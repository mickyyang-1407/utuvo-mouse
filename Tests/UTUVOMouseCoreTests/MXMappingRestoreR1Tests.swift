import Foundation
import Testing
import UTUVOMouseSupport

@Suite("MOUSE-006B R1 restore lifecycle regressions")
@MainActor
struct MXMappingRestoreR1Tests {
    private let deviceID = "sha256:0123456789abcdef"

    @Test("explicit user action skips the active-lease blocker")
    func explicitActionSkipsLeaseBlocker() async throws {
        let policy = try makePolicy()
        let token = UUID()
        policy.noteExplicitUserAction(deviceID: deviceID, connectionToken: token)
        var applyCalls = 0

        let result = await policy.restoreIfAllowed(context: context(token: token, leaseCertain: false)) { _ in
            applyCalls += 1
        }

        #expect(result == .alreadyAttempted)
        #expect(applyCalls == 0)
    }

    @Test("a successful restore skips the later active-lease blocker")
    func restoredConnectionSkipsLeaseBlocker() async throws {
        let policy = try makePolicy()
        let token = UUID()
        var applyCalls = 0

        let first = await policy.restoreIfAllowed(context: context(token: token)) { _ in applyCalls += 1 }
        let second = await policy.restoreIfAllowed(context: context(token: token, leaseCertain: false)) { _ in
            applyCalls += 1
        }

        #expect(first == .restored)
        #expect(second == .alreadyAttempted)
        #expect(applyCalls == 1)
    }

    @Test("a blocked token is bounded and requires explicit recovery")
    func blockedTokenDoesNotRetryOnRefresh() async throws {
        let policy = try makePolicy()
        let token = UUID()
        var applyCalls = 0

        let first = await policy.restoreIfAllowed(context: context(token: token, permissionReady: false)) { _ in
            applyCalls += 1
        }
        let second = await policy.restoreIfAllowed(context: context(token: token)) { _ in
            applyCalls += 1
        }

        if case .blocked = first {} else { Issue.record("Expected the first attempt to be blocked") }
        #expect(second == .alreadyAttempted)
        #expect(applyCalls == 0)
    }

    @Test("non-authoritative discovery waits without consuming the connection token")
    func incompleteDiscoveryWaits() async throws {
        let policy = try makePolicy()
        let token = UUID()
        var applyCalls = 0

        let waiting = await policy.restoreIfAllowed(
            context: context(token: token, prerequisitesAuthoritative: false)
        ) { _ in applyCalls += 1 }
        let complete = await policy.restoreIfAllowed(context: context(token: token)) { _ in applyCalls += 1 }

        #expect(waiting == .waitingForPrerequisites)
        #expect(complete == .restored)
        #expect(applyCalls == 1)
    }

    @Test("an owned active lease is recognized without another enable")
    func ownedLeaseIsAlreadyActive() async throws {
        let policy = try makePolicy()
        var applyCalls = 0

        let result = await policy.restoreIfAllowed(
            context: context(token: UUID(), leaseOwned: true)
        ) { _ in applyCalls += 1 }

        #expect(result == .alreadyActive)
        #expect(applyCalls == 0)
    }

    @Test("skipped restore results preserve unrelated operation messages")
    func skippedResultPreservesMessages() async throws {
        let policy = try makePolicy()
        let token = UUID()
        let blocked = await policy.restoreIfAllowed(
            context: context(token: token, permissionReady: false)
        ) { _ in }
        var messages = MXMappingRestoreMessages.update(for: blocked)!
        #expect(messages.errorMessage != nil)

        messages = MXMappingRestoreMessages(statusMessage: "DPI 已更新", errorMessage: nil)
        let repeated = await policy.restoreIfAllowed(context: context(token: token)) { _ in }
        if let update = MXMappingRestoreMessages.update(for: repeated) { messages = update }

        #expect(repeated == .alreadyAttempted)
        #expect(messages.statusMessage == "DPI 已更新")
        #expect(messages.errorMessage == nil)

        let skipped: [MXMappingRestoreResult] = [.notRequested, .waitingForPrerequisites, .alreadyAttempted, .alreadyActive]

        for result in skipped {
            if let update = MXMappingRestoreMessages.update(for: result) {
                messages = update
            } else {
                #expect(MXMappingRestoreMessages.update(for: result) == nil)
            }
        }
        #expect(messages.statusMessage == "DPI 已更新")
        #expect(messages.errorMessage == nil)
    }

    private func makePolicy() throws -> MXMappingRestorePolicy {
        let preferences = MXMappingPreferences(store: MemoryMXMappingPreferenceStore())
        preferences.setRestoreEnabledAtLaunch(true)
        try preferences.recordVerifiedEnable(deviceID: deviceID, choices: [0x0052: .copy])
        return MXMappingRestorePolicy(preferences: preferences)
    }

    private func context(
        token: UUID,
        permissionReady: Bool = true,
        leaseCertain: Bool = true,
        prerequisitesAuthoritative: Bool = true,
        leaseOwned: Bool = false
    ) -> MXMappingRestoreContext {
        MXMappingRestoreContext(
            deviceID: deviceID,
            connectionToken: token,
            isMXMaster4: true,
            permissionReady: permissionReady,
            capabilitiesComplete: true,
            prerequisitesAuthoritative: prerequisitesAuthoritative,
            lifecycleAllowsOperations: true,
            deviceStateCertain: true,
            leaseCertain: leaseCertain,
            leaseOwnedByCurrentSession: leaseOwned
        )
    }
}
