import Foundation
import UTUVOMouseCore
import UTUVOMouseSupport

/// The explicit file import route.
///
/// It runs before the app, the scanner, the inspection command and the broader
/// --probe path. It reads exactly one bounded regular file, validates it with
/// the same strict Support-layer rules as the app, and stores it in the local
/// model-support queue with imported provenance.
///
/// An imported record is never device-confirmed, never physically verified and
/// never a release.
enum CapabilityImportCommand {
    static let help = """
    Import a capability report / 匯入能力報告
      --import-capabilities FILE [--support-directory DIRECTORY]
      --import-capabilities --help

    FILE is a capability report exported by --inspect-capabilities.
    It is validated locally and stored with imported provenance: never
    device-confirmed, never a physical verification, never a release.
    DIRECTORY is an isolated local developer queue. The default is the app's
    own local queue.

    FILE 必須是唯讀檢查輸出的能力報告；匯入後僅標記為匯入來源，
    不視為裝置確認、實機驗證或發行。
    """

    static func run(file: String, supportDirectory: String?) -> Int32 {
        do {
            let data = try readBoundedFile(at: file)
            let report = try CapabilityRecordCodec.decodeReport(from: data)
            let record = try CapabilityRecordCodec.makeRecord(report: report, origin: .imported)
            let queue = try resolveQueue(supportDirectory)
            if let request = ModelSupportRequest(capabilityReport: report) {
                // The job is created only when it is missing. An existing
                // report.json, status.json or result.json is never rewritten.
                try queue.ensureJob(request)
            }
            try queue.saveCapabilities(record, for: record.report.modelKey)
            print(summary(for: record))
            return 0
        } catch {
            reportFailure(error)
            return 1
        }
    }

    /// Reads one bounded regular file. A symlink, a directory, a device or an
    /// oversized file is refused before anything is opened.
    static func readBoundedFile(at path: String) throws -> Data {
        let url = URL(fileURLWithPath: path)
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: url.path) else {
            throw CapabilityImportError.unsafeFile
        }
        guard attributes[.type] as? FileAttributeType == .typeRegular else {
            throw CapabilityImportError.unsafeFile
        }
        if (try? FileManager.default.destinationOfSymbolicLink(atPath: url.path)) != nil {
            throw CapabilityImportError.unsafeFile
        }
        let size = (attributes[.size] as? NSNumber)?.intValue ?? -1
        guard size >= 0, size <= CapabilityRecordCodec.maximumReportByteCount else {
            throw CapabilityImportError.tooLarge
        }
        // Bounded read: at most the limit plus one byte, so a file that grows
        // after the check is refused instead of being read whole.
        guard let handle = try? FileHandle(forReadingFrom: url) else {
            throw CapabilityImportError.unsafeFile
        }
        defer { try? handle.close() }
        var data = Data()
        do {
            while data.count <= CapabilityRecordCodec.maximumReportByteCount {
                let count = CapabilityRecordCodec.maximumReportByteCount + 1 - data.count
                guard let chunk = try handle.read(upToCount: count), !chunk.isEmpty else { break }
                data.append(chunk)
            }
        } catch {
            throw CapabilityImportError.unsafeFile
        }
        guard data.count <= CapabilityRecordCodec.maximumReportByteCount else {
            throw CapabilityImportError.tooLarge
        }
        return data
    }

    /// The directory override is a legitimate isolated developer queue, not a
    /// way to bypass the validation.
    static func resolveQueue(_ override: String?) throws -> ModelSupportQueue {
        if let override {
            let url = URL(fileURLWithPath: override).standardizedFileURL
            if (try? FileManager.default.destinationOfSymbolicLink(atPath: url.path)) != nil {
                throw CapabilityImportError.unsafeFile
            }
            try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true,
                                                   attributes: [.posixPermissions: 0o700])
            return ModelSupportQueue(directory: url)
        }
        return ModelSupportQueue(directory: try ModelSupportQueue.applicationSupportDirectory(create: true))
    }

    /// Only the model key, the input fingerprint and the fixed pending gates.
    static func summary(for record: CapabilityRecord) -> String {
        let payload: [String: String] = [
            "modelKey": record.report.modelKey,
            "capabilitiesFingerprint": record.fingerprint,
            "origin": record.origin.rawValue,
            "programTests": "pending",
            "physicalVerification": "pending",
            "release": "pending"
        ]
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        guard let data = try? encoder.encode(payload),
              let text = String(data: data, encoding: .utf8) else { return "{}" }
        return text
    }

    /// A fixed code only. The path, the file name and the file content are
    /// never echoed.
    static func reportFailure(_ error: any Error) {
        let code: String
        switch error {
        case let error as CapabilityImportError: code = error.rawValue
        case let error as CapabilityRecordError: code = error.rawValue
        case is CocoaError: code = "storage_failed"
        default: code = "import_failed"
        }
        let message = "utuvo-mouse: capability import failed / 能力匯入失敗 [\(code)]\n"
        FileHandle.standardError.write(Data(message.utf8))
    }
}
