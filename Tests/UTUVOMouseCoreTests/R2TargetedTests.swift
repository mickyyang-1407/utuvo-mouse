import Foundation
import Testing
@testable import UTUVOMouseCore
@testable import UTUVOMouseIO

/// Records the actions instead of posting key events.
private final class RecordingPerformer: ActionPerforming, @unchecked Sendable {
    private let lock = NSLock()
    private var recorded: [MappedAction] = []
    func perform(_ action: MappedAction) { lock.withLock { recorded.append(action) } }
    var actions: [MappedAction] { lock.withLock { recorded } }
}

/// A mouse that answers 0x1B04 and the battery / DPI features.
private final class FakeMX: @unchecked Sendable {
    let lock = NSLock()
    var diverted: Set<UInt16> = []
    var hideVerify = false
    var sticky = false
    var hideAfterWrite = false
    /// The DPI list the device answers; the default is a valid one.
    var dpiList: [UInt8] = [0x00, 0x00, 0xC8, 0xE0, 0x32, 0x1F, 0x40]
    /// The current DPI the device answers.
    var dpiCurrent: [UInt8] = [0x00, 0x0C, 0x80]
    /// The sensor index the device echoes.
    var sensorEcho: UInt8 = 0x00

    func reply(to request: [UInt8]) -> [UInt8]? {
        lock.withLock {
            let feature = request[2]
            let function = request[3] >> 4
            let software = request[3] & 0x0F
            let payload = Array(request[4...])
            func frame(_ data: [UInt8]) -> [UInt8] {
                var bytes: [UInt8] = [0x11, request[1], feature, (function << 4) | software]
                bytes.append(contentsOf: data)
                bytes.append(contentsOf: repeatElement(0, count: max(0, 16 - data.count)))
                return bytes
            }
            switch feature {
            case 0x00:
                if function == 0x00 {
                    let id = (UInt16(payload[0]) << 8) | UInt16(payload[1])
                    let index: UInt8 = id == 0x2201 ? 0x14 : (id == 0x1B04 ? 0x05 : 0x00)
                    return frame([index, 0x00, 0x01])
                }
                return frame([0x04, 0x02])
            case 0x14:  // adjustable DPI
                if function == 0x00 { return frame([0x01]) }
                if function == 0x01 { return frame(dpiList) }
                if function == 0x02 { return frame(dpiCurrent) }
                return frame([])
            case 0x05:  // reprogrammable controls
                if function == 0x00 { return frame([0x03]) }
                if function == 0x01 {
                    let index = Int(payload[0])
                    let cids: [UInt16] = [0x0052, 0x0053, 0x0056]
                    guard index < cids.count else { return nil }
                    return frame([
                        UInt8(cids[index] >> 8), UInt8(cids[index] & 0xFF),
                        0x00, 0x01,
                        0x31, 0x03, 0x01, 0x04, 0x05,
                    ])
                }
                if function == 0x02 {
                    let cid = (UInt16(payload[0]) << 8) | UInt16(payload[1])
                    var reported: UInt8 = diverted.contains(cid) ? 0b0000_0001 : 0
                    if hideAfterWrite {
                        hideAfterWrite = false
                        hideVerify = false
                        reported = 0
                    }
                    return frame([UInt8(cid >> 8), UInt8(cid & 0xFF), reported, 0x00, 0x00, 0x00])
                }
                if function == 0x03 {
                    let cid = (UInt16(payload[0]) << 8) | UInt16(payload[1])
                    let change = payload[2]
                    if change & 0b0000_0010 != 0 {
                        if change & 0b0000_0001 != 0 {
                            diverted.insert(cid)
                        } else if !sticky {
                            diverted.remove(cid)
                        }
                    }
                    if hideVerify { hideAfterWrite = true }
                    return frame(Array(payload.prefix(6)))
                }
                return frame([])
            default:
                return nil
            }
        }
    }
}

@Suite("R2 DPI validation")
struct R2DPIValidationTests {

    private func makeClient(_ device: FakeMX) throws -> HIDPPClient {
        let transport = MockHIDPPTransport { request in device.reply(to: request) }
        return try HIDPPClient(transport: transport, deviceIndex: 0xFF, timeout: .milliseconds(300))
    }

    @Test("the old broken vector is refused and the value stays unknown")
    func oldBrokenVectorRefused() async throws {
        let device = FakeMX()
        // The bytes the old parser read as 51424 / 12831 / 16384 and 12.
        device.dpiList = [0x00, 0x00, 0xC8, 0xC0, 0x32, 0x1F, 0x40]
        device.dpiCurrent = [0x00, 0x00, 0x0C]
        let client = try makeClient(device)
        let state = try await client.readDPI()
        #expect(state.current == nil)
        #expect(state.note != nil)
    }

    @Test("a wrong sensor echo is refused")
    func wrongSensorEchoRefused() async throws {
        let device = FakeMX()
        device.dpiList = [0x01, 0x00, 0xC8, 0xE0, 0x32, 0x1F, 0x40]
        device.dpiCurrent = [0x01, 0x0C, 0x80]
        let client = try makeClient(device)
        let state = try await client.readDPI()
        #expect(state.current == nil)
        #expect(state.note != nil)
    }

