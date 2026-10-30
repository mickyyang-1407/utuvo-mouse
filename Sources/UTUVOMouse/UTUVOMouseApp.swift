import SwiftUI
import Observation
import AppKit
import UTUVOMouseCore
import UTUVOMouseIO
import UTUVOMouseSupport

/// Holds the model for the application delegate.
@MainActor
final class AppLifecycle {
    static let shared = AppLifecycle()
    weak var model: AppModel?
}

/// Restores the button diversions before the app quits.
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        Task { @MainActor in
            let finished = await AppLifecycle.shared.model?.prepareForTermination() ?? true
            NSApp.reply(toApplicationShouldTerminate: finished)
        }
        return .terminateLater
    }
}

struct UTUVOMouseApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @State private var model: AppModel
    @State private var settings: SettingsModel

    init() {
        let model = AppModel()
        let settings = SettingsModel(
            exitCoordinator: model.exitCoordinator,
            isDemo: model.isDemo,
            mappingPreferences: model.mappingPreferences,
            languagePreferenceStore: AppLocalization.preferenceStore
        )
        // The updater runs the device cleanup before the installer takes over.
        settings.updates?.setCleanup { await model.restoreDiversions() }
        _model = State(initialValue: model)
        _settings = State(initialValue: settings)
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(model)
                .environment(settings)
                .preferredColorScheme(LaunchOptions.appearance)
                .onAppear { AppLifecycle.shared.model = model }
        }
        .defaultSize(width: 1040, height: 760)
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentMinSize)

        Settings {
            SettingsView()
                .environment(settings)
                .preferredColorScheme(LaunchOptions.appearance)
        }
        .commands {
            CommandGroup(replacing: .appSettings) {
                SettingsLink { Text(AppLocalization.text("settings.openSettings")) }
                    .keyboardShortcut(",", modifiers: .command)
            }
            CommandGroup(after: .appInfo) {
                if let updates = settings.updates {
                    Button(AppLocalization.text("settings.update.languageMenu")) { updates.checkForUpdates() }
                        .disabled(!updates.canCheckForUpdates)
                } else {
                    Button(AppLocalization.text("settings.update.languageMenu")) {}
                        .disabled(true)
                }
            }
        }
    }
}

/// The state of the window.
@MainActor
@Observable
final class AppModel {
    let actionRing = ActionRingController(isDemo: LaunchOptions.demoMode)
    var snapshots: [DeviceSnapshot] = []
    var selectedID: String?
    var isBusy = false
    var isScanning = false
    @ObservationIgnored private var isRefreshing = false
    var statusMessage: String?
    var errorMessage: String?
    /// Endpoints that are not usable as a mouse, for example a receiver.
    var diagnostics: [String] = []
    /// Last access failures stay actionable until a successful read replaces them.
    @ObservationIgnored private var deniedDevices: [String: DeviceSnapshot] = [:]
    /// Devices whose last write could not be confirmed.
    private(set) var uncertain: [String: String] = [:]
    @ObservationIgnored private var uncertainProfileSectors: [String: Int] = [:]

    let isDemo = LaunchOptions.demoMode

    /// The shared exit gate. The quit path and the update path both use it, so
    /// a device write can never slip in between the cleanup and the exit.
    let exitCoordinator = AppExitCoordinator()

    /// Versioned app-only mapping preferences shared with Settings.
    let mappingPreferences: MXMappingPreferences
    @ObservationIgnored private let mappingRestorePolicy: MXMappingRestorePolicy

    @ObservationIgnored private let service = LogitechHIDService()
    @ObservationIgnored private var clients: [String: HIDPPClient] = [:]
    @ObservationIgnored private var clientTransports: [String: ObjectIdentifier] = [:]
    @ObservationIgnored private var clientTokens: [String: UUID] = [:]
    @ObservationIgnored private var remapperTokens: [String: UUID] = [:]
    @ObservationIgnored private var observingTokens: [String: UUID] = [:]
    @ObservationIgnored private var hasStarted = false
    @ObservationIgnored private var backupStore: BackupStoring?
    @ObservationIgnored private var backupStoreError: String?

    init() {
        let preferences: MXMappingPreferences
        if LaunchOptions.demoMode {
            preferences = MXMappingPreferences(store: MemoryMXMappingPreferenceStore())
        } else if let fileURL = try? FileMXMappingPreferenceStore.applicationSupportFileURL() {
            preferences = MXMappingPreferences(store: FileMXMappingPreferenceStore(fileURL: fileURL))
        } else {
            preferences = MXMappingPreferences(store: nil, unavailableReason: AppLocalization.text("error.appSupportDirectory"))
        }
        self.mappingPreferences = preferences
        self.mappingRestorePolicy = MXMappingRestorePolicy(preferences: preferences)
    }

