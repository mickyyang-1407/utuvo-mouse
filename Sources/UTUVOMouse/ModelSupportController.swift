import AppKit
import Observation
import UTUVOMouseCore
import UTUVOMouseIO
import UTUVOMouseSupport

/// A local mailbox for a developer's AI. The normal mouse app never launches a
/// coding tool, downloads drivers, or gives an agent access to a live mouse.
@MainActor
@Observable
final class ModelSupportController {
    private(set) var enabled: Bool
    private(set) var phases: [String: ModelSupportPhase] = [:]
    private(set) var progresses: [String: ModelSupportProgress] = [:]
    /// The capability record on file for each model job, with its provenance.
    private(set) var capabilityRecords: [String: CapabilityRecord] = [:]
    /// The fixed code of the last failed collection for each model.
    private(set) var capabilityFailures: [String: String] = [:]
    /// The fixed code of an invalid stored capability input, per model.
    ///
    /// A corrupt capability file is tracked per model, so the program state
    /// can say that the input is invalid instead of claiming a coverage.
    private(set) var capabilityInputFailures: [String: String] = [:]
    private(set) var isCollecting = false
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
        var progressResult: [String: ModelSupportProgress] = [:]
        var records: [String: CapabilityRecord] = [:]
        var inputFailures: [String: String] = [:]
        for (key, request) in knownRequests {
            do {
                let progress = try queue.progress(for: request)
                result[key] = progress.phase
                progressResult[key] = progress
            } catch { storageFailed = true }
            do {
                // A missing capability file is not an error; a corrupt one is.
                if let record = try queue.capabilities(for: key) { records[key] = record }
            } catch {
                storageFailed = true
                // The invalid input belongs to this model alone: the program
                // state must say so instead of dropping the record silently.
                inputFailures[key] = Self.inputFailureCode(error)
            }
        }
        phases = result
        progresses = progressResult
        capabilityRecords = records
        capabilityInputFailures = inputFailures
    }

    func phase(for snapshot: DeviceSnapshot) -> ModelSupportPhase? {
        guard let request = ModelSupportRequest(snapshot: snapshot) else { return nil }
        return phases[request.modelKey]
    }

    /// The full progress, including the capability input revision it belongs to.
    func progress(for snapshot: DeviceSnapshot) -> ModelSupportProgress? {
        guard let request = ModelSupportRequest(snapshot: snapshot) else { return nil }
        return progresses[request.modelKey]
    }

    /// The capability record on file, with its provenance.
    func capabilityRecord(for snapshot: DeviceSnapshot) -> CapabilityRecord? {
        guard let request = ModelSupportRequest(snapshot: snapshot) else { return nil }
        return capabilityRecords[request.modelKey]
    }

    /// The fixed code of the last failed collection, if any.
    func capabilityFailure(for snapshot: DeviceSnapshot) -> String? {
        guard let request = ModelSupportRequest(snapshot: snapshot) else { return nil }
        return capabilityFailures[request.modelKey]
    }

    /// The fixed code of an invalid stored capability input, if any.
    func capabilityInputFailure(for snapshot: DeviceSnapshot) -> String? {
        guard let request = ModelSupportRequest(snapshot: snapshot) else { return nil }
        return capabilityInputFailures[request.modelKey]
    }

    /// How the program-test result relates to the capability input on file.
    func coverage(for snapshot: DeviceSnapshot) -> CapabilityProgressCoverage {
        ModelSupportCoverage.coverage(record: capabilityRecord(for: snapshot),
                                      progress: progress(for: snapshot),
                                      invalidInput: capabilityInputFailure(for: snapshot) != nil)
    }

    /// The short program state of this model job.
    func programState(for snapshot: DeviceSnapshot) -> ModelSupportProgramState {
        ModelSupportProgram.state(phase: phase(for: snapshot),
                                  record: capabilityRecord(for: snapshot),
                                  progress: progress(for: snapshot),
                                  invalidInput: capabilityInputFailure(for: snapshot) != nil)
    }

    /// Only the exact Bluetooth model has a collection route.
    func isCapabilityModel(for snapshot: DeviceSnapshot) -> Bool {
        let identity = snapshot.identity
        return identity.vendorID == MXAnywhere3CapabilityInspection.vendorID
            && identity.productID == MXAnywhere3CapabilityInspection.productID
            && identity.transport == .bluetooth
    }

    /// Whether the collection button may run right now.
    func canCollectCapabilities(for snapshot: DeviceSnapshot) -> Bool {
        guard !isDemo, enabled, queue != nil, !isCollecting else { return false }
        return isCapabilityModel(for: snapshot)
    }

    /// The one explicit collection path.
    ///
    /// Only this user action reaches the device. Observation, start, refresh
    /// and the tests never call the inspection service.
    func collectCapabilities() async {
        guard !isDemo, enabled, let queue, !isCollecting else { return }
        isCollecting = true
        defer { isCollecting = false }
        let modelKey = MXAnywhere3CapabilityInspection.modelKey
        do {
            let report = try await MXAnywhere3InspectionService.inspect(consent: true)
            let record = try CapabilityRecordCodec.makeRecord(inspection: report, origin: .appReadOnly)
            try queue.saveCapabilities(record, for: modelKey)
            capabilityRecords[modelKey] = record
            capabilityFailures.removeValue(forKey: modelKey)
            refreshProgress()
        } catch {
            // A failed collection never writes a successful record.
            capabilityFailures[modelKey] = Self.failureCode(error)
        }
    }

    /// Fixed codes only. No device text, path or value is carried over.
    private static func failureCode(_ error: any Error) -> String {
        switch error {
        case let error as CapabilityInspectionError: return error.rawValue
        case let error as CapabilityRecordError: return error.rawValue
        default: return "unexpected"
        }
    }

    /// A fixed code for an invalid stored capability input.
    ///
    /// It never carries the path, the file name, the stored record or any
    /// other value.
    private static func inputFailureCode(_ error: any Error) -> String {
        switch error {
        case let error as CapabilityRecordError: return error.rawValue
        case let error as CocoaError:
            return error.code == .fileReadCorruptFile ? "corrupt" : "unexpected"
        default: return "unexpected"
        }
    }

    func openTasks() {
        guard !isDemo, let queue,
              FileManager.default.fileExists(atPath: queue.directory.path) else { return }
        NSWorkspace.shared.open(queue.directory)
    }
}
