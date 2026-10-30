import Foundation
import Observation

/// The state of the login item as the system reports it.
public enum LaunchItemStatus: Equatable, Sendable {
    case notRegistered
    case enabled
    case requiresApproval
    case notFound
}

/// The seam in front of the system login item service.
///
/// The live implementation lives in the app target. The demo mode and the
/// tests use a fake, so no login item is ever registered outside of an
/// explicit user action in the real app.
public protocol LaunchItemRegistering: Sendable {
    /// The status the system reports right now.
    func currentStatus() async -> LaunchItemStatus
    /// Registers the login item. Throws when the system refuses.
    func register() async throws
    /// Removes the login item. Throws when the system refuses.
    func unregister() async throws
}

/// Reads and changes the login item state, and never pretends.
///
/// The toggle follows the status the system reports, not the request that was
/// sent: a request the system refuses leaves the state where it was, and the
/// interface says why.
@MainActor
@Observable
public final class LaunchItemController {

    /// The status the system reports. `nil` means the state is not known yet.
    public private(set) var status: LaunchItemStatus?

    /// A request is running.
    public private(set) var isWorking = false

    /// The last error the system reported.
    public private(set) var lastError: String?

    @ObservationIgnored private let registrar: LaunchItemRegistering
    @ObservationIgnored private let policy: RuntimePolicy

    public init(registrar: LaunchItemRegistering, policy: RuntimePolicy = .live) {
        self.registrar = registrar
        self.policy = policy
    }

    /// True only when the system says the login item is enabled.
    public var isEnabled: Bool { status == .enabled }

    /// True when the user still has to approve the login item.
    public var needsApproval: Bool { status == .requiresApproval }

    /// True when the state is still unknown.
    public var isUnknown: Bool { status == nil }

    /// Reads the real status.
    public func refreshStatus() async {
        status = await registrar.currentStatus()
    }

    /// Turns the login item on or off from an explicit user action.
    ///
    /// The status is read again afterwards, so the interface shows what the
    /// system really did instead of what was asked for.
    public func setEnabled(_ enabled: Bool) async {
        guard !isWorking else { return }
        // The demo mode never touches the system, even when something asks it to.
        guard policy.allowsLoginItemRegistration else { return }
        isWorking = true
        defer { isWorking = false }
        do {
            if enabled {
                try await registrar.register()
            } else {
                try await registrar.unregister()
            }
            lastError = nil
        } catch {
            lastError = error.localizedDescription
        }
        await refreshStatus()
    }
}
