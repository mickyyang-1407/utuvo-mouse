import Foundation
import Testing
@testable import UTUVOMouseCore

/// Wire level fixtures. The byte strings are taken from the HID++ 2.0 wire format,
/// not from the encoder, so they check the parser against the specification.
@Suite("HID++ wire framing")
struct HIDPPWireTests {

    private func longFrame(_ bytes: [UInt8]) -> [UInt8] {
        var frame = bytes
        frame.append(contentsOf: repeatElement(0, count: max(0, 20 - frame.count)))
        return frame
    }

    @Test("a successful long reply carries its parameters from byte 4")
    func longSuccessFrame() throws {
        // [0x11, device 0xFF, root feature, function 0 | software 0x0A, index 0x05, flags 0x00, version 0x01]
        let frame = longFrame([0x11, 0xFF, 0x00, 0x0A, 0x05, 0x00, 0x01])
        #expect(frame.count == 20)
        let response = try HIDPPResponse.parse(frame)
        #expect(response.isSuccess)
        #expect(response.deviceIndex == 0xFF)
        #expect(response.featureIndex == 0x00)
        #expect(response.function == 0x00)
        #expect(response.softwareID == 0x0A)
        #expect(response.data.count == 16)
        #expect(response.data[0] == 0x05)  // feature index
        #expect(response.data[2] == 0x01)  // feature version
    }

    @Test("a successful short reply carries its parameters from byte 4")
    func shortSuccessFrame() throws {
        let frame: [UInt8] = [0x10, 0xFF, 0x03, 0x0A, 0x11, 0x22, 0x33]
        let response = try HIDPPResponse.parse(frame)
        #expect(response.isSuccess)
        #expect(response.featureIndex == 0x03)
        #expect(response.function == 0x00)
        #expect(response.softwareID == 0x0A)
        #expect(response.data == [0x11, 0x22, 0x33])
    }

    @Test("an error reply echoes the failed request and carries the reason")
    func errorReplyFrame() throws {
        // [0x11, device 0xFF, marker 0xFF, feature 0x0C, function 1 | software 0x0A, reason 0x02]
        let frame = longFrame([0x11, 0xFF, 0xFF, 0x0C, 0x1A, 0x02])
        let response = try HIDPPResponse.parse(frame)
        #expect(response.isErrorReply)
        #expect(response.featureIndex == 0x0C)
        #expect(response.function == 0x01)
        #expect(response.softwareID == 0x0A)
        #expect(response.reason == 0x02)
        #expect(response.data.isEmpty)
    }

    @Test("a HID++ 1.0 style error reply is parsed the same way")
    func hidpp1ErrorReplyFrame() throws {
        let frame = longFrame([0x11, 0xFF, 0x8F, 0x0C, 0x1A, 0x07])
        let response = try HIDPPResponse.parse(frame)
        #expect(response.isErrorReply)
        #expect(response.featureIndex == 0x0C)
        #expect(response.function == 0x01)
        #expect(response.softwareID == 0x0A)
        #expect(response.reason == 0x07)
    }

    @Test("frames that are not 7 or 20 bytes are rejected")
    func truncatedFramesRejected() {
        #expect(throws: HIDPPError.self) {
            try HIDPPResponse.parse([0x11, 0xFF, 0x00, 0x0A, 0x05])
        }
        #expect(throws: HIDPPError.self) {
            try HIDPPResponse.parse([0x10, 0xFF, 0x00, 0x0A])
        }
        #expect(throws: HIDPPError.self) {
            try HIDPPResponse.parse([0x12, 0xFF, 0x00, 0x0A, 0, 0, 0])
        }
    }

    @Test("outgoing requests need a 4 bit function and a software ID of 1...15")
    func requestValidation() throws {
        #expect(throws: HIDPPError.self) {
            try HIDPPRequest(featureIndex: 0, function: 0x10)
                .encoded(deviceIndex: 0xFF, softwareID: 0x0A, reportID: .long)
        }
        #expect(throws: HIDPPError.self) {
            try HIDPPRequest(featureIndex: 0, function: 0)
                .encoded(deviceIndex: 0xFF, softwareID: 0x00, reportID: .long)
        }
        let frame = try HIDPPRequest(featureIndex: 0x0C, function: 0x02, payload: [0x01])
            .encoded(deviceIndex: 0xFF, softwareID: 0x0A, reportID: .long)
        #expect(frame.count == 20)
        #expect(frame[0] == 0x11)
        #expect(frame[1] == 0xFF)
        #expect(frame[2] == 0x0C)
        #expect(frame[3] == 0x2A)
        #expect(frame[4] == 0x01)
    }
}
