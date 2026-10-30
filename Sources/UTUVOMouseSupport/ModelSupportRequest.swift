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

    /// The same model-level request, derived from a strictly validated
    /// capability report. It carries no device identity beyond the model key.
    public init?(capabilityReport: CapabilityReport) {
        schemaVersion = 1
        vendorID = capabilityReport.vendorID
        productID = capabilityReport.productID
        transport = capabilityReport.transport
        modelKey = capabilityReport.modelKey
        catalogName = productID == 0xB025 && transport == "bluetooth" ? "MX Anywhere 3" : nil
        observation = capabilityReport.featureIDs.isEmpty ? "metadataOnly" : "featureIDsOnly"
        featureIDs = capabilityReport.featureIDs
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
    /// The capability input revision this progress belongs to, when the job
    /// carried one. Old jobs and old statuses simply have none.
    public let capabilitiesFingerprint: String?

    public init(modelKey: String, phase: ModelSupportPhase, programTestsPassed: Bool = false,
                capabilitiesFingerprint: String? = nil) {
        schemaVersion = 1
        self.modelKey = modelKey
        self.phase = phase
        self.programTestsPassed = programTestsPassed && phase == .needsHardware
        hardwareVerified = false
        released = false
        self.capabilitiesFingerprint = capabilitiesFingerprint
    }

    public var isValidCandidateProgress: Bool {
        schemaVersion == 1 && !hardwareVerified && !released &&
            (programTestsPassed == (phase == .needsHardware)) &&
            (capabilitiesFingerprint == nil || CapabilityFingerprint.isValid(capabilitiesFingerprint!))
    }
}

/// A file mailbox shared with the separately configured developer companion.
/// No networking, process launches, hardware traffic or polling happens here.
public struct ModelSupportQueue: Sendable {
    public let directory: URL

    public init(directory: URL) { self.directory = directory }

