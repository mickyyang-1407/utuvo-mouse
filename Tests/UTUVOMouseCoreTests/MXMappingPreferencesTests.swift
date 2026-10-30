import Foundation
import Testing
import UTUVOMouseSupport
import UTUVOMouseCore

@Suite("MX mapping preferences and restore policy")
@MainActor
struct MXMappingPreferencesTests {
    private let deviceID = "sha256:0123456789abcdef"
    private let choices: [UInt16: MXMappingAction] = [0x0052: .copy, 0x0053: .paste]

    @Test("temporary file round-trips with restore disabled by default")
    func roundTripAndDefaultOptIn() throws {
        let (store, directory) = makeStore()
        defer { try? FileManager.default.removeItem(at: directory) }

        let empty = try store.load()
        #expect(!empty.restoreEnabledAtLaunch)
        #expect(empty.mappingsByDeviceID.isEmpty)

        let preferences = MXMappingPreferences(store: store)
        #expect(preferences.storageReady)
        preferences.setRestoreEnabledAtLaunch(true)
        try preferences.recordVerifiedEnable(deviceID: deviceID, choices: choices)

        let loaded = try store.load()
        #expect(loaded.restoreEnabledAtLaunch)
        #expect(loaded.mappingsByDeviceID[deviceID]?.choices == choices)
        #expect(loaded.mappingsByDeviceID[deviceID]?.enabledIntent == true)
    }

    @Test("rejects an unsupported CID before saving")
    func invalidCID() throws {
        let (store, directory) = makeStore()
        defer { try? FileManager.default.removeItem(at: directory) }
        let invalid = MXMappingPreferenceDocument(mappingsByDeviceID: [
            deviceID: MXSavedMapping(deviceID: deviceID, choices: [0x1234: .copy], enabledIntent: true)
        ])

        var rejected = false
        do { try store.save(invalid) } catch { rejected = true }
        #expect(rejected)
        #expect(try store.load().mappingsByDeviceID.isEmpty)
    }

    @Test("corrupt preference data disables restore and remains visible as an error")
    func corruptData() throws {
        let (store, directory) = makeStore()
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try Data("not-json".utf8).write(to: storeURL(in: directory))

        let preferences = MXMappingPreferences(store: store)
        #expect(!preferences.storageReady)
        #expect(preferences.lastError != nil)
        #expect(preferences.savedMapping(for: deviceID) == nil)
    }

    @Test("ordinary cleanup leaves enabled intent; explicit Disable clears it")
    func cleanupPreservesIntentAndDisableClearsIt() throws {
        let (store, directory) = makeStore()
        defer { try? FileManager.default.removeItem(at: directory) }
        let preferences = MXMappingPreferences(store: store)
        preferences.setRestoreEnabledAtLaunch(true)
        try preferences.recordVerifiedEnable(deviceID: deviceID, choices: choices)

        // Quit/update cleanup changes hardware only; it does not call the explicit-clear API.
        let afterCleanup = MXMappingPreferences(store: store)
        #expect(afterCleanup.savedMapping(for: deviceID)?.enabledIntent == true)
        #expect(afterCleanup.savedMapping(for: deviceID)?.choices == choices)

        try afterCleanup.clearEnabledIntent(deviceID: deviceID)
        #expect(afterCleanup.savedMapping(for: deviceID)?.enabledIntent == false)
        #expect(afterCleanup.savedMapping(for: deviceID)?.choices == choices)
        #expect(afterCleanup.restoreEnabledAtLaunch)
    }

    @Test("opt-in off never calls the remapper adapter")
    func optInOffDoesNotApply() async throws {
        let (preferences, directory) = try optedInPreferences(enabled: false)
        defer { try? FileManager.default.removeItem(at: directory) }
        let policy = MXMappingRestorePolicy(preferences: preferences)
        var calls = 0

        let result = await policy.restoreIfAllowed(context: context()) { _ in calls += 1 }
        #expect(result == .notRequested)
        #expect(calls == 0)
    }