    /// The devices the picker shows: the two mice, never the bare receiver.
    var mice: [DeviceSnapshot] {
        snapshots.filter { $0.identity.model == .mxMaster4 || $0.identity.model == .superstrike }
    }

    var selected: DeviceSnapshot? {
        if let selectedID, let match = mice.first(where: { $0.id == selectedID }) { return match }
        return mice.first
    }

    /// Starts the scanner and loads the first state.
    func start() {
        guard !hasStarted else { return }
        hasStarted = true
        if isDemo {
            // The demo never touches IOKit: no manager, no service, no device.
            snapshots = DemoData.snapshots(language: AppLocalization.localizer.language)
            selectedID = mice.first?.id
            return
        }
        isScanning = true
        service.onDevicesChanged { [weak self] _ in
            Task { @MainActor in await self?.refresh() }
        }
        service.onError { [weak self] descriptor, failure in
            Task { @MainActor in self?.recordAccessError(descriptor: descriptor, failure: failure) }
        }
        service.start()
        Task {
            await refresh()
            isScanning = false
        }
    }

    /// Re-reads every device and, only when opted in, checks saved MX mapping intent.
    func refresh() async {
        guard !isBusy, !isRefreshing else { return }
        // No new device traffic while the app is shutting down.
        guard exitCoordinator.allowsDeviceOperations else { return }
        isRefreshing = true
        defer { isRefreshing = false }
        await readDevices()
        await restoreSavedButtonMappingsIfRequested()
    }

    /// Reads every device. The busy flag belongs to the caller.
    private func readDevices() async {
        if isDemo {
            snapshots = DemoData.snapshots(language: AppLocalization.localizer.language)
            return
        }
        var result: [DeviceSnapshot] = []
        let transports = service.devices
        let connectedIDs = Set(transports.map { DeviceReader.identity(for: $0).stableID })
        // Invalidate removed channels even when no replacement was matched yet.
        // A disconnected channel must never receive cleanup writes on Quit.
        for deviceID in Set(clients.keys).subtracting(connectedIDs) {
            invalidateConnection(deviceID)
        }
        for transport in transports {
            let identity = DeviceReader.identity(for: transport)
            guard let client = client(for: transport, identity: identity) else { continue }
            var snapshot = await DeviceReader.snapshot(for: transport, client: client, language: AppLocalization.localizer.language)
            // A different current profile cannot resolve an earlier flash result.
            if snapshot.isStateAuthoritative,
               let sector = uncertainProfileSectors[snapshot.id],
               snapshot.profile?.sector != sector {
                if let plan = snapshot.plan,
                   let onboard = try? await OnboardProfilesClient.resolve(for: client),
                   let bytes = try? await onboard.readSector(sector, size: plan.info.sectorSize) {
                    snapshot.isStateAuthoritative = ProfileSector(bytes: bytes, sector: sector).hasValidCRC
                } else {
                    snapshot.isStateAuthoritative = false
                }
            }
            result.append(snapshot)
        }
        // Endpoints that are not a mouse stay in the diagnostics.
        diagnostics = result.filter { $0.identity.model == .receiver }.flatMap { snapshot in
            snapshot.issues.map { "\(snapshot.identity.productName): \($0)" }
        }
        for snapshot in result { deniedDevices[snapshot.id] = nil }
        result.append(contentsOf: deniedDevices.values)
        diagnostics.append(contentsOf: deniedDevices.values.compactMap { snapshot in
            snapshot.accessError.map { "\(snapshot.identity.productName): \($0)" }
        })
        snapshots = result
        // Only an authoritative read clears the warning of a device.
        for snapshot in result where snapshot.isStateAuthoritative {
            uncertain[snapshot.id] = nil
            uncertainProfileSectors[snapshot.id] = nil
        }
        if let selectedID, !mice.contains(where: { $0.id == selectedID }) {
            // The device is gone: the draft that belonged to it is dropped.
            self.selectedID = nil
            clients[selectedID] = nil
            clientTransports[selectedID] = nil
            self.statusMessage = AppLocalization.text("app.deviceOfflineDraftCleared")
        }
        if selectedID == nil, let firstMouse = mice.first {
            selectedID = firstMouse.id
        }
    }