    public static func applicationSupportDirectory(create: Bool = false) throws -> URL {
        try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask,
                                    appropriateFor: nil, create: create)
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
        let progress = try JSONDecoder().decode(ModelSupportProgress.self,
                                                from: try Self.readBoundedFile(status, limit: 4096))
        guard progress.modelKey == request.modelKey, progress.isValidCandidateProgress else {
            throw CocoaError(.fileReadCorruptFile)
        }
        return progress
    }

    /// The capability file inside one model job.
    public static let capabilitiesFileName = "capabilities.json"

    /// Creates the model job when it is absent.
    ///
    /// An existing job is never rewritten: the first observation wins, exactly
    /// like `enqueue`. This only fills a missing job so an imported capability
    /// record has somewhere to live.
    @discardableResult
    public func ensureJob(_ request: ModelSupportRequest) throws -> Bool {
        guard request.isValid else { throw CocoaError(.fileReadCorruptFile) }
        let fm = FileManager.default
        try fm.createDirectory(at: directory, withIntermediateDirectories: true,
                               attributes: [.posixPermissions: 0o700])
        try rejectSymlink(directory)
        let job = directory.appendingPathComponent(request.modelKey, isDirectory: true)
        try rejectSymlink(job)
        let report = job.appendingPathComponent("report.json")
        try rejectSymlink(report)
        if fm.fileExists(atPath: report.path) { return false }
        if !fm.fileExists(atPath: job.path) {
            try fm.createDirectory(at: job, withIntermediateDirectories: false,
                                   attributes: [.posixPermissions: 0o700])
            try rejectSymlink(job)
        }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(request).write(to: report, options: .atomic)
        try Data(request.taskMarkdown.utf8).write(to: job.appendingPathComponent("TASK.md"), options: .atomic)
        return true
    }

    /// Atomically stores the capability record of one model job.
    ///
    /// It never touches report.json, status.json, result.json or any other
    /// file of the job. Returns true when the stored input revision changed.
    @discardableResult
    public func saveCapabilities(_ record: CapabilityRecord, for modelKey: String) throws -> Bool {
        guard Self.isValidModelKey(modelKey), record.report.modelKey == modelKey else {
            throw CocoaError(.fileReadCorruptFile)
        }
        // A record is stored only after its report passes the same strict rules
        // as an imported file. A publicly constructed record can never smuggle
        // in a writable, foreign or incomplete report.
        try CapabilityRecordCodec.validateReportValues(record.report)
        let fm = FileManager.default
        try fm.createDirectory(at: directory, withIntermediateDirectories: true,
                               attributes: [.posixPermissions: 0o700])
        try rejectSymlink(directory)
        let job = directory.appendingPathComponent(modelKey, isDirectory: true)
        try rejectSymlink(job)
        if !fm.fileExists(atPath: job.path) {
            try fm.createDirectory(at: job, withIntermediateDirectories: false,
                                   attributes: [.posixPermissions: 0o700])
            try rejectSymlink(job)
        }
        let file = job.appendingPathComponent(Self.capabilitiesFileName)
        try rejectSymlink(file)
        // A corrupt old file must not block a new valid record; the atomic
        // replacement below repairs it.
        let previous: CapabilityRecord? = try? capabilities(for: modelKey)
        let data = try CapabilityRecordCodec.encode(record)
        // A single atomic replacement: a reader never sees half a record.
        try data.write(to: file, options: .atomic)
        return previous?.fingerprint != record.fingerprint
    }

    /// Strictly loads the stored capability record of one model job.
    ///
    /// A missing file is not an error: metadata-only jobs stay valid. A
    /// corrupt, oversized or symlinked file is an error, never a record.
    public func capabilities(for modelKey: String) throws -> CapabilityRecord? {
        guard Self.isValidModelKey(modelKey) else { throw CocoaError(.fileReadCorruptFile) }
        let job = directory.appendingPathComponent(modelKey, isDirectory: true)
        try rejectSymlink(directory)
        try rejectSymlink(job)
        let file = job.appendingPathComponent(Self.capabilitiesFileName)
        try rejectSymlink(file)
        guard FileManager.default.fileExists(atPath: file.path) else { return nil }
        // A stored capability input must be one regular file of this job.
        let attributes = try FileManager.default.attributesOfItem(atPath: file.path)
        guard attributes[.type] as? FileAttributeType == .typeRegular else {
            throw CocoaError(.fileReadCorruptFile)
        }
        let record = try CapabilityRecordCodec.decodeRecord(
            from: try Self.readBoundedFile(file, limit: CapabilityRecordCodec.maximumRecordByteCount)
        )
        // The stored record must belong to this very job. Another model's
        // record is never this job's input.
        guard record.report.modelKey == modelKey else { throw CocoaError(.fileReadCorruptFile) }
        return record
    }

    /// Reads at most `limit` bytes from one regular file.
    ///
    /// The read stops one byte past the limit, so a file that grows after the
    /// check is refused instead of being read whole.
    static func readBoundedFile(_ url: URL, limit: Int) throws -> Data {
        guard let handle = try? FileHandle(forReadingFrom: url) else {
            throw CocoaError(.fileReadCorruptFile)
        }
        defer { try? handle.close() }
        var data = Data()
        do {
            while data.count <= limit {
                guard let chunk = try handle.read(upToCount: limit + 1 - data.count),
                      !chunk.isEmpty else { break }
                data.append(chunk)
            }
        } catch {
            throw CocoaError(.fileReadCorruptFile)
        }
        guard data.count <= limit else { throw CocoaError(.fileReadCorruptFile) }
        return data
    }

    /// A model key is a path element, so only this shape is accepted.
    static func isValidModelKey(_ modelKey: String) -> Bool {
        let allowed = ["bluetooth", "usb", "receiver", "unknown"]
        let parts = modelKey.split(separator: "-", omittingEmptySubsequences: false).map(String.init)
        guard parts.count == 3 else { return false }
        guard parts[0].count == 4, parts[1].count == 4 else { return false }
        guard parts[0].allSatisfy({ $0.isHexDigit && !$0.isUppercase }),
              parts[1].allSatisfy({ $0.isHexDigit && !$0.isUppercase }) else { return false }
        return allowed.contains(parts[2])
    }

    private func rejectSymlink(_ url: URL) throws {
        if (try? FileManager.default.destinationOfSymbolicLink(atPath: url.path)) != nil {
            throw CocoaError(.fileReadNoPermission)
        }
    }
}