    @Test("the real values are read and a value outside the list is unknown")
    func validValuesRead() async throws {
        let device = FakeMX()
        let client = try makeClient(device)
        let state = try await client.readDPI()
        #expect(state.current == 3200)
        #expect(state.available.first == 200)
        #expect(state.available.last == 8000)
        #expect(state.note == nil)
    }

    @Test("an oversized range endpoint cannot enter the supported DPI list")
    func oversizedRangeEndpointRefused() async throws {
        let device = FakeMX()
        // Sensor zero, start 200, step 50, end 50000 (0xC350).
        device.dpiList = [0x00, 0x00, 0xC8, 0xE0, 0x32, 0xC3, 0x50]
        let state = try await makeClient(device).readDPI()
        #expect(state.current == nil)
        #expect(state.available.isEmpty)
        #expect(state.note != nil)
    }
}

@Suite("R2 diversion ownership")
struct R2DiversionOwnershipTests {

    private func makeRemapper(
        _ device: FakeMX,
        store: DiversionStateStore
    ) async throws -> (MXButtonRemapper, MockHIDPPTransport) {
        let transport = MockHIDPPTransport { request in device.reply(to: request) }
        let client = try HIDPPClient(transport: transport, deviceIndex: 0xFF, timeout: .milliseconds(300))
        let reprogram = try #require(await ReprogramControlsClient.resolve(for: client))
        let remapper = MXButtonRemapper(
            client: client,
            reprogram: reprogram,
            store: store,
            deviceID: "r2-device",
            performer: RecordingPerformer(),
            accessibilityGranted: { true }
        )
        return (remapper, transport)
    }

    private func temporaryStore() -> (DiversionStateStore, URL) {
        let root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("utuvo-r2-\(UUID().uuidString)")
        return (DiversionStateStore(root: root), root)
    }

    private func writes(_ transport: MockHIDPPTransport) -> [UInt8] {
        transport.sentFrames.filter { $0[2] == 0x05 && ($0[3] >> 4) == 0x03 }.map { $0[6] }
    }

    @Test("a second enable is refused before anything is written")
    func secondEnableRefused() async throws {
        let device = FakeMX()
        let (store, root) = temporaryStore()
        defer { try? FileManager.default.removeItem(at: root) }
        let (remapper, transport) = try await makeRemapper(device, store: store)
        try await remapper.enable(mappings: [0x0053: .copy])
        let afterFirst = writes(transport)
        await #expect(throws: DiversionError.self) {
            try await remapper.enable(mappings: [0x0056: .paste])
        }
        // Nothing new was written and the first mapping is still owned.
        #expect(writes(transport) == afterFirst)
        #expect(remapper.ownedControls == [0x0053])
    }

    @Test("an unconfirmed rollback keeps the control owned so Disable retries it")
    func unconfirmedRollbackStaysOwned() async throws {
        let device = FakeMX()
        device.hideVerify = true
        device.sticky = true
        let (store, root) = temporaryStore()
        defer { try? FileManager.default.removeItem(at: root) }
        let (remapper, transport) = try await makeRemapper(device, store: store)
        await #expect(throws: DiversionError.self) {
            try await remapper.enable(mappings: [0x0053: .copy])
        }
        // The control is still owned and the lease is kept.
        #expect(remapper.ownedControls == [0x0053])
        #expect(store.load(deviceID: "r2-device") != nil)
        // A later Disable retries the control instead of reporting nothing owned.
        await #expect(throws: DiversionError.self) {
            _ = try await remapper.disable()
        }
        #expect(writes(transport).filter { $0 == 0x02 }.count >= 2)
    }

    @Test("a lease of an earlier run with an active diversion asks for a reconnect")
    func staleLeaseWithActiveDiversion() async throws {
        let device = FakeMX()
        device.diverted.insert(0x0053)
        let (store, root) = temporaryStore()
        defer { try? FileManager.default.removeItem(at: root) }
        try store.save(DiversionLease(
            deviceID: "r2-device",
            createdAt: Date(),
            originals: [0x0053: 0x00],
            actions: [0x0053: MappedAction.copy.rawValue]
        ))
        let (remapper, transport) = try await makeRemapper(device, store: store)
        await #expect(throws: DiversionError.self) {
            try await remapper.enable(mappings: [0x0056: .copy])
        }
        // Nothing was written and the lease of the other run is untouched.
        #expect(writes(transport).isEmpty)
        #expect(store.load(deviceID: "r2-device") != nil)
    }

    @Test("a lease whose controls are back in their native state is archived")
    func staleLeaseRecovered() async throws {
        let device = FakeMX()
        let (store, root) = temporaryStore()
        defer { try? FileManager.default.removeItem(at: root) }
        try store.save(DiversionLease(
            deviceID: "r2-device",
            createdAt: Date(),
            originals: [0x0053: 0x00],
            actions: [0x0053: MappedAction.copy.rawValue]
        ))
        let (remapper, transport) = try await makeRemapper(device, store: store)
        try await remapper.enable(mappings: [0x0056: .copy])
        // The old lease was archived and the new one describes the new mapping.
        let lease = try #require(store.load(deviceID: "r2-device"))
        #expect(lease.actions[0x0056] == MappedAction.copy.rawValue)
        #expect(lease.originals[0x0053] == nil)
        #expect(writes(transport).first == 0x03)
    }
}
