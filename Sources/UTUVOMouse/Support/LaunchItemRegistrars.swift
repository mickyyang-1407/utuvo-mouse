import Foundation
import ServiceManagement
import UTUVOMouseSupport

/// The real login item, backed by the system service management.
///
/// It is only created in the normal app mode. The demo mode and the tests use
/// a fake, so no login item is ever registered by them.
struct SystemLaunchItemRegistrar: LaunchItemRegistering {

    func currentStatus() async -> LaunchItemStatus {
        switch SMAppService.mainApp.status {
        case .notRegistered: return .notRegistered
        case .enabled: return .enabled
        case .requiresApproval: return .requiresApproval
        case .notFound: return .notFound
        @unknown default: return .notFound
        }
    }

    func register() async throws {
        try SMAppService.mainApp.register()
    }

    func unregister() async throws {
        try await SMAppService.mainApp.unregister()
    }
}

/// A login item that does nothing.
///
/// The demo mode uses it: the interface can be shown and the state can be read,
/// but the system is never touched.
struct DemoLaunchItemRegistrar: LaunchItemRegistering {

    func currentStatus() async -> LaunchItemStatus {
        .notRegistered
    }

    func register() async throws {
        // The demo never registers a login item.
    }

    func unregister() async throws {
        // The demo never registers a login item.
    }
}
