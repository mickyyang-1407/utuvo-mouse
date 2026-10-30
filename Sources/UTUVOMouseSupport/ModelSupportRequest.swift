import Foundation
import UTUVOMouseCore

/// A model-level research request, not a diagnostic dump. In particular, HID
/// names can contain personal text, so even the reported product name is omitted.
public struct ModelSupportRequest: Codable, Equatable, Sendable {
    public let schemaVersion: Int
    public let modelKey: String
    public let vendorID: Int
    public let productID: Int
    public let transport: String
    public let catalogName: String?
    public let observation: String
    public let featureIDs: [String]

    public init?(snapshot: DeviceSnapshot) {
        let identity = snapshot.identity
        guard !snapshot.isDemo, identity.model == .unknown,
              identity.vendorID == MouseIdentification.logitechVendorID,
              (0...65535).contains(identity.productID) else { return nil }
        schemaVersion = 1
        vendorID = identity.vendorID
        productID = identity.productID
        switch identity.transport {
        case .bluetooth: transport = "bluetooth"
        case .usb: transport = "usb"
        case .receiver: transport = "receiver"
        case .unknown: transport = "unknown"
        }
        modelKey = String(format: "%04x-%04x-", vendorID, productID) + transport
        // A research hint only. This never enables a device or a write path.
        catalogName = productID == 0xB025 && transport == "bluetooth" ? "MX Anywhere 3" : nil
        observation = snapshot.features.isEmpty ? "metadataOnly" : "featureIDsOnly"
        featureIDs = snapshot.features.keys.sorted().map { String(format: "%04X", $0) }
    }

    public var taskMarkdown: String {
        """
        # UTUVO Mouse model support request

        Model key: \(modelKey)
        Catalog hint: \(catalogName ?? "unidentified; establish the exact model first")
        Observation: \(observation)
        Observed feature IDs: \(featureIDs.joined(separator: ", "))

        report.json is a model-level observation, not proof of capabilities.
        A receiver PID identifies the receiver, not its paired mouse. Do not infer
        a model from shared features. Do not treat missing features as unsupported:
        metadataOnly means the app deliberately did not open this device.

        Research primary protocol sources and existing open-source implementations.
        Implement only in the supplied candidate source tree; add isolated mock tests.
        Keep unknown models read-only. Physical testing, independent review, signing
        and release are separate gates; program tests cannot satisfy those gates.
        Never access live HID devices, capture input, change TCC, vendor settings,
        firmware or login items. Never read signing keys or publish a release.
        Preserve English/Traditional Chinese, existing controls and updater settings.
        Record source links, assumptions, changed files and test results in
        SUPPORT-CANDIDATE.md. Do not claim hardware verification.
        """
    }

    /// Revalidate decoded data before it can become a path or an agent prompt.
    public var isValid: Bool {
        guard schemaVersion == 1, vendorID == MouseIdentification.logitechVendorID,
              (0...65535).contains(productID),
              ["bluetooth", "usb", "receiver", "unknown"].contains(transport),
              modelKey == String(format: "%04x-%04x-", vendorID, productID) + transport,
              catalogName == (productID == 0xB025 && transport == "bluetooth" ? "MX Anywhere 3" : nil),
              featureIDs.count <= 256,
              featureIDs == Array(Set(featureIDs)).sorted(),
              featureIDs.allSatisfy({ $0.range(of: "^[0-9A-F]{4}$", options: .regularExpression) != nil }) else { return false }
        return observation == (featureIDs.isEmpty ? "metadataOnly" : "featureIDsOnly")
    }
}

/// Worker progress is intentionally unable to express "hardware verified" or
/// "released". A successful coding agent can only produce a candidate.
public enum ModelSupportPhase: String, Codable, CaseIterable, Sendable {
    case queued, preparing, developing, testing, needsHardware, failed
}

public struct ModelSupportProgress: Codable, Equatable, Sendable {
    public let schemaVersion: Int
    public let modelKey: String
    public let phase: ModelSupportPhase
    public let programTestsPassed: Bool
    public let hardwareVerified: Bool
    public let released: Bool

