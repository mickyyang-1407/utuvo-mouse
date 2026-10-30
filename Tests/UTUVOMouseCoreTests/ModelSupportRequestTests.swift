import Foundation
import Testing
import UTUVOMouseCore
@testable import UTUVOMouseSupport

@Suite("Model support requests — synthetic data only")
struct ModelSupportRequestTests {
    private func snapshot(product: Int = 0xB025, model: MouseModel = .unknown,
                          transport: DeviceTransportKind = .bluetooth, seed: String = "PRIVATE-SERIAL") -> DeviceSnapshot {
        var value = DeviceSnapshot(identity: DeviceIdentity(
            stableID: seed, model: model, vendorID: 0x046D, productID: product,
            transport: transport, deviceIndex: 3, productName: "PRIVATE-NAME 00:11:22:33:44:55"))
        value.protocolVersion = "PRIVATE-PROTOCOL"
        value.issues = ["PRIVATE-ERROR"]
        value.onboardInfoRaw = [99, 98, 97]
        return value
    }

    private func temporaryQueue() throws -> ModelSupportQueue {
        let directory = MouseTestTemporaryRoot.url.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
        return ModelSupportQueue(directory: directory)
    }

    @Test func reportHasOnlyModelMetadata() throws {
        let request = try #require(ModelSupportRequest(snapshot: snapshot()))
        let data = try JSONEncoder().encode(request)
        let text = try #require(String(data: data, encoding: .utf8))
        #expect(!text.contains("PRIVATE"))
        #expect(!text.contains("00:11:22"))
        let object = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        #expect(Set(object.keys) == Set(["schemaVersion", "modelKey", "vendorID", "productID", "transport",
                                          "catalogName", "observation", "featureIDs"]))
        #expect(request.catalogName == "MX Anywhere 3")
        #expect(request.observation == "metadataOnly")
        #expect(request.modelKey == "046d-b025-bluetooth")
        #expect(request.isValid)
        #expect(!request.taskMarkdown.contains("PRIVATE"))
    }

    @Test func deduplicatesByModelAndTransportNotUnit() throws {
        let first = try #require(ModelSupportRequest(snapshot: snapshot(seed: "UNIT-ONE")))
        let second = try #require(ModelSupportRequest(snapshot: snapshot(seed: "UNIT-TWO")))
        let differentTransport = try #require(ModelSupportRequest(snapshot: snapshot(transport: .usb)))
        #expect(first == second)
        #expect(first.modelKey != differentTransport.modelKey)
        #expect(differentTransport.catalogName == nil)
        let queue = try temporaryQueue()
        defer { try? FileManager.default.removeItem(at: queue.directory) }
        #expect(try queue.enqueue(first))
        let job = queue.directory.appendingPathComponent(first.modelKey)
        let progress = ModelSupportProgress(modelKey: first.modelKey, phase: .needsHardware, programTestsPassed: true)
        try JSONEncoder().encode(progress).write(to: job.appendingPathComponent("status.json"))
        let before = try Data(contentsOf: job.appendingPathComponent("status.json"))
        #expect(try !queue.enqueue(second))
        #expect(try queue.progress(for: first) == progress)
        #expect(try Data(contentsOf: job.appendingPathComponent("status.json")) == before)
        #expect(try queue.enqueue(differentTransport))
        #expect(try queue.progress(for: differentTransport).phase == .queued)
    }

    @Test func excludesDemoSupportedBareReceiverAndOtherVendors() {
        #expect(ModelSupportRequest(snapshot: snapshot(model: .mxMaster4)) == nil)
        #expect(ModelSupportRequest(snapshot: snapshot(model: .superstrike)) == nil)
        #expect(ModelSupportRequest(snapshot: snapshot(model: .receiver)) == nil)
        var value = snapshot()
        value.isDemo = true
        #expect(ModelSupportRequest(snapshot: value) == nil)
        value.isDemo = false
        value.identity.vendorID = 0x1234
        #expect(ModelSupportRequest(snapshot: value) == nil)
        #expect(ModelSupportRequest(snapshot: snapshot(product: -1)) == nil)
        #expect(ModelSupportRequest(snapshot: snapshot(product: 65536)) == nil)
    }

    @Test func exportsFeatureIDsWithoutRuntimeIndexesOrRawReplies() throws {
        var value = snapshot(product: 0x1234)
        value.features = [0x2201: 7, 0x1B04: 10]
        let request = try #require(ModelSupportRequest(snapshot: value))
        #expect(request.featureIDs == ["1B04", "2201"])
        #expect(request.observation == "featureIDsOnly")
        #expect(request.catalogName == nil)
        #expect(request.isValid)
        // A shared feature never grants configuration support.
        #expect(value.identity.model == .unknown)
        #expect(!value.identity.model.supportsConfiguration)
    }

    @Test(arguments: ["../../escape", "046d-b025-usb", "PRIVATE-SERIAL"])
    func rejectsDecodedPathOrModelForgery(key: String) throws {
        let original = try #require(ModelSupportRequest(snapshot: snapshot()))
        var json = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(original)) as? [String: Any])
        json["modelKey"] = key
        let forged = try JSONDecoder().decode(ModelSupportRequest.self, from: JSONSerialization.data(withJSONObject: json))
        #expect(!forged.isValid)
        let queue = try temporaryQueue()
        defer { try? FileManager.default.removeItem(at: queue.directory) }
        #expect(throws: (any Error).self) { try queue.enqueue(forged) }
        #expect(throws: (any Error).self) { try queue.progress(for: forged) }
    }

    @Test(arguments: ["hardwareVerified", "released", "programTestsPassed"])
    func rejectsForgedSuccess(field: String) throws {
        let request = try #require(ModelSupportRequest(snapshot: snapshot()))
        let queue = try temporaryQueue()
        defer { try? FileManager.default.removeItem(at: queue.directory) }
        try queue.enqueue(request)
        let status = ModelSupportProgress(modelKey: request.modelKey, phase: .queued)
        var json = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(status)) as? [String: Any])
        json[field] = true
        try JSONSerialization.data(withJSONObject: json).write(to: queue.directory
            .appendingPathComponent(request.modelKey).appendingPathComponent("status.json"))
        #expect(throws: (any Error).self) { try queue.progress(for: request) }
    }

    @Test func rejectsCorruptOversizedAndSymlinkStatus() throws {
        let request = try #require(ModelSupportRequest(snapshot: snapshot()))
        let queue = try temporaryQueue()
        defer { try? FileManager.default.removeItem(at: queue.directory) }
        try queue.enqueue(request)
        let status = queue.directory.appendingPathComponent(request.modelKey).appendingPathComponent("status.json")
        for data in [Data("not-json".utf8), Data(repeating: 0x20, count: 4097)] {
            try data.write(to: status)
            #expect(throws: (any Error).self) { try queue.progress(for: request) }
        }
        try FileManager.default.removeItem(at: status)
        try FileManager.default.createSymbolicLink(at: status, withDestinationURL: queue.directory.appendingPathComponent("other"))
        // Broken links must not be interpreted as a missing (queued) status.
        #expect(throws: (any Error).self) { try queue.progress(for: request) }
    }

    @Test func missingTaskIsNotShownAsQueued() throws {
        let request = try #require(ModelSupportRequest(snapshot: snapshot()))
        let queue = try temporaryQueue()
        defer { try? FileManager.default.removeItem(at: queue.directory) }
        #expect(throws: (any Error).self) { try queue.progress(for: request) }
    }
}