    /// One bounded restore attempt per eligible MX connection token.
    private func restoreSavedButtonMappingsIfRequested() async {
        guard !isDemo,
              mappingPreferences.storageReady,
              mappingPreferences.restoreEnabledAtLaunch,
              !isBusy,
              exitCoordinator.allowsDeviceOperations else { return }

        for snapshot in mice {
            guard let token = snapshot.connectionEpoch else { continue }
            if mappingRestorePolicy.hasHandledConnection(deviceID: snapshot.id, connectionToken: token) {
                continue
            }
            guard let saved = mappingPreferences.savedMapping(for: snapshot.id), saved.enabledIntent else { continue }
            let targetCIDs = saved.choices.compactMap { cid, action in action == .native ? nil : cid }
            let availableCIDs = Set(snapshot.reprogControls
                .filter { $0.isDivertable && !$0.isVirtual }
                .map(\.cid))
            let prerequisitesAuthoritative = snapshot.isStateAuthoritative && snapshot.accessError == nil
            let capabilitiesComplete = prerequisitesAuthoritative
                && snapshot.accessError == nil
                && !targetCIDs.isEmpty
                && targetCIDs.allSatisfy { MXButtonRemapper.allowedCIDs.contains($0) && availableCIDs.contains($0) }
            let permissionReady = MXButtonRemapper.hasAccessibilityPermission
            let deviceStateCertain = uncertain[snapshot.id] == nil
            var preparedRemapper: MXButtonRemapper?
            var adapterReady = false
            var leaseCertain = true
            var leaseOwnedByCurrentSession = false

            // Only resolve the read-only remapper adapter after the snapshot is
            // authoritative and every ordinary precondition is ready. A partial
            // snapshot waits for discovery without spending the token attempt.
            if prerequisitesAuthoritative,
               snapshot.identity.model == .mxMaster4,
               permissionReady,
               capabilitiesComplete,
               deviceStateCertain,
               exitCoordinator.allowsDeviceOperations,
               !isBusy {
                preparedRemapper = await remapper(for: snapshot)
                if let remapper = preparedRemapper {
                    adapterReady = true
                    leaseOwnedByCurrentSession = !remapper.ownedControls.isEmpty
                        && remapper.uncertainControls.isEmpty
                    leaseCertain = leaseOwnedByCurrentSession
                        || (remapper.ownedControls.isEmpty
                            && remapper.uncertainControls.isEmpty
                            && !remapper.hasLease)
                }
            }

            // The cleanup/operation gate may have changed while the adapter was
            // resolving. Do not turn a transient lifecycle wait into a failure.
            guard !isBusy, exitCoordinator.allowsDeviceOperations else { return }
            guard !mappingRestorePolicy.hasHandledConnection(deviceID: snapshot.id, connectionToken: token) else {
                continue
            }
            let context = MXMappingRestoreContext(
                deviceID: snapshot.id,
                connectionToken: token,
                isMXMaster4: snapshot.identity.model == .mxMaster4,
                permissionReady: permissionReady,
                capabilitiesComplete: capabilitiesComplete,
                prerequisitesAuthoritative: prerequisitesAuthoritative,
                adapterReady: adapterReady,
                lifecycleAllowsOperations: exitCoordinator.allowsDeviceOperations,
                deviceStateCertain: deviceStateCertain,
                leaseCertain: leaseCertain,
                leaseOwnedByCurrentSession: leaseOwnedByCurrentSession
            )
            let mayApply = prerequisitesAuthoritative
                && context.isMXMaster4
                && context.permissionReady
                && context.capabilitiesComplete
                && context.lifecycleAllowsOperations
                && context.deviceStateCertain
                && context.adapterReady
                && context.leaseCertain
                && !context.leaseOwnedByCurrentSession
            if mayApply { isBusy = true }
            let remapperForApply = preparedRemapper
            let result = await mappingRestorePolicy.restoreIfAllowed(context: context) { savedChoices in
                guard let remapper = remapperForApply else { throw DiversionError.reconnectRequired }
                let actions = Dictionary(uniqueKeysWithValues: savedChoices.map { cid, action in
                    (cid, MappedAction(rawValue: action.rawValue) ?? .native)
                })
                try await remapper.enable(mappings: actions)
            }
            if mayApply { isBusy = false }
            if let messages = MXMappingRestoreMessages.update(for: result, language: AppLocalization.localizer.language) {
                statusMessage = messages.statusMessage
                errorMessage = messages.errorMessage
            }
        }
    }

