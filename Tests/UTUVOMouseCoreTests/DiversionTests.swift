import Foundation
import Testing
@testable import UTUVOMouseCore
@testable import UTUVOMouseIO

/// Records the actions instead of posting key events.
private final class SpyActionPerformer: ActionPerforming, @unchecked Sendable {
    private let lock = NSLock()
    private var recorded: [MappedAction] = []

    func perform(_ action: MappedAction) {
        lock.withLock { recorded.append(action) }
    }

    var actions: [MappedAction] { lock.withLock { recorded } }
}

/// A fake mouse that answers the 0x1B04 feature.
private final class FakeReprog: @unchecked Sendable {
    /// The write itself fails.
    enum Behavior: Sendable { case normal; case rejectWrite }

    let lock = NSLock()
    var behavior: Behavior = .normal
    /// The reporting read that follows a write hides the diversion bit.
    var hideVerify = false
    /// The control stays diverted even after a disable write.
    var sticky = false
    var diverted: Set<UInt16> = []
    var writeCount = 0
    var hideAfterWrite = false
    var missingControlIndex: Int?
    var onVerify: (@Sendable () -> Void)?
    var controls: [(cid: UInt16, flags: UInt16)] = [
        (0x0050, 0x0401),
        (0x0052, 0x0531),
        (0x0053, 0x0531),
        (0x0056, 0x0531),
    ]

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
                if function == 0x00 { return frame([0x05, 0x00, 0x01]) }
                return frame([0x04, 0x02])
            case 0x05:
                if function == 0x00 { return frame([UInt8(controls.count)]) }
                if function == 0x01 {
                    let index = Int(payload[0])
                    guard index < controls.count, index != missingControlIndex else { return nil }
                    let control = controls[index]
                    // byte 4 = low flags, byte 8 = high flags
                    return frame([
                        UInt8(control.cid >> 8), UInt8(control.cid & 0xFF),
                        0x00, 0x01,
                        UInt8(control.flags & 0xFF),
                        0x03, 0x01, 0x04,
                        UInt8(control.flags >> 8),
                    ])
                }
                if function == 0x02 {
                    let cid = (UInt16(payload[0]) << 8) | UInt16(payload[1])
                    if writeCount > 0 { onVerify?() }
                    var reported: UInt8 = diverted.contains(cid) ? 0b0000_0001 : 0
                    if hideAfterWrite {
                        hideAfterWrite = false
                        // Only the first verify is hidden, so the rollback is
                        // checked against the real state.
                        hideVerify = false
                        reported = 0
                    }
                    return frame([UInt8(cid >> 8), UInt8(cid & 0xFF), reported, 0x00, 0x00, 0x00])
                }
                if function == 0x03 {
                    writeCount += 1
                    if behavior == .rejectWrite {
                        return frame([0xFF, 0x00, 0x00, 0x00, 0x00, 0x00])
                    }
                    let cid = (UInt16(payload[0]) << 8) | UInt16(payload[1])
                    let change = payload[2]
                    if hideVerify { hideAfterWrite = true }
                    if change & 0b0000_0010 != 0 {
                        if change & 0b0000_0001 != 0 {
                            diverted.insert(cid)
                        } else if !sticky {
                            diverted.remove(cid)
                        }
                    }
                    return frame(Array(payload.prefix(6)))
                }
                return frame([])
            default:
                return nil
            }
        }
    }
}

@Suite("MX diversion lifecycle")
struct DiversionLifecycleTests {

    private func makeRemapper(
        _ device: FakeReprog,
        store: DiversionStateStore,
        accessibility: Bool = true
    ) async throws -> (MXButtonRemapper, MockHIDPPTransport) {
        let transport = MockHIDPPTransport { request in device.reply(to: request) }
        let client = try HIDPPClient(transport: transport, deviceIndex: 0xFF, timeout: .milliseconds(400))
        let reprogram = try #require(await ReprogramControlsClient.resolve(for: client))
        let remapper = MXButtonRemapper(
            client: client,
            reprogram: reprogram,
            store: store,
            deviceID: "test-device",
            performer: SpyActionPerformer(),
            accessibilityGranted: { accessibility }
        )
        return (remapper, transport)
    }

