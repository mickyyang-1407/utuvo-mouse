import Foundation
import Testing
@testable import UTUVOMouseCore
@testable import UTUVOMouseIO

/// One transaction at a time per transport, and a late answer never belongs to a
/// newer transaction.
@Suite("HID++ transactions")
struct HIDPPTransactionTests {

    private func reply(for frame: [UInt8], value: UInt8) -> [UInt8] {
        var bytes: [UInt8] = [0x11, frame[1], frame[2], frame[3], value]
        bytes.append(contentsOf: repeatElement(0, count: 15))
        return bytes
    }

    /// Waits until the transport has sent at least `count` frames.
    ///
    /// A bounded wait for the condition, not a fixed delay: the test only moves
    /// on when the frame it expects is really on the wire.
    private func waitForSentFrames(
        _ transport: MockHIDPPTransport,
        count: Int,
        timeout: Duration = .milliseconds(1000)
    ) async -> Bool {
        let clock = ContinuousClock()
        let deadline = clock.now + timeout
        while clock.now < deadline {
            if transport.sentFrames.count >= count { return true }
            await Task.yield()
            try? await Task.sleep(for: .milliseconds(2))
        }
        return transport.sentFrames.count >= count
    }

    @Test("a second request waits until the first one is answered")
    func requestsAreSerialised() async throws {
        let transport = MockHIDPPTransport { _ in nil }
        let client = try HIDPPClient(transport: transport, deviceIndex: 0xFF, timeout: .milliseconds(2000))
        // The first request is the only one that exists at this point, so the
        // first frame on the wire belongs to it.
        async let first: [UInt8] = client.request(featureIndex: 0x05, function: 0x01)
        #expect(await waitForSentFrames(transport, count: 1))
        let firstFrame = transport.sentFrames[0]

        // Only now the second request starts. It has to wait for the gate.
        async let second: [UInt8] = client.request(featureIndex: 0x05, function: 0x01)
        let sentTooEarly = await waitForSentFrames(transport, count: 2, timeout: .milliseconds(250))
        #expect(sentTooEarly == false)
        #expect(transport.sentFrames.count == 1)

        transport.deliver(reply(for: firstFrame, value: 0x42))
        let firstValue = try await first
        #expect(firstValue.first == 0x42)

        // With the first transaction finished, the second one goes out.
        #expect(await waitForSentFrames(transport, count: 2))
        let secondFrame = transport.sentFrames[1]
        transport.deliver(reply(for: secondFrame, value: 0x43))
        let secondValue = try await second
        #expect(secondValue.first == 0x43)
    }

    @Test("every transaction carries its own software ID")
    func softwareIDsRotate() async throws {
        let transport = MockHIDPPTransport { _ in nil }
        let client = try HIDPPClient(transport: transport, deviceIndex: 0xFF, timeout: .milliseconds(2000))
        async let first: [UInt8] = client.request(featureIndex: 0x05, function: 0x01)
        #expect(await waitForSentFrames(transport, count: 1))
        let firstFrame = transport.sentFrames[0]
        let firstID = firstFrame[3] & 0x0F
        transport.deliver(reply(for: firstFrame, value: 0x01))
        _ = try await first

        async let second: [UInt8] = client.request(featureIndex: 0x05, function: 0x01)
        #expect(await waitForSentFrames(transport, count: 2))
        let secondFrame = transport.sentFrames[1]
        let secondID = secondFrame[3] & 0x0F
        #expect(firstID != secondID)
        #expect(firstID >= 1 && firstID <= 15)
        #expect(secondID >= 1 && secondID <= 15)
        transport.deliver(reply(for: secondFrame, value: 0x02))
        _ = try await second
    }

