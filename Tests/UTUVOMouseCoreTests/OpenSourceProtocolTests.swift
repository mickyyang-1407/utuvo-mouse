import Foundation
import Testing
import CoreGraphics
@testable import UTUVOMouseCore
import UTUVOMouseIO

/// Independent vectors: Nanostrike's actual format-8 readout, not our encoder.
@Suite("Verified open-source protocol regressions")
struct OpenSourceProtocolTests {
    @Test("14 08 0C means RT disabled with sensitivity 2")
    func actualBaseline() throws {
        let record = try #require(AnalogButtonRecord(decoding: [0x14, 0x08, 0x0C]))
        #expect(record.actuationPoint == 5)
        #expect(!record.rapidTriggerEnabled)
        #expect(record.rapidTriggerSensitivity == 2)
        #expect(record.hapticLevel == 3)
        let baseline = HitsButtonConfig(button: 0, record: record)
        let enabled = try HIDPPClient.HitsDraft(button: 0, rapidTrigger: 3).applying(to: baseline)
        #expect(try enabled.validatedRecord().encoded == [0x14, 0x0D, 0x0C])
        let disabled = try HIDPPClient.HitsDraft(button: 0, rapidTrigger: 0).applying(to: enabled)
        #expect(try disabled.validatedRecord().encoded == [0x14, 0x0C, 0x0C])
        let hapticOnly = try HIDPPClient.HitsDraft(button: 0, haptics: 4).applying(to: baseline)
        #expect(try hapticOnly.validatedRecord().encoded == [0x14, 0x08, 0x10])
    }

    @Test("a live haptic-only change preserves RT and disabling never sends zero sensitivity")
    func liveHITS() async throws {
        let firmware = HITSTestFirmware()
        let transport = MockHIDPPTransport { firmware.reply($0) }
        let client = try HIDPPClient(transport: transport, deviceIndex: 0xFF)
        try await client.applyHits(draft: .init(button: 0, haptics: 4), maxActuation: 10, maxRapidTrigger: 5, maxHaptics: 5)
        try await client.applyHits(draft: .init(button: 0, rapidTrigger: 3), maxActuation: 10, maxRapidTrigger: 5, maxHaptics: 5)
        try await client.applyHits(draft: .init(button: 0, rapidTrigger: 0), maxActuation: 10, maxRapidTrigger: 5, maxHaptics: 5)
        let written = transport.sentFrames.filter { $0[2] == 2 && $0[3] >> 4 == 1 }
        #expect(written.map { $0[6] } == [8, 13, 12])
        #expect(written.allSatisfy { $0[7] == 16 })
    }