    private func temporaryStore() -> (DiversionStateStore, URL) {
        let root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("utuvo-diversion-tests-\(UUID().uuidString)")
        return (DiversionStateStore(root: root), root)
    }

    private func diversionWrites(_ transport: MockHIDPPTransport) -> [UInt8] {
        transport.sentFrames.filter { $0[2] == 0x05 && ($0[3] >> 4) == 0x03 }.map { $0[6] }
    }

    @Test("a failed control read refuses the entire list and sends no diversion")
    func partialControlsRefused() async throws {
        let device = FakeReprog()
        device.missingControlIndex = 2
        let (store, root) = temporaryStore()
        defer { try? FileManager.default.removeItem(at: root) }
        let (remapper, transport) = try await makeRemapper(device, store: store)
        await #expect(throws: HIDPPError.self) { _ = try await remapper.divertableControls() }
        #expect(diversionWrites(transport).isEmpty)
    }

    @Test("disconnect during enable cannot reactivate dispatch or restore through the old channel")
    func disconnectDuringEnable() async throws {
        let device = FakeReprog()
        let (store, root) = temporaryStore()
        defer { try? FileManager.default.removeItem(at: root) }
        let transport = MockHIDPPTransport { device.reply(to: $0) }
        let client = try HIDPPClient(transport: transport, deviceIndex: 0xFF, timeout: .milliseconds(400))
        let reprogram = try #require(await ReprogramControlsClient.resolve(for: client))
        let spy = SpyActionPerformer()
        let remapper = MXButtonRemapper(client: client, reprogram: reprogram, store: store,
            deviceID: "test-device", performer: spy, accessibilityGranted: { true })
        device.onVerify = { remapper.stopDispatch() }
        await #expect(throws: DiversionError.self) {
            try await remapper.enable(mappings: [0x0053: .copy])
        }
        remapper.handle(frame: [0x11, 0xFF, 0x05, 0x00, 0x00, 0x53, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0])
        #expect(spy.actions.isEmpty)
        #expect(diversionWrites(transport) == [0x03])
        #expect(store.load(deviceID: "test-device") != nil)
        await #expect(throws: DiversionError.self) {
            try await remapper.enable(mappings: [0x0056: .paste])
        }
        #expect(diversionWrites(transport) == [0x03])
    }

    @Test("a main button is refused before anything is written")
    func mainButtonRefused() async throws {
        let device = FakeReprog()
        let (store, root) = temporaryStore()
        defer { try? FileManager.default.removeItem(at: root) }
        let (remapper, transport) = try await makeRemapper(device, store: store)
        await #expect(throws: DiversionError.self) {
            try await remapper.enable(mappings: [0x0050: .copy])
        }
        #expect(diversionWrites(transport).isEmpty)
        #expect(device.writeCount == 0)
    }

    @Test("a control the device does not advertise is refused")
    func unknownControlRefused() async throws {
        let device = FakeReprog()
        let (store, root) = temporaryStore()
        defer { try? FileManager.default.removeItem(at: root) }
        let (remapper, transport) = try await makeRemapper(device, store: store)
        await #expect(throws: DiversionError.self) {
            try await remapper.enable(mappings: [0x0099: .copy])
        }
        #expect(diversionWrites(transport).isEmpty)
    }

    @Test("a control that is not advertised as divertable is refused")
    func notDivertableRefused() async throws {
        let device = FakeReprog()
        device.controls = [(0x0053, 0x0401)]  // no divertable bit
        let (store, root) = temporaryStore()
        defer { try? FileManager.default.removeItem(at: root) }
        let (remapper, transport) = try await makeRemapper(device, store: store)
        await #expect(throws: DiversionError.self) {
            try await remapper.enable(mappings: [0x0053: .copy])
        }
        #expect(diversionWrites(transport).isEmpty)
    }

    @Test("a failed verify puts the attempted control back")
    func failedVerifyRollsBack() async throws {
        let device = FakeReprog()
        device.hideVerify = true
        let (store, root) = temporaryStore()
        defer { try? FileManager.default.removeItem(at: root) }
        let (remapper, transport) = try await makeRemapper(device, store: store)
        await #expect(throws: DiversionError.self) {
            try await remapper.enable(mappings: [0x0053: .copy])
        }
        // The enable (03) and the rollback (02) for the same control.
        #expect(diversionWrites(transport) == [0x03, 0x02])
        #expect(device.diverted.isEmpty)
        #expect(store.load(deviceID: "test-device") == nil)
        #expect(remapper.ownedControls.isEmpty)
        #expect(try await remapper.disable() == .nothingOwned)
        #expect(diversionWrites(transport) == [0x03, 0x02])
    }

    @Test("an unconfirmed rollback keeps the lease as evidence")
    func unconfirmedRollbackKeepsLease() async throws {
        let device = FakeReprog()
        device.hideVerify = true
        let (store, root) = temporaryStore()
        defer { try? FileManager.default.removeItem(at: root) }
        let (remapper, _) = try await makeRemapper(device, store: store)
        device.sticky = true
        await #expect(throws: DiversionError.self) {
            try await remapper.enable(mappings: [0x0053: .copy])
        }
        // The lease is kept so the state can be inspected and recovered.
        #expect(store.load(deviceID: "test-device") != nil)
    }

    @Test("disabling puts the control back and only then clears the lease")
    func disableRestoresAndClears() async throws {
        let device = FakeReprog()
        let (store, root) = temporaryStore()
        defer { try? FileManager.default.removeItem(at: root) }
        let (remapper, transport) = try await makeRemapper(device, store: store)
        try await remapper.enable(mappings: [0x0053: .copy])
        #expect(device.diverted.contains(0x0053))
        #expect(store.load(deviceID: "test-device") != nil)

        let result = try await remapper.disable()
        #expect(result == .restored([0x0053]))
        #expect(device.diverted.isEmpty)
        #expect(store.load(deviceID: "test-device") == nil)
        #expect(diversionWrites(transport).contains(0x02))
    }

    @Test("a failed restore keeps the lease")
    func failedRestoreKeepsLease() async throws {
        let device = FakeReprog()
        let (store, root) = temporaryStore()
        defer { try? FileManager.default.removeItem(at: root) }
        let (remapper, _) = try await makeRemapper(device, store: store)
        try await remapper.enable(mappings: [0x0053: .copy])
        device.sticky = true
        await #expect(throws: DiversionError.self) {
            _ = try await remapper.disable()
        }
        #expect(store.load(deviceID: "test-device") != nil)
    }

    @Test("a lease of an earlier run is left alone")
    func staleLeaseIsLeftAlone() async throws {
        let device = FakeReprog()
        let (store, root) = temporaryStore()
        defer { try? FileManager.default.removeItem(at: root) }
        let (remapper, transport) = try await makeRemapper(device, store: store)
        // A lease from a previous run of the app.
        try store.save(DiversionLease(
            deviceID: "test-device",
            createdAt: Date(),
            originals: [0x0053: 0x00],
            actions: [0x0053: MappedAction.copy.rawValue]
        ))
        let result = try await remapper.disable()
        #expect(result == .nothingOwned)
        // Nothing was written to the device.
        #expect(diversionWrites(transport).isEmpty)
        #expect(store.load(deviceID: "test-device") != nil)
    }
}