    @Test("a different stable device ID has no saved intent and never reaches the adapter")
    func wrongDeviceIDDoesNotApply() async throws {
        let (preferences, directory) = try optedInPreferences(enabled: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let policy = MXMappingRestorePolicy(preferences: preferences)
        var calls = 0

        let result = await policy.restoreIfAllowed(
            context: context(deviceID: "sha256:fedcba9876543210")
        ) { _ in calls += 1 }
        #expect(result == .notRequested)
        #expect(calls == 0)
    }

    @Test("permission, model, capability, lease, ownership, uncertain state and lifecycle gates refuse restore")
    func unsafeContextsDoNotApply() async throws {
        let (preferences, directory) = try optedInPreferences(enabled: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let deniedContexts = [
            context(permissionReady: false),
            context(isMXMaster4: false),
            context(capabilitiesComplete: false),
            context(leaseCertain: false),
            context(foreignOwnershipDetected: true),
            context(deviceStateCertain: false),
            context(lifecycleAllowsOperations: false),
        ]

        for deniedContext in deniedContexts {
            let policy = MXMappingRestorePolicy(preferences: preferences)
            var calls = 0
            let result = await policy.restoreIfAllowed(context: deniedContext) { _ in calls += 1 }
            if case .blocked = result {
                #expect(calls == 0)
            } else {
                Issue.record("Unsafe context was not blocked: \(result)")
            }
        }
    }

    @Test("one enable per connection token; a failed attempt waits for explicit retry or reconnect")
    func boundedAttempt() async throws {
        let (preferences, directory) = try optedInPreferences(enabled: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let policy = MXMappingRestorePolicy(preferences: preferences)
        let connection = context()
        var calls = 0

        let failed = await policy.restoreIfAllowed(context: connection) { _ in
            calls += 1
            throw TestFailure.expected
        }
        #expect(failed == .failed(.external(TestFailure.expected.localizedDescription)))
        #expect(await policy.restoreIfAllowed(context: connection) { _ in calls += 1 } == .alreadyAttempted)
        #expect(calls == 1)

        let nextConnection = context(connectionToken: UUID())
        #expect(await policy.restoreIfAllowed(context: nextConnection) { _ in calls += 1 } == .restored)
        #expect(calls == 2)

        let userAction = context(connectionToken: UUID())
        policy.noteExplicitUserAction(deviceID: deviceID, connectionToken: userAction.connectionToken)
        #expect(await policy.restoreIfAllowed(context: userAction) { _ in calls += 1 } == .alreadyAttempted)
        #expect(calls == 2)
    }

    @Test("storage write failure is surfaced and disables persistence")
    func writeFailureIsVisible() {
        let store = FailingMXMappingPreferenceStore()
        let preferences = MXMappingPreferences(store: store)
        preferences.setRestoreEnabledAtLaunch(true)
        #expect(!preferences.restoreEnabledAtLaunch)
        #expect(!preferences.storageReady)
        #expect(preferences.lastError != nil)
        #expect(preferences.lastErrorReason?.message(language: .english).contains("injected preference write failure") == true)
    }

    @Test("restore failures retain typed diversion reasons for localized presentation")
    func restoreFailureKeepsTypedReason() async throws {
        let (preferences, directory) = try optedInPreferences(enabled: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let policy = MXMappingRestorePolicy(preferences: preferences)

        let result = await policy.restoreIfAllowed(context: context()) { _ in
            throw DiversionError.accessibilityRequired
        }
        #expect(result == .failed(.diversion(.accessibilityRequired)))
        let message = MXMappingRestoreMessages.update(for: result, language: .english)?.errorMessage
        #expect(message?.contains("Accessibility permission is required") == true)
        #expect(message?.contains("輔助使用") == false)
    }

    @Test("manual remapper setup preserves the storage cause through refresh fallback")
    func manualSetupFailureRemainsVisible() {
        let cause = "injected storage permission failure"
        let englishFailure = MXMappingSetupMessages.storageFailure(cause, language: .english)
        #expect(englishFailure.contains(cause))
        #expect(!englishFailure.contains("supported divertible button controls"))
        #expect(MXMappingSetupMessages.unavailableFallback(existingFailure: englishFailure, language: .english) == englishFailure)
        #expect(MXMappingSetupMessages.preserveManualError(afterRefresh: englishFailure, refreshError: "later refresh error") == englishFailure)
    }

    @Test("explicit mapping action suppresses an automatic retry on that connection")
    func explicitActionBoundsAutomaticRetry() async throws {
        let (preferences, directory) = try optedInPreferences(enabled: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let policy = MXMappingRestorePolicy(preferences: preferences)
        let connection = context()
        policy.noteExplicitUserAction(deviceID: deviceID, connectionToken: connection.connectionToken)
        var adapterCalls = 0

        let result = await policy.restoreIfAllowed(context: connection) { _ in adapterCalls += 1 }
        #expect(result == .alreadyAttempted)
        #expect(adapterCalls == 0)
    }

    private func optedInPreferences(enabled: Bool) throws -> (MXMappingPreferences, URL) {
        let (store, directory) = makeStore()
        let preferences = MXMappingPreferences(store: store)
        preferences.setRestoreEnabledAtLaunch(true)
        if enabled {
            try preferences.recordVerifiedEnable(deviceID: deviceID, choices: choices)
        } else {
            // The helper intentionally supports a valid disabled intent for the opt-in gate test.
            try preferences.recordVerifiedEnable(deviceID: deviceID, choices: choices)
            try preferences.clearEnabledIntent(deviceID: deviceID)
        }
        return (preferences, directory)
    }

    private func context(
        deviceID requestedDeviceID: String? = nil,
        connectionToken: UUID = UUID(),
        isMXMaster4: Bool = true,
        permissionReady: Bool = true,
        capabilitiesComplete: Bool = true,
        lifecycleAllowsOperations: Bool = true,
        deviceStateCertain: Bool = true,
        leaseCertain: Bool = true,
        foreignOwnershipDetected: Bool = false
    ) -> MXMappingRestoreContext {
        MXMappingRestoreContext(
            deviceID: requestedDeviceID ?? deviceID,
            connectionToken: connectionToken,
            isMXMaster4: isMXMaster4,
            permissionReady: permissionReady,
            capabilitiesComplete: capabilitiesComplete,
            lifecycleAllowsOperations: lifecycleAllowsOperations,
            deviceStateCertain: deviceStateCertain,
            leaseCertain: leaseCertain,
            foreignOwnershipDetected: foreignOwnershipDetected
        )
    }

    private func makeStore() -> (FileMXMappingPreferenceStore, URL) {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("mx-mapping-tests-\(UUID().uuidString)", isDirectory: true)
        return (FileMXMappingPreferenceStore(fileURL: storeURL(in: directory)), directory)
    }

    private func storeURL(in directory: URL) -> URL {
        directory.appendingPathComponent("mx-mappings-v1.json")
    }
}

@MainActor
private final class FailingMXMappingPreferenceStore: MXMappingPreferenceStoring {
    func load() throws -> MXMappingPreferenceDocument { MXMappingPreferenceDocument() }
    func save(_ document: MXMappingPreferenceDocument) throws { throw TestFailure.expected }
}

private enum TestFailure: Error, LocalizedError {
    case expected
    var errorDescription: String? { "injected preference write failure" }
}
