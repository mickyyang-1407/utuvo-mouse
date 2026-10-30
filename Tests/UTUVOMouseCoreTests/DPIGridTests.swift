import Foundation
import Testing
@testable import UTUVOMouseCore

@Suite("Sensor-advertised DPI grid")
struct DPIGridTests {
    // Captured range words, also documented by Nanostrike. The terminator
    // crosses the 13-byte boundary between pages 2 and 3.
    private let words: [UInt16] = [100,0xE001,200,0xE002,500,0xE005,1000,0xE00A,2000,0xE014,5000,0xE032,10000,0xE064,20000,0xE07D,32000,0xE0C8,44000,0]

    private var stream: [UInt8] { words.flatMap { [UInt8($0 >> 8), UInt8($0 & 255)] } }

    @Test("actual sensor bands reject 3250 and accept 3260 or 3300")
    func actualBands() {
        let grid = DPIGrid(decodingRangeStream: stream)
        #expect(grid.ranges.count == 9)
        #expect(grid.contains(3200))
        #expect(!grid.contains(3250))
        #expect(grid.contains(3260))
        #expect(grid.contains(3300))
        #expect(grid.values.first == 100 && grid.values.last == 44000)
        #expect(grid.values.first { $0 > 3200 } == 3220)
        #expect(grid.values.last { $0 < 3200 } == 3180)
        #expect(grid.values == Array(Set(grid.values)).sorted())
    }

    @Test("odd-sized pages are concatenated before decoding range words")
    func splitWordsAndTerminator() async throws {
        let bytes = stream
        let transport = MockHIDPPTransport { req in
            var data: [UInt8]
            if req[2] == 0 { data = [9,0,1] }
            else {
                let page = Int(req[6]); let offset = page * 13
                let chunk = offset < bytes.count ? Array(bytes[offset..<min(offset+13,bytes.count)]) : []
                data = [0,req[5],req[6]] + chunk
            }
            data += Array(repeating: 0, count: max(0,16-data.count))
            return [0x11,req[1],req[2],req[3]] + data
        }
        let client = try HIDPPClient(transport: transport, deviceIndex: 0xFF)
        let grid = try await client.readDPIGrid(axis: 1)
        #expect(grid.ranges.count == 9)
        #expect(!grid.contains(3250) && grid.contains(3300))
        let reads = transport.sentFrames.filter { $0[2] == 9 && $0[3] >> 4 == 2 }
        #expect(reads.count == 4)
        #expect(reads.map { $0[6] } == [0,1,2,3])
    }

    @Test("a nonterminating range stream stops after eight pages")
    func boundedMalformedStream() async throws {
        let transport = MockHIDPPTransport { req in
            let data: [UInt8] = req[2] == 0 ? [9,0,1] + Array(repeating:0,count:13) : [0,req[5],req[6]] + Array(repeating: 0x11,count:13)
            return [0x11,req[1],req[2],req[3]] + data
        }
        let client = try HIDPPClient(transport: transport, deviceIndex: 0xFF)
        await #expect(throws: HIDPPError.self) { _ = try await client.readDPIGrid(axis: 0) }
        #expect(transport.sentFrames.filter { $0[2] == 9 && $0[3] >> 4 == 2 }.count == 8)
    }

    @Test("bad axis and unexpected page echoes are refused")
    func echoedPageGuard() async throws {
        let transport = MockHIDPPTransport { req in
            let data: [UInt8] = req[2] == 0 ? [9,0,1] + Array(repeating:0,count:13) : [0,req[5],req[6]+1] + Array(repeating:0,count:13)
            return [0x11,req[1],req[2],req[3]] + data
        }
        let client = try HIDPPClient(transport: transport, deviceIndex: 0xFF)
        await #expect(throws: HIDPPError.self) { _ = try await client.readDPIGrid(axis: 0) }
        let before = transport.sentFrames.count
        await #expect(throws: HIDPPError.self) { _ = try await client.readDPIGrid(axis: 2) }
        #expect(transport.sentFrames.count == before)
    }
}