@Suite("MX notification dispatch")
struct DiversionDispatchTests {

    private func notification(
        feature: UInt8,
        function: UInt8 = 0,
        softwareID: UInt8 = 0,
        deviceIndex: UInt8 = 0xFF,
        payload: [UInt8]
    ) -> [UInt8] {
        var bytes: [UInt8] = [0x11, deviceIndex, feature, (function << 4) | softwareID]
        bytes.append(contentsOf: payload)
        bytes.append(contentsOf: repeatElement(0, count: max(0, 16 - payload.count)))
        return bytes
    }

    @Test("a rising edge performs the action once, repeats do nothing")
    func risingEdgeOnly() async throws {
        let device = FakeReprog()
        let transport = MockHIDPPTransport { request in device.reply(to: request) }
        let client = try HIDPPClient(transport: transport, deviceIndex: 0xFF, timeout: .milliseconds(400))
        let reprogram = try #require(await ReprogramControlsClient.resolve(for: client))
        let root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("utuvo-dispatch-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let spy = SpyActionPerformer()
        let remapper = MXButtonRemapper(
            client: client,
            reprogram: reprogram,
            store: DiversionStateStore(root: root),
            deviceID: "test-device",
            performer: spy,
            accessibilityGranted: { true }
        )
        try await remapper.enable(mappings: [0x0053: .copy])

        // The button goes down.
        remapper.handle(frame: notification(feature: 0x05, payload: [0x00, 0x53, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00]))
        #expect(spy.actions == [.copy])
        // The same frame again is a repeat and does nothing.
        remapper.handle(frame: notification(feature: 0x05, payload: [0x00, 0x53, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00]))
        #expect(spy.actions == [.copy])
        // The button goes up: a release does not post another command.
        remapper.handle(frame: notification(feature: 0x05, payload: [0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00]))
        #expect(spy.actions == [.copy])
        let writesBeforeDisconnect = device.writeCount
        remapper.stopDispatch()
        remapper.handle(frame: notification(feature: 0x05, payload: [0x00, 0x53, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00]))
        #expect(spy.actions == [.copy])
        #expect(device.writeCount == writesBeforeDisconnect)
        #expect(DiversionStateStore(root: root).load(deviceID: "test-device") != nil)
    }

    @Test("frames of another device, feature or function are ignored")
    func foreignFramesIgnored() async throws {
        let device = FakeReprog()
        let transport = MockHIDPPTransport { request in device.reply(to: request) }
        let client = try HIDPPClient(transport: transport, deviceIndex: 0xFF, timeout: .milliseconds(400))
        let reprogram = try #require(await ReprogramControlsClient.resolve(for: client))
        let root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("utuvo-dispatch-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let spy = SpyActionPerformer()
        let remapper = MXButtonRemapper(
            client: client,
            reprogram: reprogram,
            store: DiversionStateStore(root: root),
            deviceID: "test-device",
            performer: spy,
            accessibilityGranted: { true }
        )
        try await remapper.enable(mappings: [0x0053: .copy])
        let payload: [UInt8] = [0x00, 0x53, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00]
        // Another feature index.
        remapper.handle(frame: notification(feature: 0x06, payload: payload))
        // Another function.
        remapper.handle(frame: notification(feature: 0x05, function: 1, payload: payload))
        // Another device index.
        remapper.handle(frame: notification(feature: 0x05, deviceIndex: 0x01, payload: payload))
        // A software ID that is not zero is a reply, not a notification.
        remapper.handle(frame: notification(feature: 0x05, softwareID: 0x0A, payload: payload))
        #expect(spy.actions.isEmpty)
    }

    @Test("a control without an action does nothing")
    func unmappedControlDoesNothing() async throws {
        let device = FakeReprog()
        let transport = MockHIDPPTransport { request in device.reply(to: request) }
        let client = try HIDPPClient(transport: transport, deviceIndex: 0xFF, timeout: .milliseconds(400))
        let reprogram = try #require(await ReprogramControlsClient.resolve(for: client))
        let root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("utuvo-dispatch-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let spy = SpyActionPerformer()
        let remapper = MXButtonRemapper(
            client: client,
            reprogram: reprogram,
            store: DiversionStateStore(root: root),
            deviceID: "test-device",
            performer: spy,
            accessibilityGranted: { true }
        )
        try await remapper.enable(mappings: [0x0053: .copy])
        // 0x0056 was not mapped.
        remapper.handle(frame: notification(feature: 0x05, payload: [0x00, 0x56, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00]))
        #expect(spy.actions.isEmpty)
    }
}
