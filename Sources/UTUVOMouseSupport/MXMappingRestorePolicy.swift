import Foundation
import UTUVOMouseLocalization
import UTUVOMouseCore

/// Facts that must be true before saved intent may reach the remapper.
public struct MXMappingRestoreContext: Sendable {
    public var deviceID: String
    public var connectionToken: UUID
    public var isMXMaster4: Bool
    public var permissionReady: Bool
    public var capabilitiesComplete: Bool
    /// False only while live snapshot/connection prerequisites are still being discovered.
    public var prerequisitesAuthoritative: Bool
    /// True when the production remapper adapter could be prepared for this connection.
    public var adapterReady: Bool
    public var lifecycleAllowsOperations: Bool
    public var deviceStateCertain: Bool
    /// True when a lease is owned and active in this process, not an old uncertain lease.
    public var leaseCertain: Bool
    public var leaseOwnedByCurrentSession: Bool
    public var foreignOwnershipDetected: Bool

    public init(
        deviceID: String,
        connectionToken: UUID,
        isMXMaster4: Bool,
        permissionReady: Bool,
        capabilitiesComplete: Bool,
        prerequisitesAuthoritative: Bool = true,
        adapterReady: Bool = true,
        lifecycleAllowsOperations: Bool,
        deviceStateCertain: Bool,
        leaseCertain: Bool,
        leaseOwnedByCurrentSession: Bool = false,
        foreignOwnershipDetected: Bool = false
    ) {
        self.deviceID = deviceID
        self.connectionToken = connectionToken
        self.isMXMaster4 = isMXMaster4
        self.permissionReady = permissionReady
        self.capabilitiesComplete = capabilitiesComplete
        self.prerequisitesAuthoritative = prerequisitesAuthoritative
        self.adapterReady = adapterReady
        self.lifecycleAllowsOperations = lifecycleAllowsOperations
        self.deviceStateCertain = deviceStateCertain
        self.leaseCertain = leaseCertain
        self.leaseOwnedByCurrentSession = leaseOwnedByCurrentSession
        self.foreignOwnershipDetected = foreignOwnershipDetected
    }
}

public enum MXMappingRestoreBlockReason: Equatable, Sendable {
    case storageUnavailable(String)
    case deviceMismatch
    case unsupportedDevice
    case permissionRequired
    case incompleteCapabilities
    case lifecycleClosed
    case deviceStateUncertain
    case adapterUnavailable
    case leaseUncertain
    case foreignOwnership
    case savedChoicesInvalid
}

public enum MXMappingRestoreResult: Equatable, Sendable {
    case notRequested
    case waitingForPrerequisites
    case blocked(MXMappingRestoreBlockReason)
    case alreadyAttempted
    case alreadyActive
    case restored
    case failed(MXMappingRestoreFailure)
}

public enum MXMappingRestoreFailure: Equatable, Sendable {
    case diversion(DiversionError)
    case external(String)

    public func message(language: MouseLanguage) -> String {
        switch self {
        case .diversion(let error): error.message(language: language)
        case .external(let message): message
        }
    }
}

public enum MXMappingSetupMessages {
    public static func storageFailure(_ detail: String, language: MouseLanguage) -> String {
        MouseLocalizer(language: language).string("app.remapper.storageFailed", arguments: [detail])
    }

    public static func unavailableFallback(existingFailure: String?, language: MouseLanguage) -> String {
        existingFailure ?? MouseLocalizer(language: language).string("app.mapping.unsupported")
    }

    public static func preserveManualError(afterRefresh manualError: String?, refreshError: String?) -> String? {
        manualError ?? refreshError
    }
}

/// The launch/connection restore gate used by the app and exercised with an
/// injected apply closure in tests. It never treats preferences as hardware state.
@MainActor
public final class MXMappingRestorePolicy {
    private struct Attempt: Hashable {
        var deviceID: String
        var connectionToken: UUID
    }

    private let preferences: MXMappingPreferences
    private var attempted = Set<Attempt>()

    public init(preferences: MXMappingPreferences) {
        self.preferences = preferences
    }

    /// A deliberate Enable/Disable on this connection supersedes launch restore.
    public func noteExplicitUserAction(deviceID: String, connectionToken: UUID) {
        attempted.insert(Attempt(deviceID: deviceID, connectionToken: connectionToken))
    }

    /// Lets AppModel skip repeated preflight and message work for this connection.
    public func hasHandledConnection(deviceID: String, connectionToken: UUID) -> Bool {
        attempted.contains(Attempt(deviceID: deviceID, connectionToken: connectionToken))
    }

