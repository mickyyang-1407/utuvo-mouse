import AppKit
import Observation
import UTUVOMouseCore
import UTUVOMouseSupport

/// A local mailbox for a developer's AI. The normal mouse app never launches a
/// coding tool, downloads drivers, or gives an agent access to a live mouse.
@MainActor
@Observable
final class ModelSupportController {
    private(set) var enabled: Bool
    private(set) var phases: [String: ModelSupportPhase] = [:]
    private(set) var storageFailed = false
    @ObservationIgnored private let queue: ModelSupportQueue?
    @ObservationIgnored private let isDemo: Bool
    @ObservationIgnored private var knownRequests: [String: ModelSupportRequest] = [:]
    private static let preferenceKey = "utuvo.mouse.modelSupport.localQueue"

    init(isDemo: Bool) {
        self.isDemo = isDemo
        if isDemo {
            enabled = false
            queue = nil
        } else {
            enabled = UserDefaults.standard.object(forKey: Self.preferenceKey) as? Bool ?? true
            queue = (try? ModelSupportQueue.applicationSupportDirectory()).map(ModelSupportQueue.init)
        }
    }

    func setEnabled(_ requested: Bool, snapshots: [DeviceSnapshot]) {
        guard !isDemo else { return }
        enabled = requested
        UserDefaults.standard.set(requested, forKey: Self.preferenceKey)
        observe(snapshots)
    }

    func observe(_ snapshots: [DeviceSnapshot]) {
        guard !isDemo, enabled else { return }
        guard let queue else { storageFailed = true; return }
        var enqueueFailed = false
        for snapshot in snapshots {
            guard let request = ModelSupportRequest(snapshot: snapshot) else { continue }
            knownRequests[request.modelKey] = request
            do {
                // Existing requests are not rewritten by refresh or hot-plug.
                try queue.enqueue(request)
            } catch { enqueueFailed = true }
        }
        refreshProgress()
        storageFailed = storageFailed || enqueueFailed
    }

    func refreshProgress() {
        guard !isDemo, let queue else { return }
        storageFailed = false
        var result: [String: ModelSupportPhase] = [:]
        for (key, request) in knownRequests {
            do { result[key] = try queue.progress(for: request).phase }
            catch { storageFailed = true }
        }
        phases = result
    }

    func phase(for snapshot: DeviceSnapshot) -> ModelSupportPhase? {
        guard let request = ModelSupportRequest(snapshot: snapshot) else { return nil }
        return phases[request.modelKey]
    }

    func openTasks() {
        guard !isDemo, let queue,
              FileManager.default.fileExists(atPath: queue.directory.path) else { return }
        NSWorkspace.shared.open(queue.directory)
    }
}