    @Test("a late answer of an older transaction does not finish the newer one")
    func lateOldReplyIsIgnored() async throws {
        let transport = MockHIDPPTransport { _ in nil }
        let client = try HIDPPClient(transport: transport, deviceIndex: 0xFF, timeout: .milliseconds(2000))
        async let first: [UInt8] = client.request(featureIndex: 0x05, function: 0x01)
        #expect(await waitForSentFrames(transport, count: 1))
        let oldFrame = transport.sentFrames[0]
        transport.deliver(reply(for: oldFrame, value: 0x11))
        _ = try await first

        async let second: [UInt8] = client.request(featureIndex: 0x05, function: 0x01)
        #expect(await waitForSentFrames(transport, count: 2))
        let newFrame = transport.sentFrames[1]
        #expect(newFrame[3] & 0x0F != oldFrame[3] & 0x0F)
        // The late answer of the first transaction arrives now.
        transport.deliver(reply(for: oldFrame, value: 0x99))
        await Task.yield()
        // The second transaction is still waiting for its own answer.
        transport.deliver(reply(for: newFrame, value: 0x22))
        let value = try await second
        #expect(value.first == 0x22)
    }
}

/// The compound patch of the onboard profile.
@Suite("Compound profile patch")
struct CompoundPatchTests {

    @Test("only the requested bytes change")
    func onlyRequestedBytesChange() throws {
        var bytes = [UInt8](repeating: 0x22, count: 255)
        bytes[0] = 3
        bytes[2] = 1
        bytes[9] = 0x80; bytes[10] = 0x0C
        bytes[11] = 0x80; bytes[12] = 0x0C
        let sector = ProfileSector(bytes: bytes, sector: 1).withRecomputedCRC()
        let patched = try SuperstrikeService.patch(
            sector,
            changes: CompoundChanges(
                dpiX: 1600,
                dpiY: 1600,
                reportRateHz: 2000,
                buttons: [ButtonChange(slot: 3, action: ButtonAction(kind: .mouse, code: 0x0010))]
            )
        )
        let changed = zip(sector.bytes, patched.bytes).enumerated()
            .filter { $0.element.0 != $0.element.1 }
            .map { $0.offset }
        // report rate, the two DPI words, one button slot and the CRC.
        #expect(Set(changed).isSubset(of: [0, 9, 10, 11, 12, 60, 61, 62, 63, 253, 254]))
        #expect(changed.contains(0))
        #expect(changed.contains(9))
        #expect(changed.contains(60))
        #expect(patched.dpiX == 1600)
        #expect(patched.reportRateHz == 2000)
        #expect(patched.hasValidCRC)
    }

    @Test("a profile slot outside 1...count is refused")
    func invalidSectorRefused() {
        #expect(SuperstrikeService.isValidProfileSector(0, count: 5) == false)
        #expect(SuperstrikeService.isValidProfileSector(0x0100, count: 5) == false)
        #expect(SuperstrikeService.isValidProfileSector(6, count: 5) == false)
        #expect(SuperstrikeService.isValidProfileSector(1, count: 5) == true)
        #expect(SuperstrikeService.isValidProfileSector(5, count: 5) == true)
    }
}

/// The 1B04 wire facts and the scoped diversion.
@Suite("MX button protocol")
struct MXButtonProtocolTests {