    public init(modelKey: String, phase: ModelSupportPhase, programTestsPassed: Bool = false) {
        schemaVersion = 1
        self.modelKey = modelKey
        self.phase = phase
        self.programTestsPassed = programTestsPassed && phase == .needsHardware
        hardwareVerified = false
        released = false
    }

    public var isValidCandidateProgress: Bool {
        schemaVersion == 1 && !hardwareVerified && !released &&
            (programTestsPassed == (phase == .needsHardware))
    }
}

/// A file mailbox shared with the separately configured developer companion.
/// No networking, process launches, hardware traffic or polling happens here.
public struct ModelSupportQueue: Sendable {
    public let directory: URL

    public init(directory: URL) { self.directory = directory }

    public static func applicationSupportDirectory() throws -> URL {
        try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask,
                                    appropriateFor: nil, create: false)
            .appendingPathComponent("UTUVOMouse/ModelSupport", isDirectory: true)
    }

    /// First observation wins. Refresh/reconnect cannot erase worker progress or
    /// reopen a failed job. Retry is an explicit developer-companion operation.
    @discardableResult
    public func enqueue(_ request: ModelSupportRequest) throws -> Bool {
        guard request.isValid else { throw CocoaError(.fileReadCorruptFile) }
        let fm = FileManager.default
        try fm.createDirectory(at: directory, withIntermediateDirectories: true,
                               attributes: [.posixPermissions: 0o700])
        try rejectSymlink(directory)
        let job = directory.appendingPathComponent(request.modelKey, isDirectory: true)
        try rejectSymlink(job)
        if fm.fileExists(atPath: job.path) {
            try rejectSymlink(job)
            guard fm.fileExists(atPath: job.appendingPathComponent("report.json").path) else {
                throw CocoaError(.fileReadCorruptFile)
            }
            return false
        }
        let staging = directory.appendingPathComponent(".pending-" + UUID().uuidString, isDirectory: true)
        try fm.createDirectory(at: staging, withIntermediateDirectories: false,
                               attributes: [.posixPermissions: 0o700])
        defer { try? fm.removeItem(at: staging) }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(request).write(to: staging.appendingPathComponent("report.json"), options: .atomic)
        try Data(request.taskMarkdown.utf8).write(to: staging.appendingPathComponent("TASK.md"), options: .atomic)
        // Rename publishes a complete job; a watcher never sees half a report.
        do { try fm.moveItem(at: staging, to: job) }
        catch {
            if fm.fileExists(atPath: job.path) {
                try rejectSymlink(job)
                guard fm.fileExists(atPath: job.appendingPathComponent("report.json").path) else { throw error }
                return false
            }
            throw error
        }
        return true
    }

    public func progress(for request: ModelSupportRequest) throws -> ModelSupportProgress {
        guard request.isValid else { throw CocoaError(.fileReadCorruptFile) }
        let job = directory.appendingPathComponent(request.modelKey, isDirectory: true)
        try rejectSymlink(directory)
        try rejectSymlink(job)
        guard FileManager.default.fileExists(atPath: job.appendingPathComponent("report.json").path) else {
            throw CocoaError(.fileReadNoSuchFile)
        }
        let status = job.appendingPathComponent("status.json")
        try rejectSymlink(status)
        guard FileManager.default.fileExists(atPath: status.path) else {
            return ModelSupportProgress(modelKey: request.modelKey, phase: .queued)
        }
        let size = try status.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? Int.max
        guard size <= 4096 else { throw CocoaError(.fileReadCorruptFile) }
        let progress = try JSONDecoder().decode(ModelSupportProgress.self, from: Data(contentsOf: status))
        guard progress.modelKey == request.modelKey, progress.isValidCandidateProgress else {
            throw CocoaError(.fileReadCorruptFile)
        }
        return progress
    }

    private func rejectSymlink(_ url: URL) throws {
        if (try? FileManager.default.destinationOfSymbolicLink(atPath: url.path)) != nil {
            throw CocoaError(.fileReadNoPermission)
        }
    }
}
