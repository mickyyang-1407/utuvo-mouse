import Foundation
import Testing
import UTUVOMouseCore
@testable import UTUVOMouseSupport

/// Synthetic capability data only. No device, no queue of the real app.
@Suite("Capability records — synthetic data only")
struct CapabilityRecordTests {
    static let modelKey = "046d-b025-bluetooth"

    private static var fixtureURL: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("fixtures/capability-fingerprint.json")
    }

    private func temporaryQueue() throws -> ModelSupportQueue {
        let directory = MouseTestTemporaryRoot.url.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
        return ModelSupportQueue(directory: directory)
    }

    private func validReportObject() -> [String: Any] {
        [
            "schemaVersion": 1,
            "modelKey": Self.modelKey,
            "vendorID": 0x046D,
            "productID": 0xB025,
            "transport": "bluetooth",
            "readOnly": true,
            "configurationWritesEnabled": false,
            "protocolVersion": ["major": 2, "minor": 0],
            "featureIDs": ["0000", "0001", "1004", "2201"]
        ]
    }

    private func data(_ object: [String: Any]) throws -> Data {
        try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
    }

    private func capabilityRecord(origin: CapabilityRecordOrigin = .imported,
                        features: [String] = ["0000", "0001", "1004", "2201"]) throws -> CapabilityRecord {
        var object = validReportObject()
        object["featureIDs"] = features
        let report = try CapabilityRecordCodec.decodeReport(from: try data(object))
        return try CapabilityRecordCodec.makeRecord(report: report, origin: origin)
    }

    // MARK: - Cross-language fingerprint

    @Test("the shared fixture gives the same fingerprint as the fixture file")
    func crossLanguageFingerprintFixture() throws {
        let fixtureData = try Data(contentsOf: Self.fixtureURL)
        let fixture = try #require(JSONSerialization.jsonObject(with: fixtureData) as? [String: Any])
        let expected = try #require(fixture["fingerprint"] as? String)
        let canonical = try #require(fixture["canonical"] as? String)
        let origin = try #require(fixture["origin"] as? String)
        let originValue = try #require(CapabilityRecordOrigin(rawValue: origin))
        let reportObject = try #require(fixture["report"] as? [String: Any])

        let report = try CapabilityRecordCodec.decodeReport(from: try data(reportObject))
        let record = try CapabilityRecordCodec.makeRecord(report: report, origin: originValue)
        #expect(record.fingerprint == expected)
        let rebuilt = CapabilityFingerprint.canonical(
            modelKey: report.modelKey, origin: originValue,
            major: report.protocolVersion.major, minor: report.protocolVersion.minor,
            featureIDs: report.featureIDs)
        #expect(rebuilt == canonical)
        #expect(!canonical.hasSuffix("\n"))
        #expect(canonical.split(separator: "\n").count == 5)
    }

    @Test("the canonical fingerprint ignores feature order but not content")
    func canonicalIsStable() throws {
        let first = try capabilityRecord(features: ["0000", "0001", "1004"])
        let second = try capabilityRecord(features: ["0000", "0001", "1004"])
        #expect(first.fingerprint == second.fingerprint)
        let other = try capabilityRecord(features: ["0000", "0001", "1004", "2201"])
        #expect(other.fingerprint != first.fingerprint)
        let imported = try capabilityRecord(origin: .imported, features: ["0000", "0001", "1004"])
        let collected = try capabilityRecord(origin: .appReadOnly, features: ["0000", "0001", "1004"])
        #expect(imported.fingerprint != collected.fingerprint)
    }

    // MARK: - Strict validation

    @Test("extra private fields are rejected")
    func rejectsExtraFields() throws {
        var object = validReportObject()
        object["serialNumber"] = "PRIVATE-SERIAL"
        #expect(throws: CapabilityRecordError.unexpectedField) {
            try CapabilityRecordCodec.decodeReport(from: try data(object))
        }
        var version = validReportObject()
        version["protocolVersion"] = ["major": 2, "minor": 0, "private": 1]
        #expect(throws: CapabilityRecordError.unexpectedField) {
            try CapabilityRecordCodec.decodeReport(from: try data(version))
        }
    }

    @Test("booleans never pass as integers and numbers never pass as booleans")
    func rejectsWrongTypes() throws {
        var readOnly = validReportObject()
        readOnly["readOnly"] = 1
        #expect(throws: CapabilityRecordError.typeMismatch) {
            try CapabilityRecordCodec.decodeReport(from: try data(readOnly))
        }
        var writes = validReportObject()
        writes["configurationWritesEnabled"] = 0
        #expect(throws: CapabilityRecordError.typeMismatch) {
            try CapabilityRecordCodec.decodeReport(from: try data(writes))
        }
        var schema = validReportObject()
        schema["schemaVersion"] = true
        #expect(throws: CapabilityRecordError.typeMismatch) {
            try CapabilityRecordCodec.decodeReport(from: try data(schema))
        }
        // A fractional number stays fractional in the raw text; a JSON writer
        // would round it to an integer.
        let fractionalText = "{\"schemaVersion\": 1.0, \"modelKey\": \"046d-b025-bluetooth\","
            + "\"vendorID\": 1133, \"productID\": 45093, \"transport\": \"bluetooth\","
            + "\"readOnly\": true, \"configurationWritesEnabled\": false,"
            + "\"protocolVersion\": {\"major\": 2, \"minor\": 0},"
            + "\"featureIDs\": [\"0000\", \"0001\", \"1004\", \"2201\"]}"
        #expect(throws: CapabilityRecordError.typeMismatch) {
            try CapabilityRecordCodec.decodeReport(from: Data(fractionalText.utf8))
        }
        var vendor = validReportObject()
        vendor["vendorID"] = "046D"
        #expect(throws: CapabilityRecordError.typeMismatch) {
            try CapabilityRecordCodec.decodeReport(from: try data(vendor))
        }
    }

    @Test("a foreign model, vendor, product or transport is rejected")
    func rejectsForeignIdentity() throws {
        var model = validReportObject()
        model["modelKey"] = "046d-c54d-receiver"
        #expect(throws: CapabilityRecordError.identityMismatch) {
            try CapabilityRecordCodec.decodeReport(from: try data(model))
        }
        var vendor = validReportObject()
        vendor["vendorID"] = 0x1234
        #expect(throws: CapabilityRecordError.identityMismatch) {
            try CapabilityRecordCodec.decodeReport(from: try data(vendor))
        }
        var product = validReportObject()
        product["productID"] = 0xC54D
        #expect(throws: CapabilityRecordError.identityMismatch) {
            try CapabilityRecordCodec.decodeReport(from: try data(product))
        }
        var transport = validReportObject()
        transport["transport"] = "usb"
        #expect(throws: CapabilityRecordError.identityMismatch) {
            try CapabilityRecordCodec.decodeReport(from: try data(transport))
        }
    }

    @Test("a writable report or an unsupported protocol is rejected")
    func rejectsWritableAndUnsupportedProtocol() throws {
        var writable = validReportObject()
        writable["configurationWritesEnabled"] = true
        #expect(throws: CapabilityRecordError.configurationWritesForbidden) {
            try CapabilityRecordCodec.decodeReport(from: try data(writable))
        }
        var notReadOnly = validReportObject()
        notReadOnly["readOnly"] = false
        #expect(throws: CapabilityRecordError.readOnlyRequired) {
            try CapabilityRecordCodec.decodeReport(from: try data(notReadOnly))
        }
        var protocol3 = validReportObject()
        protocol3["protocolVersion"] = ["major": 3, "minor": 0]
        #expect(throws: CapabilityRecordError.unsupportedProtocol) {
            try CapabilityRecordCodec.decodeReport(from: try data(protocol3))
        }
        var minor = validReportObject()
        minor["protocolVersion"] = ["major": 2, "minor": 40]
        #expect(throws: CapabilityRecordError.unsupportedProtocol) {
            try CapabilityRecordCodec.decodeReport(from: try data(minor))
        }
    }

    @Test("duplicate, unsorted, lowercase or incomplete feature IDs are rejected")
    func rejectsInvalidFeatureIDs() throws {
        for features in [["0000", "0001", "1004", "1004"], ["1004", "0001", "0000"],
                         ["0000", "0001", "1004", "1b0c"], ["0001", "1004"],
                         ["0000", "1004"], ["2201"]] {
            var object = validReportObject()
            object["featureIDs"] = features
            #expect(throws: CapabilityRecordError.invalidFeatureIDs) {
                try CapabilityRecordCodec.decodeReport(from: try data(object))
            }
        }
    }

    @Test("an oversized payload is rejected before it is parsed")
    func rejectsOversizedPayload() throws {
        var object = validReportObject()
        object["featureIDs"] = (0..<64).map { String(format: "%04X", 0x2000 + $0) }
        let payload = try data(object)
        #expect(payload.count <= CapabilityRecordCodec.maximumReportByteCount)
        var padded = object
        padded["padding"] = String(repeating: "A", count: CapabilityRecordCodec.maximumReportByteCount)
        #expect(throws: CapabilityRecordError.tooLarge) {
            try CapabilityRecordCodec.decodeReport(from: try data(padded))
        }
        #expect(throws: CapabilityRecordError.tooLarge) {
            try CapabilityRecordCodec.decodeReport(from: Data(repeating: 0x20, count: 16 * 1024 + 1))
        }
    }

    @Test("malformed JSON is rejected without a value")
    func rejectsMalformedJSON() {
        #expect(throws: CapabilityRecordError.malformed) {
            try CapabilityRecordCodec.decodeReport(from: Data("not-json".utf8))
        }
        #expect(throws: CapabilityRecordError.malformed) {
            try CapabilityRecordCodec.decodeReport(from: Data("[]".utf8))
        }
    }

    // MARK: - Envelope

    @Test("the envelope has exactly five safe fields and no hardware claim")
    func envelopeShape() throws {
        let record = try capabilityRecord()
        let encoded = try CapabilityRecordCodec.encode(record)
        let object = try #require(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        #expect(Set(object.keys) == Set(["schemaVersion", "origin", "report",
                                          "hardwareBehaviorVerified", "released"]))
        #expect(object["hardwareBehaviorVerified"] as? Bool == false)
        #expect(object["released"] as? Bool == false)
        let report = try #require(object["report"] as? [String: Any])
        #expect(Set(report.keys) == Set(["schemaVersion", "modelKey", "vendorID", "productID", "transport",
                                          "readOnly", "configurationWritesEnabled", "protocolVersion",
                                          "featureIDs"]))
        let text = try #require(String(data: encoded, encoding: .utf8))
        for forbidden in ["serial", "name", "address", "/Users/", "202", "timestamp"] {
            #expect(!text.lowercased().contains(forbidden))
        }
    }

    @Test("a stored record can never claim hardware behaviour or a release")
    func storedRecordStaysStrict() throws {
        let record = try capabilityRecord()
        var object = try #require(JSONSerialization.jsonObject(with: try CapabilityRecordCodec.encode(record))
                                   as? [String: Any])
        object["hardwareBehaviorVerified"] = true
        #expect(throws: CapabilityRecordError.forbiddenClaim) {
            try CapabilityRecordCodec.decodeRecord(from: try JSONSerialization.data(withJSONObject: object))
        }
        var released = try #require(JSONSerialization.jsonObject(with: try CapabilityRecordCodec.encode(record))
                                    as? [String: Any])
        released["released"] = true
        #expect(throws: CapabilityRecordError.forbiddenClaim) {
            try CapabilityRecordCodec.decodeRecord(from: try JSONSerialization.data(withJSONObject: released))
        }
        var extra = try #require(JSONSerialization.jsonObject(with: try CapabilityRecordCodec.encode(record))
                                 as? [String: Any])
        extra["configurationWritesEnabled"] = true
        #expect(throws: CapabilityRecordError.unexpectedField) {
            try CapabilityRecordCodec.decodeRecord(from: try JSONSerialization.data(withJSONObject: extra))
        }
        var origin = try #require(JSONSerialization.jsonObject(with: try CapabilityRecordCodec.encode(record))
                                  as? [String: Any])
        origin["origin"] = "deviceConfirmed"
        #expect(throws: CapabilityRecordError.invalidOrigin) {
            try CapabilityRecordCodec.decodeRecord(from: try JSONSerialization.data(withJSONObject: origin))
        }
    }

    // MARK: - Queue

    @Test("the queue stores the record atomically and never touches the job files")
    func queueStoresCapabilities() throws {
        let queue = try temporaryQueue()
        defer { try? FileManager.default.removeItem(at: queue.directory) }
        let request = try #require(ModelSupportRequest(capabilityReport: try CapabilityRecordCodec
            .decodeReport(from: try data(validReportObject()))))
        try queue.ensureJob(request)
        let job = queue.directory.appendingPathComponent(Self.modelKey)
        let reportBefore = try Data(contentsOf: job.appendingPathComponent("report.json"))
        let taskBefore = try Data(contentsOf: job.appendingPathComponent("TASK.md"))
        let queued = "{\"schemaVersion\":1,\"modelKey\":\"046d-b025-bluetooth\",\"phase\":\"queued\","
            + "\"programTestsPassed\":false,\"hardwareVerified\":false,\"released\":false}"
        try Data(queued.utf8).write(to: job.appendingPathComponent("status.json"))

        let record = try capabilityRecord()
        #expect(try queue.saveCapabilities(record, for: Self.modelKey))
        let loaded = try #require(try queue.capabilities(for: Self.modelKey))
        #expect(loaded == record)
        #expect(loaded.origin == .imported)
        #expect(try Data(contentsOf: job.appendingPathComponent("report.json")) == reportBefore)
        #expect(try Data(contentsOf: job.appendingPathComponent("TASK.md")) == taskBefore)
        let status = try #require(JSONSerialization.jsonObject(
            with: try Data(contentsOf: job.appendingPathComponent("status.json"))) as? [String: Any])
        #expect(status["phase"] as? String == "queued")

        // The same input is not a new revision; a changed one is.
        #expect(try !queue.saveCapabilities(record, for: Self.modelKey))
        let changed = try capabilityRecord(features: ["0000", "0001", "1004", "2201", "8061"])
        #expect(try queue.saveCapabilities(changed, for: Self.modelKey))
        #expect(try queue.capabilities(for: Self.modelKey)?.fingerprint == changed.fingerprint)
    }

    @Test("a model key that disagrees with the record is refused")
    func queueRefusesForeignModelKey() throws {
        let queue = try temporaryQueue()
        defer { try? FileManager.default.removeItem(at: queue.directory) }
        let record = try capabilityRecord()
        #expect(throws: (any Error).self) { try queue.saveCapabilities(record, for: "046d-c54d-receiver") }
        #expect(throws: (any Error).self) { try queue.saveCapabilities(record, for: "../../escape") }
    }

    @Test("a corrupt, oversized or symlinked capability file is refused")
    func queueRefusesUnsafeCapabilityFiles() throws {
        let queue = try temporaryQueue()
        defer { try? FileManager.default.removeItem(at: queue.directory) }
        let request = try #require(ModelSupportRequest(capabilityReport: try CapabilityRecordCodec
            .decodeReport(from: try data(validReportObject()))))
        try queue.ensureJob(request)
        let file = queue.directory.appendingPathComponent(Self.modelKey)
            .appendingPathComponent(ModelSupportQueue.capabilitiesFileName)
        try Data("not-json".utf8).write(to: file)
        #expect(throws: (any Error).self) { try queue.capabilities(for: Self.modelKey) }
        try Data(repeating: 0x20, count: CapabilityRecordCodec.maximumRecordByteCount + 1).write(to: file)
        #expect(throws: (any Error).self) { try queue.capabilities(for: Self.modelKey) }
        try FileManager.default.removeItem(at: file)
        try FileManager.default.createSymbolicLink(at: file, withDestinationURL: file.deletingLastPathComponent())
        #expect(throws: (any Error).self) { try queue.capabilities(for: Self.modelKey) }
        try FileManager.default.removeItem(at: file)
        // A missing file is not an error: metadata-only jobs stay valid.
        #expect(try queue.capabilities(for: Self.modelKey) == nil)
    }

    @Test("a corrupt old capability file is repaired by a valid record")
    func queueRepairsCorruptCapabilityFile() throws {
        let queue = try temporaryQueue()
        defer { try? FileManager.default.removeItem(at: queue.directory) }
        let request = try #require(ModelSupportRequest(capabilityReport: try CapabilityRecordCodec
            .decodeReport(from: try data(validReportObject()))))
        try queue.ensureJob(request)
        let file = queue.directory.appendingPathComponent(Self.modelKey)
            .appendingPathComponent(ModelSupportQueue.capabilitiesFileName)
        try Data("not-json".utf8).write(to: file)
        #expect(throws: (any Error).self) { try queue.capabilities(for: Self.modelKey) }
        let record = try capabilityRecord()
        try queue.saveCapabilities(record, for: Self.modelKey)
        #expect(try queue.capabilities(for: Self.modelKey) == record)
    }

    // MARK: - Progress and coverage

    @Test("an old status without a fingerprint still loads")
    func oldStatusStillLoads() throws {
        let queue = try temporaryQueue()
        defer { try? FileManager.default.removeItem(at: queue.directory) }
        let request = try #require(ModelSupportRequest(capabilityReport: try CapabilityRecordCodec
            .decodeReport(from: try data(validReportObject()))))
        try queue.ensureJob(request)
        let status = queue.directory.appendingPathComponent(Self.modelKey).appendingPathComponent("status.json")
        let passed = "{\"schemaVersion\":1,\"modelKey\":\"046d-b025-bluetooth\",\"phase\":\"needsHardware\","
            + "\"programTestsPassed\":true,\"hardwareVerified\":false,\"released\":false}"
        try Data(passed.utf8).write(to: status)
        let progress = try queue.progress(for: request)
        #expect(progress.phase == .needsHardware)
        #expect(progress.capabilitiesFingerprint == nil)
        #expect(progress.isValidCandidateProgress)
        // The companion writes an explicit null for a job without capability input.
        let nulled = "{\"schemaVersion\":1,\"modelKey\":\"046d-b025-bluetooth\",\"phase\":\"needsHardware\","
            + "\"programTestsPassed\":true,\"hardwareVerified\":false,\"released\":false,"
            + "\"capabilitiesFingerprint\":null}"
        try Data(nulled.utf8).write(to: status)
        #expect(try queue.progress(for: request).capabilitiesFingerprint == nil)
    }

    @Test("a status with a malformed fingerprint is refused")
    func refusesMalformedFingerprint() throws {
        let queue = try temporaryQueue()
        defer { try? FileManager.default.removeItem(at: queue.directory) }
        let request = try #require(ModelSupportRequest(capabilityReport: try CapabilityRecordCodec
            .decodeReport(from: try data(validReportObject()))))
        try queue.ensureJob(request)
        let status = queue.directory.appendingPathComponent(Self.modelKey).appendingPathComponent("status.json")
        let forged = "{\"schemaVersion\":1,\"modelKey\":\"046d-b025-bluetooth\",\"phase\":\"needsHardware\","
            + "\"programTestsPassed\":true,\"hardwareVerified\":false,\"released\":false,"
            + "\"capabilitiesFingerprint\":\"NOT-A-FINGERPRINT\"}"
        try Data(forged.utf8).write(to: status)
        #expect(throws: (any Error).self) { try queue.progress(for: request) }
    }

    @Test("an old program result never covers a newer capability input")
    func coverageDistinguishesInputRevisions() throws {
        let record = try capabilityRecord()
        let current = ModelSupportProgress(modelKey: Self.modelKey, phase: .needsHardware,
                                           programTestsPassed: true,
                                           capabilitiesFingerprint: record.fingerprint)
        #expect(ModelSupportCoverage.coverage(record: record, progress: current) == .currentInput)
        let stale = ModelSupportProgress(modelKey: Self.modelKey, phase: .needsHardware,
                                         programTestsPassed: true,
                                         capabilitiesFingerprint: String(repeating: "a", count: 64))
        #expect(ModelSupportCoverage.coverage(record: record, progress: stale) == .staleInput)
        let old = ModelSupportProgress(modelKey: Self.modelKey, phase: .needsHardware, programTestsPassed: true)
        #expect(ModelSupportCoverage.coverage(record: record, progress: old) == .unattributed)
        #expect(ModelSupportCoverage.coverage(record: nil, progress: current) == .noCapabilityInput)
        #expect(ModelSupportCoverage.coverage(record: record, progress: nil) == .noCapabilityInput)
    }

    // MARK: - Import routing

    @Test("the import route is parsed before anything else happens")
    func importRouting() throws {
        #expect(try CapabilityImportInvocation.parse([]) == .notRequested)
        #expect(try CapabilityImportInvocation.parse(["--probe"]) == .notRequested)
        #expect(try CapabilityImportInvocation.parse(["--import-capabilities", "--help"]) == .help)
        #expect(try CapabilityImportInvocation.parse(["--import-capabilities", "-h"]) == .help)
        #expect(try CapabilityImportInvocation.parse(["--import-capabilities", "/tmp/report.json"])
                == .importCapabilities(file: "/tmp/report.json", supportDirectory: nil))
        #expect(try CapabilityImportInvocation.parse(["--import-capabilities", "/tmp/report.json",
                                                      "--support-directory", "/tmp/queue"])
                == .importCapabilities(file: "/tmp/report.json", supportDirectory: "/tmp/queue"))
        #expect(try CapabilityImportInvocation.parse(["--import-capabilities=/tmp/report.json"])
                == .importCapabilities(file: "/tmp/report.json", supportDirectory: nil))
    }

    @Test("mixed modes and malformed arguments are refused")
    func importRoutingRejectsBadInput() throws {
        for arguments in [["--import-capabilities", "/tmp/report.json", "--inspect-capabilities"],
                          ["--import-capabilities", "/tmp/report.json", "--probe"],
                          ["--import-capabilities", "/tmp/report.json", "--demo"],
                          ["--import-capabilities", "/tmp/report.json", "--allow-read-only-hidpp"]] {
            #expect(throws: CapabilityImportError.mixedModes) {
                try CapabilityImportInvocation.parse(arguments)
            }
        }
        for arguments in [["--import-capabilities"],
                          ["--import-capabilities", "--support-directory", "/tmp/queue"],
                          ["--import-capabilities", "/tmp/a.json", "/tmp/b.json"],
                          ["--import-capabilities", "/tmp/report.json", "--support-directory"],
                          ["--import-capabilities", "/tmp/report.json", "--unknown"]] {
            #expect(throws: CapabilityImportError.invalidArguments) {
                try CapabilityImportInvocation.parse(arguments)
            }
        }
    }
}
