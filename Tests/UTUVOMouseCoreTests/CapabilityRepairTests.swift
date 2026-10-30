import Foundation
import Testing
import UTUVOMouseCore
import UTUVOMouseLocalization
@testable import UTUVOMouseSupport

/// Regressions of the bounded repair round.
///
/// Synthetic data only: no device, no queue of the real app, no collection.
/// The coverage tests are pure: they never read or write a job directory.
@Suite("Capability repair — synthetic data only")
struct CapabilityRepairTests {
    static let modelKey = "046d-b025-bluetooth"
    /// Another model of the same vendor, with a valid model key shape.
    static let otherModelKey = "046d-ffff-bluetooth"

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

    private func capabilityRecord(origin: CapabilityRecordOrigin = .imported) throws -> CapabilityRecord {
        let report = try CapabilityRecordCodec.decodeReport(from: try data(validReportObject()))
        return try CapabilityRecordCodec.makeRecord(report: report, origin: origin)
    }

    private func request() throws -> ModelSupportRequest {
        try #require(ModelSupportRequest(capabilityReport: try CapabilityRecordCodec
            .decodeReport(from: try data(validReportObject()))))
    }

    // MARK: - Stored record identity

    @Test("a stored record of another model is refused")
    func refusesForeignStoredRecord() throws {
        let queue = try temporaryQueue()
        defer { try? FileManager.default.removeItem(at: queue.directory) }
        // The stored record is the B025 record, the job directory is another
        // model. It is never this job's input.
        let job = queue.directory.appendingPathComponent(Self.otherModelKey, isDirectory: true)
        try FileManager.default.createDirectory(at: job, withIntermediateDirectories: false)
        let record = try capabilityRecord()
        try CapabilityRecordCodec.encode(record)
            .write(to: job.appendingPathComponent(ModelSupportQueue.capabilitiesFileName))
        #expect(throws: (any Error).self) { try queue.capabilities(for: Self.otherModelKey) }
        // The record of its own model is unaffected.
        #expect(try queue.capabilities(for: Self.modelKey) == nil)
    }

    @Test("a stored record that names another model never decodes")
    func refusesForeignRecordContent() throws {
        let queue = try temporaryQueue()
        defer { try? FileManager.default.removeItem(at: queue.directory) }
        try queue.ensureJob(try request())
        var object = try #require(JSONSerialization.jsonObject(
            with: try CapabilityRecordCodec.encode(try capabilityRecord())) as? [String: Any])
        var report = try #require(object["report"] as? [String: Any])
        report["modelKey"] = Self.otherModelKey
        object["report"] = report
        try JSONSerialization.data(withJSONObject: object)
            .write(to: queue.directory.appendingPathComponent(Self.modelKey)
                .appendingPathComponent(ModelSupportQueue.capabilitiesFileName))
        #expect(throws: (any Error).self) { try queue.capabilities(for: Self.modelKey) }
    }

    @Test("a capability file that is not a regular file is refused")
    func refusesNonRegularCapabilityFile() throws {
        let queue = try temporaryQueue()
        defer { try? FileManager.default.removeItem(at: queue.directory) }
        try queue.ensureJob(try request())
        // A directory in place of the stored input is never read.
        try FileManager.default.createDirectory(
            at: queue.directory.appendingPathComponent(Self.modelKey)
                .appendingPathComponent(ModelSupportQueue.capabilitiesFileName),
            withIntermediateDirectories: false)
        #expect(throws: (any Error).self) { try queue.capabilities(for: Self.modelKey) }
    }

    @Test("an invalid record never replaces a valid stored record")
    func invalidRecordNeverReplacesValidData() throws {
        let queue = try temporaryQueue()
        defer { try? FileManager.default.removeItem(at: queue.directory) }
        try queue.ensureJob(try request())
        let valid = try capabilityRecord()
        try queue.saveCapabilities(valid, for: Self.modelKey)
        // A hand-built record that was never validated.
        let writable = CapabilityRecord(origin: .imported, report: CapabilityReport(
            schemaVersion: 1, modelKey: Self.modelKey, vendorID: 0x046D, productID: 0xB025,
            transport: "bluetooth", readOnly: true, configurationWritesEnabled: true,
            protocolVersion: .init(major: 2, minor: 0), featureIDs: ["0000", "0001"]))
        #expect(throws: CapabilityRecordError.configurationWritesForbidden) {
            try queue.saveCapabilities(writable, for: Self.modelKey)
        }
        #expect(throws: CapabilityRecordError.configurationWritesForbidden) {
            try CapabilityRecordCodec.encode(writable)
        }
        let incomplete = CapabilityRecord(origin: .appReadOnly, report: CapabilityReport(
            schemaVersion: 1, modelKey: Self.modelKey, vendorID: 0x046D, productID: 0xB025,
            transport: "bluetooth", readOnly: true, configurationWritesEnabled: false,
            protocolVersion: .init(major: 2, minor: 0), featureIDs: ["1004", "0000"]))
        #expect(throws: CapabilityRecordError.invalidFeatureIDs) {
            try queue.saveCapabilities(incomplete, for: Self.modelKey)
        }
        // The valid record is still the stored one.
        #expect(try queue.capabilities(for: Self.modelKey) == valid)
    }

    // MARK: - Coverage and program state

    @Test("an invalid capability input never yields a coverage claim")
    func invalidInputHasNoCoverage() throws {
        let record = try capabilityRecord()
        let passed = ModelSupportProgress(modelKey: Self.modelKey, phase: .needsHardware,
                                          programTestsPassed: true,
                                          capabilitiesFingerprint: record.fingerprint)
        #expect(ModelSupportCoverage.coverage(record: record, progress: passed,
                                              invalidInput: true) == .invalidInput)
        #expect(ModelSupportProgram.state(phase: .needsHardware, record: record,
                                          progress: passed, invalidInput: true) == .invalidInput)
        #expect(ModelSupportProgram.state(phase: .needsHardware, record: nil,
                                          progress: passed, invalidInput: true) == .invalidInput)
    }

    @Test("a newer input than the tested one is pending, never a success")
    func newerInputIsPending() throws {
        let record = try capabilityRecord()
        let older = ModelSupportProgress(modelKey: Self.modelKey, phase: .needsHardware,
                                         programTestsPassed: true,
                                         capabilitiesFingerprint: String(repeating: "a", count: 64))
        #expect(ModelSupportCoverage.coverage(record: record, progress: older) == .staleInput)
        #expect(ModelSupportProgram.state(phase: .needsHardware, record: record,
                                          progress: older) == .olderInput)
    }

    @Test("a removed capability record is not a current-input success")
    func removedRecordIsNotCurrent() throws {
        let tested = ModelSupportProgress(modelKey: Self.modelKey, phase: .needsHardware,
                                          programTestsPassed: true,
                                          capabilitiesFingerprint: String(repeating: "a", count: 64))
        #expect(ModelSupportProgram.state(phase: .needsHardware, record: nil,
                                          progress: tested) == .noCapabilityInput)
        // A legacy status without a fingerprint stays compatible and is
        // identified as covering metadata only.
        let legacy = ModelSupportProgress(modelKey: Self.modelKey, phase: .needsHardware,
                                          programTestsPassed: true)
        #expect(ModelSupportProgram.state(phase: .needsHardware, record: nil,
                                          progress: legacy) == .metadataOnly)
        let record = try capabilityRecord()
        #expect(ModelSupportProgram.state(phase: .needsHardware, record: record,
                                          progress: legacy) == .metadataOnly)
    }

    @Test("only the exact current input claims a program coverage")
    func currentInputIsTheOnlyCoverage() throws {
        let record = try capabilityRecord()
        let current = ModelSupportProgress(modelKey: Self.modelKey, phase: .needsHardware,
                                           programTestsPassed: true,
                                           capabilitiesFingerprint: record.fingerprint)
        #expect(ModelSupportCoverage.coverage(record: record, progress: current) == .currentInput)
        #expect(ModelSupportProgram.state(phase: .needsHardware, record: record,
                                          progress: current) == .currentInput)
        #expect(ModelSupportProgram.state(phase: .queued, record: record,
                                          progress: ModelSupportProgress(modelKey: Self.modelKey,
                                                                        phase: .queued)) == .pending)
        #expect(ModelSupportProgram.state(phase: .failed, record: record,
                                          progress: ModelSupportProgress(modelKey: Self.modelKey,
                                                                        phase: .failed)) == .failed)
        #expect(ModelSupportProgram.state(phase: nil, record: nil, progress: nil) == .noTask)
    }

    @Test("no other combination resolves to a current-input state")
    func currentInputIsUnreachable() throws {
        let record = try capabilityRecord()
        let fingerprints: [String?] = [nil, record.fingerprint, String(repeating: "b", count: 64)]
        for phase in ModelSupportPhase.allCases {
            for fingerprint in fingerprints {
                let progress = ModelSupportProgress(modelKey: Self.modelKey, phase: phase,
                                                    programTestsPassed: phase == .needsHardware,
                                                    capabilitiesFingerprint: fingerprint)
                for stored in [CapabilityRecord?.none, .some(record)] {
                    for invalid in [false, true] {
                        let state = ModelSupportProgram.state(phase: phase, record: stored,
                                                              progress: progress,
                                                              invalidInput: invalid)
                        if state == .currentInput {
                            #expect(fingerprint == record.fingerprint)
                            #expect(stored != nil)
                            #expect(invalid == false)
                            #expect(phase == .needsHardware)
                        }
                    }
                }
            }
        }
    }

    // MARK: - Localized program states

    @Test("every program state has an English and a Traditional Chinese text")
    func programStateTextsExist() {
        let english = MouseLocalizer(language: .english)
        let chinese = MouseLocalizer(language: .traditionalChinese)
        for state in ModelSupportProgramState.allCases {
            let key = "support.program." + state.rawValue
            #expect(!english.string(key).hasPrefix("⟦"))
            #expect(!chinese.string(key).hasPrefix("⟦"))
            #expect(english.string(key) != key)
            #expect(chinese.string(key) != key)
        }
        for key in ["support.tests.earlierInput", "support.tests.unavailable",
                    "support.capability.invalid"] {
            #expect(!english.string(key).hasPrefix("⟦"))
            #expect(!chinese.string(key).hasPrefix("⟦"))
        }
    }
}
