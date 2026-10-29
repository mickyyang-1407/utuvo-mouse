import SwiftUI
import Observation
import AppKit
import UTUVOMouseCore
import UTUVOMouseIO

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
    @State private var model = AppModel()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(model)
                .preferredColorScheme(LaunchOptions.appearance)
                .onAppear { AppLifecycle.shared.model = model }
        }
        .defaultSize(width: 960, height: 700)
        .windowResizability(.contentMinSize)
    }
}

/// The state of the window.
@MainActor
@Observable
final class AppModel {
    var snapshots: [DeviceSnapshot] = []
    var selectedID: String?
    var isBusy = false
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

    @ObservationIgnored private let service = LogitechHIDService()
    @ObservationIgnored private var clients: [String: HIDPPClient] = [:]
    @ObservationIgnored private var clientTransports: [String: ObjectIdentifier] = [:]
    @ObservationIgnored private var clientTokens: [String: UUID] = [:]
    @ObservationIgnored private var remapperTokens: [String: UUID] = [:]
    @ObservationIgnored private var observingTokens: [String: UUID] = [:]
    @ObservationIgnored private var hasStarted = false
    @ObservationIgnored private var backupStore: BackupStoring?
    @ObservationIgnored private var backupStoreError: String?

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
            snapshots = DemoData.snapshots()
            return
        }
        service.onDevicesChanged { [weak self] _ in
            Task { @MainActor in await self?.refresh() }
        }
        service.onError { [weak self] descriptor, message in
            Task { @MainActor in self?.recordAccessError(descriptor: descriptor, message: message) }
        }
        service.start()
        Task { await refresh() }
    }

    /// Re-reads every device. Nothing is written.
    func refresh() async {
        guard !isBusy, !isRefreshing else { return }
        isRefreshing = true
        defer { isRefreshing = false }
        await readDevices()
    }

    /// Reads every device. The busy flag belongs to the caller.
    private func readDevices() async {
        if isDemo {
            snapshots = DemoData.snapshots()
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
            var snapshot = await DeviceReader.snapshot(for: transport, client: client)
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
            snapshot.issues.map { "\(snapshot.identity.productName)：\($0)" }
        }
        for snapshot in result { deniedDevices[snapshot.id] = nil }
        result.append(contentsOf: deniedDevices.values)
        diagnostics.append(contentsOf: deniedDevices.values.compactMap { snapshot in
            snapshot.accessError.map { "\(snapshot.identity.productName)：\($0)" }
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
            self.statusMessage = "選取的裝置已離線，草稿已清除"
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
        remappers.removeValue(forKey: deviceID)?.stopDispatch()
        remapperTokens[deviceID] = nil
        observingTokens[deviceID] = nil
        clients[deviceID] = nil
        clientTransports[deviceID] = nil
        clientTokens[deviceID] = nil
    }

    /// Records a device that could not be opened, so the row stays visible.
    private func recordAccessError(descriptor: HIDInterfaceDescriptor, message: String) {
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
        snapshot.needsInputMonitoring = message.contains("輸入監控")
        snapshot.issues = [message]
        deniedDevices[identity.stableID] = snapshot
        snapshots.removeAll { $0.id == identity.stableID }
        snapshots.append(snapshot)
        diagnostics.append("\(descriptor.productName)：\(message)")
    }

    /// Restores the button diversions before the app quits.
    ///
    /// Returns false when the app must stay open: a running operation is not
    /// abandoned and a failed restore is reported instead of being ignored.
    func prepareForTermination() async -> Bool {
        if isBusy {
            errorMessage = "還有操作進行中，請先完成後再離開"
            return false
        }
        isBusy = true
        defer { isBusy = false }
        var failed = false
        for remapper in remappers.values {
            do {
                let result = try await remapper.disable()
                if case .restored(let cids) = result {
                    statusMessage = "已還原 \(cids.count) 個按鍵的改道"
                }
            } catch {
                failed = true
                errorMessage = "還原按鍵改道失敗，App 將保持開啟：\(error.localizedDescription)"
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
            backupStoreError = error.localizedDescription
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
        isBusy = true
        errorMessage = nil
        statusMessage = nil
        await action()
        isBusy = false
        // The refresh runs after the busy flag is released — otherwise it would
        // be skipped and the interface would keep the old values.
        await refresh()
    }

    /// Applies a DPI value through the classic feature (MX Master 4 M).
    func applyClassicDPI(device: DeviceSnapshot, value: Int) async {
        await run {
            guard let client = self.clients[device.id] else { return }
            do {
                try await client.setDPI(value)
                self.statusMessage = "已送出 DPI \(value)，請重新整理確認"
            } catch {
                self.errorMessage = error.localizedDescription
            }
        }
    }

    /// Applies the SmartShift mode and threshold (MX Master 4 M).
    func applySmartShift(device: DeviceSnapshot, mode: Int?, threshold: Int?) async {
        await run {
            guard let client = self.clients[device.id] else { return }
            do {
                try await client.setSmartShift(mode: mode, threshold: threshold)
                self.statusMessage = "已送出 SmartShift 設定，請重新整理確認"
            } catch {
                self.errorMessage = error.localizedDescription
            }
        }
    }

    /// Applies the wheel settings (MX Master 4 M). The event target bit is kept.
    func applyWheel(device: DeviceSnapshot, inverted: Bool?, highResolution: Bool?) async {
        await run {
            guard let client = self.clients[device.id] else { return }
            do {
                try await client.setWheel(inverted: inverted, highResolution: highResolution, diverted: nil)
                self.statusMessage = "已送出滾輪設定，請重新整理確認"
            } catch {
                self.errorMessage = error.localizedDescription
            }
        }
    }

    /// Applies a HITS draft (Superstrike).
    func applyHITS(device: DeviceSnapshot, draft: HIDPPClient.HitsDraft, capabilities: HitsCapabilities) async {
        await run {
            guard let client = self.clients[device.id] else { return }
            do {
                try await client.applyHits(
                    draft: draft,
                    maxActuation: capabilities.maxActuation,
                    maxRapidTrigger: capabilities.maxRapidTrigger,
                    maxHaptics: capabilities.maxHaptics
                )
                self.statusMessage = "HITS 已送出，可讀數值已核對；快速觸發開關仍需實際確認"
            } catch {
                self.errorMessage = error.localizedDescription
            }
        }
    }

    /// Applies a compound change to the onboard profile (Superstrike).
    func applySuperstrike(device: DeviceSnapshot, changes: CompoundChanges) async {
        await run {
            guard let plan = device.plan, let baseline = device.profile else {
                self.errorMessage = "這個裝置沒有可用的板載設定檔"
                return
            }
            guard let service = await self.service(for: device) else {
                self.errorMessage = self.backupStoreError.map { "無法建立備份目錄，未寫入任何設定：\($0)" }
                    ?? "無法準備板載設定服務"
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
                self.errorMessage = "無法準備板載設定服務"
                return
            }
            let outcome = await service.activateOnboard(profileSector: sector)
            self.handle(outcome: outcome, deviceID: device.id)
        }
    }

    /// Enables the side button mapping of a mouse. Only from an explicit user action.
    func enableButtonMapping(device: DeviceSnapshot, mappings: [UInt16: MappedAction]) async {
        await run {
            guard let remapper = await self.remapper(for: device) else {
                self.errorMessage = "此裝置沒有可改道的按鍵功能"
                return
            }
            do {
                try await remapper.enable(mappings: mappings)
                self.statusMessage = "已啟用側鍵改道"
            } catch {
                self.errorMessage = error.localizedDescription
            }
        }
    }

    /// Restores the original reporting state of the diverted controls.
    func disableButtonMapping(device: DeviceSnapshot) async {
        await run {
            guard let remapper = await self.remapper(for: device) else { return }
            do {
                try await remapper.disable()
                self.statusMessage = "已停用側鍵改道並還原原本狀態"
            } catch {
                self.errorMessage = error.localizedDescription
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
        let root = (try? DiversionStateStore.applicationSupportRoot())
            ?? URL(fileURLWithPath: NSTemporaryDirectory())
        let remapper = MXButtonRemapper(
            client: client,
            reprogram: reprogram,
            store: DiversionStateStore(root: root),
            deviceID: device.id
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
        case .applied:
            self.uncertain[deviceID] = nil
            self.uncertainProfileSectors[deviceID] = nil
            self.statusMessage = outcome.summary
        case .needsOnboardSelection:
            self.errorMessage = outcome.summary
        case .rejectedStale:
            self.errorMessage = outcome.summary
        case .backupFailed:
            self.uncertain[deviceID] = outcome.summary
            self.errorMessage = outcome.summary
        case .uncertain:
            self.uncertain[deviceID] = outcome.summary
            self.uncertainProfileSectors[deviceID] = profileSector
            self.errorMessage = outcome.summary
        case .failed:
            self.errorMessage = outcome.summary
        }
    }
}

struct ContentView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        VStack(spacing: 0) {
            topBar
            Divider()
            HSplitView {
                sidebar
                    .frame(minWidth: 180, idealWidth: 200, maxWidth: 230)
                detail
                    .frame(minWidth: 480)
            }
            Divider()
            statusBar
        }
        .frame(minWidth: 760, minHeight: 600)
        .task { model.start() }
    }

    private var topBar: some View {
        HStack(spacing: 12) {
            Image(systemName: "computermouse")
                .font(.title2)
                .foregroundStyle(.secondary)
            Text("UTUVO Mouse")
                .font(.headline)
            if model.isDemo {
                Label("示範模式", systemImage: "exclamationmark.triangle.fill")
                    .labelStyle(.titleAndIcon)
                    .font(.callout)
                    .foregroundStyle(.orange)
                    .help("所有數值都是合成資料，未連接任何裝置。")
            }
            Spacer()
            Button {
                Task { await model.refresh() }
            } label: {
                if model.isBusy {
                    ProgressView().controlSize(.small)
                } else {
                    Label("重新整理", systemImage: "arrow.clockwise")
                }
            }
            .disabled(model.isBusy)
            .keyboardShortcut("r", modifiers: .command)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    private var sidebar: some View {
        List(selection: Bindable(model).selectedID) {
            Section("裝置") {
                if model.mice.isEmpty {
                    Text("沒有偵測到支援的滑鼠")
                        .foregroundStyle(.secondary)
                }
                ForEach(model.mice) { snapshot in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(snapshot.identity.model.rawValue)
                        HStack(spacing: 4) {
                            Text(snapshot.identity.transport.rawValue)
                            if snapshot.needsInputMonitoring {
                                Image(systemName: "lock.fill").foregroundStyle(.orange)
                            }
                            if model.uncertain[snapshot.id] != nil {
                                Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                            }
                        }
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    }
                    .tag(snapshot.id)
                }
            }
            if !model.diagnostics.isEmpty {
                Section("診斷") {
                    ForEach(model.diagnostics, id: \.self) { line in
                        Text(line)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .listStyle(.sidebar)
    }

    @ViewBuilder
    private var detail: some View {
        if let snapshot = model.selected {
            ScrollView {
                DeviceDetailView(snapshot: snapshot)
                    .padding(16)
            }
        } else {
            VStack(spacing: 8) {
                Image(systemName: "mouse")
                    .font(.system(size: 36))
                    .foregroundStyle(.tertiary)
                Text("請先連接 MX Master 4 M 或 PRO X2 SUPERSTRIKE")
                    .foregroundStyle(.secondary)
                Text("連上滑鼠後，這裡會顯示它的設定。")
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
                Text(model.mice.isEmpty ? "選擇滑鼠以調整設定" : "偵測到 \(model.mice.count) 支滑鼠")
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