    /// One client per physical connection; a hot plug replaces it.
    private func client(for transport: IOKitHIDTransport, identity: DeviceIdentity) -> HIDPPClient? {
        let identifier = ObjectIdentifier(transport)
        let token = transport.connectionToken
        if let existing = clients[identity.stableID],
           clientTransports[identity.stableID] == identifier,
           clientTokens[identity.stableID] == token {
            return existing
        }
        invalidateConnection(identity.stableID)
        // The transport was replaced: the old client belongs to a channel that
        // is gone, so a new one is built for the new channel.
        guard let created = try? HIDPPClient(
            transport: transport,
            deviceIndex: DeviceReader.deviceIndex(for: transport),
            timeout: .milliseconds(600)
        ) else { return nil }
        clients[identity.stableID] = created
        clientTransports[identity.stableID] = identifier
        clientTokens[identity.stableID] = token
        return created
    }

    /// Stops the previous connection immediately; its persisted lease is retained.
    /// A new connection needs an explicit Enable and fresh ownership checks.
    private func invalidateConnection(_ deviceID: String) {
        actionRing.cancel()
        remappers.removeValue(forKey: deviceID)?.stopDispatch()
        remapperTokens[deviceID] = nil
        observingTokens[deviceID] = nil
        clients[deviceID] = nil
        clientTransports[deviceID] = nil
        clientTokens[deviceID] = nil
    }

    func mappingPresentationKey(for snapshot: DeviceSnapshot) -> String {
        let saved = mappingPreferences.savedMapping(for: snapshot.id)
        let remapper = remappers[snapshot.id].flatMap { remapperTokens[snapshot.id] == snapshot.connectionEpoch ? $0 : nil }
        let state = MXMappingPresentationPolicy.state(
            savedEnabledIntent: saved?.enabledIntent == true,
            hasSavedMapping: saved != nil,
            activeControlCount: remapper?.ownedControls.count ?? 0,
            uncertainControlCount: max(remapper?.uncertainControls.count ?? 0, uncertain[snapshot.id] == nil ? 0 : 1),
            hasLease: remapper?.hasLease == true
        )
        return switch state {
        case .active: "device.mapping.state.active"
        case .uncertain: "device.mapping.state.uncertain"
        case .previousLease: "device.mapping.state.previousLease"
        case .savedIntentOnly: "device.mapping.state.savedIntentOnly"
        case .savedDisabled: "device.mapping.state.savedDisabled"
        case .noSavedMapping: "device.mapping.state.none"
        }
    }

    /// Records a device that could not be opened, so the row stays visible.
    private func recordAccessError(descriptor: HIDInterfaceDescriptor, failure: HIDAccessFailure) {
        let message = failure.message(language: AppLocalization.localizer.language)
        let identity = DeviceIdentity(
            stableID: StableIdentifier.make(
                vendorID: descriptor.vendorID,
                productID: descriptor.productID,
                seed: descriptor.physicalKey
            ),
            model: DeviceReader.detectModel(features: [:], productID: descriptor.productID),
            vendorID: descriptor.vendorID,
            productID: descriptor.productID,
            transport: descriptor.transportKind,
            deviceIndex: descriptor.productID == TargetProducts.receiver ? 0x01 : 0xFF,
            productName: descriptor.productName
        )
        var snapshot = DeviceSnapshot(identity: identity)
        invalidateConnection(identity.stableID)
        snapshot.accessError = message
        snapshot.needsInputMonitoring = failure.requiresInputMonitoring
        snapshot.issues = [message]
        deniedDevices[identity.stableID] = snapshot
        snapshots.removeAll { $0.id == identity.stableID }
        snapshots.append(snapshot)
        diagnostics.append("\(descriptor.productName): \(message)")
    }

    /// Restores the button diversions before the app quits.
    ///
    /// Returns false when the app must stay open: a running operation is not
    /// abandoned and a failed restore is reported instead of being ignored.
    func prepareForTermination() async -> Bool {
        // The update path already cleaned up: the installer may take over.
        if exitCoordinator.phase == .ready { return true }
        return await exitCoordinator.performExitSequence { await self.restoreDiversions() }
    }

    /// Restores the original reporting state of the diverted controls.
    ///
    /// This is the cleanup both the quit path and the update path run.
    func restoreDiversions() async -> Bool {
        actionRing.cancel()
        if isBusy {
            errorMessage = AppLocalization.text("app.operationInProgress")
            return false
        }
        isBusy = true
        defer { isBusy = false }
        var failed = false
        for remapper in remappers.values {
            do {
                let result = try await remapper.disable()
                if case .restored(let cids) = result {
                    statusMessage = AppLocalization.text("app.restoreDiversions.restored", cids.count)
                }
            } catch {
                failed = true
                errorMessage = AppLocalization.text("app.restoreDiversions.failed", AppLocalization.errorMessage(error))
            }
        }
        return !failed
    }