    public func restoreIfAllowed(
        context: MXMappingRestoreContext,
        apply: @escaping @MainActor ([UInt16: MXMappingAction]) async throws -> Void
    ) async -> MXMappingRestoreResult {
        let attempt = Attempt(deviceID: context.deviceID, connectionToken: context.connectionToken)
        guard !attempted.contains(attempt) else { return .alreadyAttempted }
        guard preferences.storageReady else {
            return block(.storageUnavailable(preferences.lastError ?? ""), attempt: attempt)
        }
        guard preferences.restoreEnabledAtLaunch else { return .notRequested }
        guard let saved = preferences.savedMapping(for: context.deviceID), saved.enabledIntent else {
            return .notRequested
        }
        guard MXMappingPreferenceDocument.isStableDeviceID(context.deviceID), saved.deviceID == context.deviceID else {
            return block(.deviceMismatch, attempt: attempt)
        }
        // A partial, non-authoritative snapshot is still being discovered. It
        // does not consume a token; a later complete read may become eligible.
        guard context.prerequisitesAuthoritative else { return .waitingForPrerequisites }
        guard context.isMXMaster4 else { return block(.unsupportedDevice, attempt: attempt) }
        guard context.permissionReady else {
            return block(.permissionRequired, attempt: attempt)
        }
        guard context.capabilitiesComplete else {
            return block(.incompleteCapabilities, attempt: attempt)
        }
        guard context.lifecycleAllowsOperations else {
            return block(.lifecycleClosed, attempt: attempt)
        }
        guard context.deviceStateCertain else { return block(.deviceStateUncertain, attempt: attempt) }
        guard context.adapterReady else {
            return block(.adapterUnavailable, attempt: attempt)
        }
        guard context.leaseCertain else {
            return block(.leaseUncertain, attempt: attempt)
        }
        if context.leaseOwnedByCurrentSession {
            attempted.insert(attempt)
            return .alreadyActive
        }
        guard !context.foreignOwnershipDetected else {
            return block(.foreignOwnership, attempt: attempt)
        }
        guard saved.choices.keys.allSatisfy(MXMappingPreferenceDocument.allowedCIDs.contains),
              saved.choices.values.contains(where: { $0 != .native }) else {
            return block(.savedChoicesInvalid, attempt: attempt)
        }

        attempted.insert(attempt)
        do {
            try await apply(saved.choices)
            return .restored
        } catch let error as DiversionError {
            return .failed(.diversion(error))
        } catch {
            return .failed(.external(error.localizedDescription))
        }
    }

    private func block(_ reason: MXMappingRestoreBlockReason, attempt: Attempt) -> MXMappingRestoreResult {
        attempted.insert(attempt)
        return .blocked(reason)
    }
}

/// Message projection shared by AppModel and tests. `nil` means preserve the
/// current operation status or error (for example, when a refresh is skipped).
public struct MXMappingRestoreMessages: Equatable, Sendable {
    public var statusMessage: String?
    public var errorMessage: String?

    public init(statusMessage: String?, errorMessage: String?) {
        self.statusMessage = statusMessage
        self.errorMessage = errorMessage
    }

    public static func update(
        for result: MXMappingRestoreResult,
        language: MouseLanguage = .traditionalChinese
    ) -> MXMappingRestoreMessages? {
        let text = MouseLocalizer(language: language)
        return switch result {
        case .notRequested, .waitingForPrerequisites, .alreadyAttempted, .alreadyActive:
            nil
        case .blocked(let reason):
            MXMappingRestoreMessages(statusMessage: nil, errorMessage: blockedMessage(reason, text: text))
        case .restored:
            MXMappingRestoreMessages(statusMessage: text.string("mapping.restore.restored"), errorMessage: nil)
        case .failed(let failure):
            MXMappingRestoreMessages(statusMessage: nil, errorMessage: text.string("mapping.restore.failed", arguments: [failure.message(language: language)]))
        }
    }

    private static func blockedMessage(_ reason: MXMappingRestoreBlockReason, text: MouseLocalizer) -> String {
        switch reason {
        case .storageUnavailable(let message): text.string("mapping.restore.storageUnavailable", arguments: [message])
        case .deviceMismatch: text.string("mapping.restore.deviceMismatch")
        case .unsupportedDevice: text.string("mapping.restore.unsupportedDevice")
        case .permissionRequired: text.string("mapping.restore.permissionRequired")
        case .incompleteCapabilities: text.string("mapping.restore.incompleteCapabilities")
        case .lifecycleClosed: text.string("mapping.restore.lifecycleClosed")
        case .deviceStateUncertain: text.string("mapping.restore.deviceStateUncertain")
        case .adapterUnavailable: text.string("mapping.restore.adapterUnavailable")
        case .leaseUncertain: text.string("mapping.restore.leaseUncertain")
        case .foreignOwnership: text.string("mapping.restore.foreignOwnership")
        case .savedChoicesInvalid: text.string("mapping.restore.savedChoicesInvalid")
        }
    }
}