    @Test("matching sensitivity with a rejected enable bit must fail verification")
    func ignoredEnableIsNotSuccess() async throws {
        let firmware = HITSTestFirmware(ignoreEnable: true)
        let transport = MockHIDPPTransport { firmware.reply($0) }
        let client = try HIDPPClient(transport: transport, deviceIndex: 0xFF)
        await #expect(throws: HIDPPError.self) {
            try await client.applyHits(draft: .init(button: 0, rapidTrigger: 3), maxActuation: 10, maxRapidTrigger: 5, maxHaptics: 5)
        }
    }

    @Test("legacy unknown-device 08 is unavailable, not HID++2 busy")
    func sleepingReceiverError() async throws {
        let transport = MockHIDPPTransport { req in [0x10, req[1], 0x8F, req[2], req[3], 0x08, 0] }
        let client = try HIDPPClient(transport: transport, deviceIndex: 1)
        await #expect(throws: HIDPPError.localized(key: "error.hidpp.receiverUnavailable", arguments: [])) {
            _ = try await client.request(featureIndex: 0, function: 1)
        }
    }

    @Test("asymmetric sensor reply is current-X/default-X/current-Y/default-Y")
    func sensorAxes() async throws {
        let transport = MockHIDPPTransport { req in
            let data: [UInt8] = req[2] == 0 ? [9,0,1] : [0,0x3E,0x80,0x1F,0x40,0x0B,0xB8,3,0x20,2]
            return [0x11,req[1],req[2],req[3]] + data + Array(repeating: 0, count: 16-data.count)
        }
        let client = try HIDPPClient(transport: transport, deviceIndex: 1)
        let actual = try await client.readSensorDPI()
        #expect(actual.x == 16000 && actual.y == 3000)
    }

    @Test("HITS equality depends on current fields, not decoded history")
    func configEquality() throws {
        let record = try #require(AnalogButtonRecord(decoding: [23,10,13]))
        let decoded = HitsButtonConfig(button: 0, record: record)
        #expect(decoded == .init(button: 0, actuation: 5, rapidTrigger: 2, haptics: 3))
        let changed = try HIDPPClient.HitsDraft(button: 0, haptics: 4).applying(to: decoded)
        #expect(changed == .init(button: 0, actuation: 5, rapidTrigger: 2, haptics: 4))
    }

    @Test("all 32 combinations of reserved bits survive a HITS edit")
    func reservedBits() throws {
        for bits in 0..<32 {
            let raw: [UInt8] = [0x14 | UInt8(bits & 3), 0x08 | UInt8((bits >> 2) & 1) << 1, 0x0C | UInt8((bits >> 3) & 3)]
            let record = try #require(AnalogButtonRecord(decoding: raw))
            let edited = try HIDPPClient.HitsDraft(button: 0, rapidTrigger: 3).applying(to: .init(button: 0, record: record)).validatedRecord().encoded
            #expect(edited == [raw[0], 0x0D | (raw[1] & 2), raw[2]])
        }
    }

    @Test("HITS only changes the chosen stored analog record and CRC")
    func persistentHITS() throws {
        var bytes = [UInt8](repeating: 0xFF, count: 255)
        bytes.replaceSubrange(38..<44, with: [0x17, 0x0A, 0x0D, 0x14, 0x08, 0x0C])
        let original = ProfileSector(bytes: bytes, sector: 1).withRecomputedCRC()
        let patched = try SuperstrikeService.patch(original, changes: .init(hits: [.init(button: 0, actuation: 6, rapidTrigger: 3, haptics: 4)]))
        #expect(patched.hasValidCRC)
        #expect(Array(patched.bytes[38..<41]) == [0x1B, 0x0F, 0x11])
        let changed = zip(original.bytes, patched.bytes).enumerated().filter { $0.element.0 != $0.element.1 }.map(\.offset)
        #expect(Set(changed).isSubset(of: [38, 39, 40, 253, 254]))
        #expect(Array(patched.bytes[41..<44]) == [0x14, 0x08, 0x0C])
    }

    @Test("DPI follows actual selected stage and preserves all other stages and LOD")
    func selectedDPI() throws {
        var bytes = [UInt8](repeating: 0xFF, count: 255)
        bytes[1] = 3  // Unidentified field: must never be used as the default.
        bytes[2] = 0
        bytes.replaceSubrange(4..<29, with: [0x20,3,0x20,3,2, 0xB0,4,0xB0,4,2, 0x40,6,0x40,6,2, 0x60,9,0x60,9,1, 0x80,12,0x80,12,2])
        let stored = ProfileSector(bytes: bytes, sector: 1)
        #expect(stored.dpiX == 800)
        for index in 0..<5 {
            let original = ProfileSector(bytes: bytes, sector: 1, activeDPIIndex: index).withRecomputedCRC()
            let patched = try SuperstrikeService.patch(original, changes: .init(dpiX: 6400, dpiY: 3200))
            let offset = 4 + index * 5
            let changed = zip(original.bytes, patched.bytes).enumerated().filter { $0.element.0 != $0.element.1 }.map(\.offset)
            #expect(Set(changed).isSubset(of: [2, offset, offset+1, offset+2, offset+3, 253, 254]))
            #expect(patched.bytes[1] == 3)
            #expect(patched.bytes[offset+4] == bytes[offset+4])
            #expect(patched.dpiX == 6400 && patched.dpiY == 3200)
        }
    }

    @Test("macOS copy/paste emit Command-C(8) and Command-V(9), never Z or 9")
    func actualKeyEvents() {
        let recorder = EventRecorder()
        let performer = SystemActionPerformer(eventSink: { recorder.add($0) })
        performer.perform(.copy); performer.perform(.paste); performer.perform(.native)
        let events = recorder.events
        #expect(events.map(\.key) == [8, 8, 9, 9])
        #expect(events.map(\.down) == [true, false, true, false])
        #expect(events.allSatisfy { $0.command })
    }
}

private final class EventRecorder: @unchecked Sendable {
    struct Event { var key: Int64; var down: Bool; var command: Bool }
    private let lock = NSLock()
    private var recorded: [Event] = []
    var events: [Event] { lock.withLock { recorded } }
    func add(_ event: CGEvent) {
        lock.withLock { recorded.append(.init(key: event.getIntegerValueField(.keyboardEventKeycode), down: event.type == .keyDown, command: event.flags.contains(.maskCommand))) }
    }
}

private final class HITSTestFirmware: @unchecked Sendable {
    private let lock = NSLock()
    private var record: [UInt8] = [20, 8, 12]
    private let ignoreEnable: Bool
    init(ignoreEnable: Bool = false) { self.ignoreEnable = ignoreEnable }
    func reply(_ req: [UInt8]) -> [UInt8]? {
        lock.withLock {
            var data: [UInt8] = []
            if req[2] == 0 { data = [2, 0, 1] }
            else if req[2] == 2 {
                switch req[3] >> 4 {
                case 1:
                    record = Array(req[5...7])
                    if ignoreEnable { record[1] &= 0xFE }
                case 2: data = [req[4]] + record
                default: return nil
                }
            } else { return nil }
            return [0x11,req[1],req[2],req[3]] + data + Array(repeating: 0, count: 16-data.count)
        }
    }
}