    /// Opens the Accessibility pane. It grants nothing, it only shows the pane.
    func openAccessibilitySettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") else { return }
        NSWorkspace.shared.open(url)
    }

    /// Opens the Input Monitoring pane. Only ever called from a user button.
    func openInputMonitoringSettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent") else { return }
        NSWorkspace.shared.open(url)
    }

    /// The backup store. There is no temporary fallback: without a store nothing
    /// is written to a device.
    private func resolveBackupStore() -> BackupStoring? {
        if let backupStore { return backupStore }
        do {
            let root = try FileBackupStore.applicationSupportRoot()
            let store = FileBackupStore(root: root)
            backupStore = store
            return store
        } catch {
            backupStoreError = AppLocalization.errorMessage(error)
            return nil
        }
    }

    private func service(for device: DeviceSnapshot) async -> SuperstrikeService? {
        guard let client = self.clients[device.id] else { return nil }
        guard let onboard = try? await OnboardProfilesClient.resolve(for: client) else { return nil }
        guard let store = resolveBackupStore() else { return nil }
        return SuperstrikeService(client: client, onboard: onboard, backupStore: store, deviceID: device.id)
    }

    /// Runs one action while the app is busy. Nothing else can run at the same time.
    private func run(_ action: @escaping () async -> Void) async {
        guard !isBusy else { return }
        // From the first cleanup step until the installer takes over, no new
        // device write is allowed through.
        guard exitCoordinator.allowsDeviceOperations else {
            errorMessage = SettingsStrings.exit.writeRejected
            return
        }
        isBusy = true
        errorMessage = nil
        statusMessage = nil
        await action()
        let actionError = errorMessage
        isBusy = false
        // The refresh runs after the busy flag is released — otherwise it would
        // be skipped and the interface would keep the old values.
        await refresh()
        errorMessage = MXMappingSetupMessages.preserveManualError(afterRefresh: actionError, refreshError: errorMessage)
    }

    /// Applies a DPI value through the classic feature (MX Master 4 M).
    func applyClassicDPI(device: DeviceSnapshot, value: Int) async {
        await run {
            guard let client = self.clients[device.id] else { return }
            do {
                try await client.setDPI(value)
                self.statusMessage = AppLocalization.text("app.dpi.sent", value)
            } catch {
                self.errorMessage = AppLocalization.errorMessage(error)
            }
        }
    }

    /// Applies the SmartShift mode and threshold (MX Master 4 M).
    func applySmartShift(device: DeviceSnapshot, mode: Int?, threshold: Int?) async {
        await run {
            guard let client = self.clients[device.id] else { return }
            do {
                try await client.setSmartShift(mode: mode, threshold: threshold)
                self.statusMessage = AppLocalization.text("app.smartShiftSent")
            } catch {
                self.errorMessage = AppLocalization.errorMessage(error)
            }
        }
    }

    /// Applies the wheel settings (MX Master 4 M). The event target bit is kept.
    func applyWheel(device: DeviceSnapshot, inverted: Bool?, highResolution: Bool?) async {
        await run {
            guard let client = self.clients[device.id] else { return }
            do {
                try await client.setWheel(inverted: inverted, highResolution: highResolution, diverted: nil)
                self.statusMessage = AppLocalization.text("app.wheelSent")
            } catch {
                self.errorMessage = AppLocalization.errorMessage(error)
            }
        }
    }

    /// Saves HITS in the active onboard profile, with backup and live readback.
    func applyHITS(device: DeviceSnapshot, draft: HIDPPClient.HitsDraft, capabilities: HitsCapabilities) async {
        await applySuperstrike(device: device, changes: CompoundChanges(hits: [draft]))
    }

    /// Applies a compound change to the onboard profile (Superstrike).
    func applySuperstrike(device: DeviceSnapshot, changes: CompoundChanges) async {
        await run {
            guard let plan = device.plan, let baseline = device.profile else {
                self.errorMessage = AppLocalization.text("app.profileUnavailable")
                return
            }
            guard let service = await self.service(for: device) else {
                self.errorMessage = self.backupStoreError.map { AppLocalization.text("app.backupServiceUnavailable", $0) }
                    ?? AppLocalization.text("app.profileServiceUnavailable")
                return
            }
            let outcome = await service.applyCompound(plan: plan, baseline: baseline, changes: changes)
            self.handle(outcome: outcome, deviceID: device.id, profileSector: plan.storedSector)
        }
    }

    /// Switches the device into onboard mode and selects a profile. Explicit user action.
    func activateOnboard(device: DeviceSnapshot, sector: Int) async {
        await run {
            guard let service = await self.service(for: device) else {
                self.errorMessage = AppLocalization.text("app.profileServiceUnavailable")
                return
            }
            let outcome = await service.activateOnboard(profileSector: sector)
            self.handle(outcome: outcome, deviceID: device.id)
        }
    }

    /// Enables the side button mapping of a mouse. Only from an explicit user action.
    func enableButtonMapping(device: DeviceSnapshot, mappings: [UInt16: MappedAction]) async {
        await run {
            guard !mappings.filter({ $0.value != .native }).isEmpty else {
                self.errorMessage = AppLocalization.text("app.mapping.chooseAction")
                return
            }
            if let token = device.connectionEpoch {
                self.mappingRestorePolicy.noteExplicitUserAction(deviceID: device.id, connectionToken: token)
            }
            guard let remapper = await self.remapper(for: device) else {
                self.errorMessage = MXMappingSetupMessages.unavailableFallback(
                    existingFailure: self.errorMessage,
                    language: AppLocalization.localizer.language
                )
                return
            }
            let savedChoices = mappings.mapValues { MXMappingAction(rawValue: $0.rawValue) ?? .native }
            do {
                try self.mappingPreferences.validateEnable(deviceID: device.id, choices: savedChoices)
            } catch {
                self.errorMessage = AppLocalization.text("app.mapping.saveRejected", AppLocalization.errorMessage(error))
                return
            }
            do {
                if !remapper.ownedControls.isEmpty {
                    _ = try await remapper.disable()
                }
                try await remapper.enable(mappings: mappings)
                do {
                    try self.mappingPreferences.recordVerifiedEnable(deviceID: device.id, choices: savedChoices)
                } catch {
                    do {
                        _ = try await remapper.disable()
                        self.errorMessage = AppLocalization.text("app.mapping.saveRollback", AppLocalization.errorMessage(error))
                    } catch {
                        self.uncertain[device.id] = AppLocalization.errorMessage(error)
                        self.errorMessage = AppLocalization.text("app.mapping.saveAndRollbackUncertain", AppLocalization.errorMessage(error))
                    }
                    return
                }
                self.statusMessage = AppLocalization.text("app.mapping.enabled")
            } catch {
                self.errorMessage = AppLocalization.errorMessage(error)
            }
        }
    }

    /// Reconfigure the same owned lease, preserving the saved side-button choices.
    func setActionRingEnabled(device: DeviceSnapshot, enabled: Bool) async {
        let saved = mappingPreferences.savedMapping(for: device.id)
        var choices = saved?.enabledIntent == true ? (saved?.choices.mapValues {
            MappedAction(rawValue: $0.rawValue) ?? .native
        } ?? [:]) : [:]
        choices[MXButtonRemapper.ringCID] = enabled ? .actionsRing : .native
        if choices.values.contains(where: { $0 != .native }) {
            await enableButtonMapping(device: device, mappings: choices)
        } else {
            await disableButtonMapping(device: device)
        }
    }

    func isActionRingEnabled(for device: DeviceSnapshot) -> Bool {
        guard remapperTokens[device.id] == device.connectionEpoch,
              let mapper = remappers[device.id] else { return false }
        return mapper.ownedControls.contains(MXButtonRemapper.ringCID)
            && !mapper.uncertainControls.contains(MXButtonRemapper.ringCID)
    }

    /// Restores the original reporting state of the diverted controls.
    func disableButtonMapping(device: DeviceSnapshot) async {
        await run {
            guard let remapper = await self.remapper(for: device) else {
                self.errorMessage = AppLocalization.text("app.mapping.disconnected")
                return
            }
            if let token = device.connectionEpoch {
                self.mappingRestorePolicy.noteExplicitUserAction(deviceID: device.id, connectionToken: token)
            }
            do {
                let result = try await remapper.disable()
                if case .nothingOwned = result {
                    guard !remapper.hasLease else {
                        self.errorMessage = AppLocalization.text("app.mapping.previousLease")
                        return
                    }
                    do {
                        try self.mappingPreferences.clearEnabledIntent(deviceID: device.id)
                    } catch {
                        self.errorMessage = AppLocalization.text("app.mapping.clearIntentFailed", AppLocalization.errorMessage(error))
                        return
                    }
                    self.statusMessage = AppLocalization.text("app.mapping.intentCleared")
                    return
                }
                do {
                    try self.mappingPreferences.clearEnabledIntent(deviceID: device.id)
                } catch {
                    self.errorMessage = AppLocalization.text("app.mapping.clearIntentFailed", AppLocalization.errorMessage(error))
                    return
                }
                self.statusMessage = AppLocalization.text("app.mapping.restored")
            } catch {
                self.errorMessage = AppLocalization.errorMessage(error)
            }
        }
    }

    @ObservationIgnored private var remappers: [String: MXButtonRemapper] = [:]

    private func remapper(for device: DeviceSnapshot) async -> MXButtonRemapper? {
        let token = device.connectionEpoch
        if let existing = remappers[device.id], remapperTokens[device.id] == token {
            return existing
        }
        // The channel was replaced: the old remapper stops dispatching and is not
        // restored on a channel that is gone. Its lease stays as the evidence.
        remappers[device.id]?.stopDispatch()
        guard let client = self.clients[device.id] else { return nil }
        guard let reprogram = try? await ReprogramControlsClient.resolve(for: client) else { return nil }
        let root: URL
        do {
            root = try DiversionStateStore.applicationSupportRoot()
        } catch {
            errorMessage = MXMappingSetupMessages.storageFailure(error.localizedDescription, language: AppLocalization.localizer.language)
            return nil
        }
        let remapper = MXButtonRemapper(
            client: client,
            reprogram: reprogram,
            store: DiversionStateStore(root: root),
            deviceID: device.id,
            ringEvent: { [weak self] down in
                Task { @MainActor in
                    guard let self, self.remapperTokens[device.id] == token else { return }
                    if down == true, self.isBusy || !self.exitCoordinator.allowsDeviceOperations { return }
                    if down == true, self.remappers[device.id]?.ownedControls.contains(MXButtonRemapper.ringCID) != true { return }
                    self.actionRing.input(down)
                }
            }
        )
        remappers[device.id] = remapper
        remapperTokens[device.id] = token
        if observingTokens[device.id] != token {
            observingTokens[device.id] = token
            client.addObserver { [weak remapper] frame in
                remapper?.handle(frame: frame)
            }
        }
        return remapper
    }

    private func handle(outcome: ApplyOutcome, deviceID: String, profileSector: Int? = nil) {
        switch outcome {
        case .applied, .onboardActivated:
            self.uncertain[deviceID] = nil
            self.uncertainProfileSectors[deviceID] = nil
            self.statusMessage = AppLocalization.applyOutcomeSummary(outcome)
        case .needsOnboardSelection:
            self.errorMessage = AppLocalization.applyOutcomeSummary(outcome)
        case .rejectedStale:
            self.errorMessage = AppLocalization.applyOutcomeSummary(outcome)
        case .backupFailed, .backupFailedReason:
            self.uncertain[deviceID] = AppLocalization.applyOutcomeSummary(outcome)
            self.errorMessage = AppLocalization.applyOutcomeSummary(outcome)
        case .uncertain, .uncertainReason:
            self.uncertain[deviceID] = AppLocalization.applyOutcomeSummary(outcome)
            self.uncertainProfileSectors[deviceID] = profileSector
            self.errorMessage = AppLocalization.applyOutcomeSummary(outcome)
        case .failed, .failedReason:
            self.errorMessage = AppLocalization.applyOutcomeSummary(outcome)
        }
    }
}

