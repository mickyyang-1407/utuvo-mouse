import Foundation

/// What the running process is allowed to do.
///
/// The demo mode runs on synthetic data only: it never registers a login item,
/// never creates an updater and never reaches the network.
public struct RuntimePolicy: Equatable, Sendable {

    /// The demo mode.
    public var isDemo: Bool

    public init(isDemo: Bool) {
        self.isDemo = isDemo
    }

    /// The normal app.
    public static let live = RuntimePolicy(isDemo: false)

    /// The demo.
    public static let demo = RuntimePolicy(isDemo: true)

    /// A login item may only be registered from a user action in the real app.
    public var allowsLoginItemRegistration: Bool { !isDemo }

    /// The updater is not created at all in the demo mode.
    public var allowsUpdater: Bool { !isDemo }
}
