import Foundation
import Testing
@testable import UTUVOMouseCore

@Suite("Mouse identification")
struct MouseIdentificationTests {
    @Test("Direct model IDs stay exact, including other vendors and unknown Logitech products")
    func directModels() {
        #expect(MouseIdentification.model(vendorID: 0x046D, productID: 0xB042) == .mxMaster4)
        #expect(MouseIdentification.model(vendorID: 0x046D, productID: 0xC0A8) == .superstrike)
        #expect(MouseIdentification.model(vendorID: 0x1234, productID: 0xB042) == .unknown)
        #expect(MouseIdentification.model(vendorID: 0x046D, productID: 0xB034, pairedDeviceName: "PRO X2 SUPERSTRIKE") == .unknown)
    }

    @Test("A receiver needs an exact paired name; another gaming mouse is not SUPERSTRIKE")
    func receivers() {
        #expect(MouseIdentification.model(vendorID: 0x046D, productID: 0xC54D) == .receiver)
        #expect(MouseIdentification.model(vendorID: 0x046D, productID: 0xC54D, pairedDeviceName: "PRO X2 SUPERSTRIKE") == .superstrike)
        #expect(MouseIdentification.model(vendorID: 0x046D, productID: 0xC54D, pairedDeviceName: "PRO X SUPERLIGHT 2") == .unknown)
        #expect(MouseIdentification.model(vendorID: 0x046D, productID: 0xC54D, pairedDeviceName: "PRO X2 SUPERSTRIKE TEST") == .unknown)
        #expect(MouseIdentification.model(vendorID: 0x046D, productID: 0xC54D, pairedDeviceName: "PRO X2 SUPERSTRIKE\0") == .receiver)
    }

    @Test("A mouse with common onboard/DPI features remains unknown without a verified model ID")
    func sharedFeaturesNeverGrantControls() {
        let identity = DeviceIdentity(stableID: "fixture", model: MouseIdentification.model(vendorID: 0x046D, productID: 0xFFFF),
            vendorID: 0x046D, productID: 0xFFFF, transport: .usb, deviceIndex: 0xFF, productName: "G703")
        let state = DeviceSnapshot(identity: identity, features: [HIDPPFeatureID.onboardProfiles: 1, HIDPPFeatureID.adjustableDPI: 2])
        #expect(!state.identity.model.supportsConfiguration)
        #expect(!state.hasCompleteState)
        #expect(state.identity.displayName(language: .english) == "G703")
        #expect(state.identity.displayName(language: .traditionalChinese) == "G703")
    }

    @Test("A multi-frame UTF-8 device name is assembled at byte offsets using only getters")
    func nameFragments() async throws {
        let name = "PRO X2 SUPERSTRIKE"
        let utf8 = Array(name.utf8)
        let transport = MockHIDPPTransport { request in
            let data: [UInt8]
            if request[3] >> 4 == 0 { data = [UInt8(utf8.count)] }
            else { data = Array(utf8.dropFirst(Int(request[4])).prefix(16)) }
            return [0x11, request[1], request[2], request[3]] + data + Array(repeating: 0, count: 16 - data.count)
        }
        let client = try HIDPPClient(transport: transport, deviceIndex: 1)
        #expect(try await client.readDeviceName(featureIndex: 5) == name)
        #expect(transport.sentFrames.map { $0[3] >> 4 } == [0, 1, 1])
        #expect(transport.sentFrames.dropFirst().map { $0[4] } == [0, 16])
        #expect(transport.sentFrames.allSatisfy { $0[1] == 1 && $0[2] == 5 })
    }

    @Test("Oversized or malformed names fail closed, with a bounded number of reads")
    func invalidNames() async throws {
        let huge = MockHIDPPTransport { r in [0x11,r[1],r[2],r[3],129] + Array(repeating: 0,count:15) }
        let client = try HIDPPClient(transport: huge, deviceIndex: 1)
        #expect(try await client.readDeviceName(featureIndex: 5) == nil)
        #expect(huge.sentFrames.count == 1)
        let invalid = MockHIDPPTransport { r in
            [0x11,r[1],r[2],r[3],r[3] >> 4 == 0 ? 1 : 0xFF] + Array(repeating: 0,count:15)
        }
        #expect(try await HIDPPClient(transport: invalid,deviceIndex:1).readDeviceName(featureIndex:5) == nil)
        #expect(invalid.sentFrames.count == 2)
    }
}