struct ContentView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        HStack(spacing: 0) {
            sidebar.frame(width: 210)
            VStack(spacing: 0) {
                HStack {
                    if model.isDemo { Text(AppLocalization.text("app.demo")).foregroundStyle(.orange) }
                    Spacer()
                    Button { Task { await model.refresh() } } label: {
                        Image(systemName: "arrow.clockwise").frame(width: 26, height: 24)
                    }
                    .disabled(model.isBusy)
                    .help(AppLocalization.text("app.refresh"))
                    .accessibilityLabel(AppLocalization.text("app.refresh"))
                    .keyboardShortcut("r", modifiers: .command)
                    SettingsLink { Image(systemName: "slider.horizontal.3").frame(width: 26, height: 24) }
                        .help(SettingsStrings.exit.settingsHelp)
                        .accessibilityLabel(SettingsStrings.exit.settingsHelp)
                }
                .buttonStyle(.borderless)
                .padding(.horizontal, 28).padding(.top, 17).padding(.bottom, 2)
                detail
                statusBar
            }
            .background(MouseTheme.canvas)
        }
        .tint(MouseTheme.accent)
        .groupBoxStyle(MouseGroupStyle())
        .frame(minWidth: 820, minHeight: 640)
        .task { model.start() }
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 3) {
                Text("UTUVO").font(.system(size: 11, weight: .semibold)).tracking(3).foregroundStyle(.secondary)
                Text("Mouse").font(.system(size: 30, weight: .semibold)).tracking(-1)
            }.padding(.horizontal, 23).padding(.top, 52).padding(.bottom, 38)
            Text(AppLocalization.text("app.devices")).font(.system(size: 11, weight: .medium)).foregroundStyle(.secondary)
                .padding(.horizontal, 23).padding(.bottom, 13)
            ForEach(model.mice) { snapshot in
                Button { model.selectedID = snapshot.id } label: {
                    HStack(spacing: 11) {
                        MouseIllustration(model: snapshot.identity.model, compact: true).frame(width: 31, height: 45)
                        VStack(alignment: .leading, spacing: 5) {
                            Text(snapshot.identity.model == .mxMaster4 ? "MX Master 4" : "SUPERSTRIKE")
                                .font(.system(size: 12, weight: .semibold))
                            Text(snapshot.identity.transport.displayTitle(language: AppLocalization.localizer.language))
                                .font(.system(size: 10)).foregroundStyle(.secondary)
                        }
                        Spacer(minLength: 0)
                        if snapshot.needsInputMonitoring || model.uncertain[snapshot.id] != nil {
                            Image(systemName: "exclamationmark.circle").foregroundStyle(.orange)
                        }
                    }
                    .padding(.horizontal, 11).padding(.vertical, 12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(model.selected?.id == snapshot.id ? MouseTheme.surface : .clear, in: RoundedRectangle(cornerRadius: 13))
                    .overlay(RoundedRectangle(cornerRadius: 13).strokeBorder(.primary.opacity(model.selected?.id == snapshot.id ? 0.06 : 0), lineWidth: 1))
                    .contentShape(RoundedRectangle(cornerRadius: 13))
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(model.selected?.id == snapshot.id ? [.isSelected] : [])
                .padding(.horizontal, 12).padding(.bottom, 6)
            }
            if model.mice.isEmpty {
                Text(AppLocalization.text(model.isScanning ? "app.scanning" : "app.noDevices"))
                    .font(.callout).foregroundStyle(.secondary).padding(23)
            }
            Spacer()
            if !model.diagnostics.isEmpty {
                DisclosureGroup(AppLocalization.text("app.diagnostics")) {
                    ForEach(model.diagnostics, id: \.self) { Text($0).font(.caption2).textSelection(.enabled) }
                }.font(.caption).foregroundStyle(.secondary).padding(18)
            }
            HStack(spacing: 7) {
                Image(systemName: "computermouse.fill").foregroundStyle(MouseTheme.accent)
                Text("UTUVO Mouse").font(.system(size: 11, weight: .medium))
            }.foregroundStyle(.secondary).padding(.horizontal, 23).padding(.bottom, 23)
        }
        .frame(maxHeight: .infinity)
        .background(.primary.opacity(0.025))
        .overlay(alignment: .trailing) { Rectangle().fill(.primary.opacity(0.06)).frame(width: 1) }
    }

    @ViewBuilder
    private var detail: some View {
        if let snapshot = model.selected {
            ScrollView {
                DeviceDetailView(snapshot: snapshot)
                    .padding(.horizontal, 28).padding(.top, 8).padding(.bottom, 24)
            }
        } else {
            VStack(spacing: 8) {
                Image(systemName: "mouse")
                    .font(.system(size: 36))
                    .foregroundStyle(.tertiary)
                Text(model.isScanning ? AppLocalization.text("app.scanning") : AppLocalization.text("app.connectHint.title"))
                    .foregroundStyle(.secondary)
                Text(AppLocalization.text("app.connectHint.detail"))
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private var statusBar: some View {
        HStack(spacing: 10) {
            if let message = model.errorMessage {
                Label(message, systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.red)
                    .lineLimit(2)
            } else if let message = model.statusMessage {
                Label(message, systemImage: "checkmark.circle")
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            } else {
                Text(model.mice.isEmpty ? AppLocalization.text("app.chooseMouse") : AppLocalization.text("app.detectedMice", model.mice.count))
                    .foregroundStyle(.tertiary)
            }
            Spacer()
        }
        .font(.callout)
        .padding(.horizontal, 14)
        .padding(.vertical, 6)
        .frame(minHeight: 28)
    }
}