    private func makeTransport(reporting: UInt8 = 0x00) -> MockHIDPPTransport {
        MockHIDPPTransport { request in
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
                if function == 0x00 { return frame([0x02]) }
                if function == 0x01 {
                    // CID 0x0053, task 1, flags: mouse + divertable + persistently divertable
                    return frame([0x00, 0x53, 0x00, 0x01, 0x61, 0x03, 0x01, 0x04, 0x00])
                }
                if function == 0x02 {
                    let cid = (UInt16(payload[0]) << 8) | UInt16(payload[1])
                    return frame([UInt8(cid >> 8), UInt8(cid & 0xFF), reporting, 0x00, 0x00, 0x00])
                }
                if function == 0x03 {
                    return frame(Array(payload.prefix(6)))
                }
                return frame([])
            default:
                return nil
            }
        }
    }

    @Test("the reporting flags keep the temporary bit at 0 and the persistent bit at 2")
    func reportingBits() async throws {
        let transport = makeTransport(reporting: 0b0000_0101)
        let client = try HIDPPClient(transport: transport, deviceIndex: 0xFF, timeout: .milliseconds(300))
        let reprogram = try #require(await ReprogramControlsClient.resolve(for: client))
        let reporting = try await reprogram.readReporting(cid: 0x0053)
        #expect(reporting.isTemporarilyDiverted)
        #expect(reporting.isPersistentlyDiverted)
    }

    @Test("the control info uses the documented byte layout")
    func controlInfoLayout() async throws {
        let transport = makeTransport()
        let client = try HIDPPClient(transport: transport, deviceIndex: 0xFF, timeout: .milliseconds(300))
        let reprogram = try #require(await ReprogramControlsClient.resolve(for: client))
        let control = try await reprogram.readControlInfo(index: 0)
        #expect(control.cid == 0x0053)
        #expect(control.taskID == 0x0001)
        #expect(control.flags == 0x0061)
        #expect(control.position == 0x03)
        #expect(control.group == 0x01)
        #expect(control.groupMask == 0x04)
        #expect(control.isMouse)
        #expect(control.isDivertable)
    }

    @Test("enabling writes 03 and disabling writes 02, the rest stays zero")
    func changeBytes() async throws {
        let transport = makeTransport()
        let client = try HIDPPClient(transport: transport, deviceIndex: 0xFF, timeout: .milliseconds(300))
        let reprogram = try #require(await ReprogramControlsClient.resolve(for: client))
        try await reprogram.writeTemporaryDiversion(cid: 0x0053, change: .enable)
        var frame = transport.sentFrames.last!
        #expect(frame[4] == 0x00)
        #expect(frame[5] == 0x53)
        #expect(frame[6] == 0x03)
        #expect(frame[7] == 0x00)
        #expect(frame[8] == 0x00)
        #expect(frame[9] == 0x00)
        #expect(frame.dropFirst(10).allSatisfy { $0 == 0 })

        try await reprogram.writeTemporaryDiversion(cid: 0x0053, change: .disable)
        frame = transport.sentFrames.last!
        #expect(frame[6] == 0x02)
        #expect(frame.dropFirst(10).allSatisfy { $0 == 0 })
    }

    @Test("a notification only uses the first eight bytes and ignores zero IDs")
    func notificationParsing() {
        var payload: [UInt8] = [0x00, 0x53, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00]
        #expect(ReprogramControlsClient.pressedControls(in: payload) == [0x0053])
        payload = [0x00, 0x00, 0x00, 0x56, 0x00, 0x00, 0x00, 0x00]
        #expect(ReprogramControlsClient.pressedControls(in: payload) == [0x0056])
        // Everything after the first eight bytes is ignored.
        payload = [0x00, 0x53, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x56]
        #expect(ReprogramControlsClient.pressedControls(in: payload) == [0x0053])
    }

    @Test("without the accessibility permission nothing is written")
    func noAccessibilityNoWrites() async throws {
        let transport = makeTransport()
        let client = try HIDPPClient(transport: transport, deviceIndex: 0xFF, timeout: .milliseconds(300))
        let reprogram = try #require(await ReprogramControlsClient.resolve(for: client))
        let root = MouseTestTemporaryRoot.url
            .appendingPathComponent("utuvo-diversion-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let remapper = MXButtonRemapper(
            client: client,
            reprogram: reprogram,
            store: DiversionStateStore(root: root),
            deviceID: "test",
            accessibilityGranted: { false }
        )
        await #expect(throws: DiversionError.self) {
            try await remapper.enable(mappings: [0x0053: .copy])
        }
        #expect(!transport.sentFrames.contains { $0[2] == 0x05 && ($0[3] >> 4) == 0x03 })
    }

    @Test("an already diverted control is not taken over")
    func ownershipConflict() async throws {
        let transport = makeTransport(reporting: 0b0000_0001)
        let client = try HIDPPClient(transport: transport, deviceIndex: 0xFF, timeout: .milliseconds(300))
        let reprogram = try #require(await ReprogramControlsClient.resolve(for: client))
        let root = MouseTestTemporaryRoot.url
            .appendingPathComponent("utuvo-diversion-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let remapper = MXButtonRemapper(
            client: client,
            reprogram: reprogram,
            store: DiversionStateStore(root: root),
            deviceID: "test",
            accessibilityGranted: { true }
        )
        await #expect(throws: DiversionError.self) {
            try await remapper.enable(mappings: [0x0053: .copy])
        }
        #expect(!transport.sentFrames.contains { $0[2] == 0x05 && ($0[3] >> 4) == 0x03 })
    }
}
