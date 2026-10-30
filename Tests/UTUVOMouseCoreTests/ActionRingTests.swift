import Foundation
import Testing
@testable import UTUVOMouseSupport

@Suite("Action Ring configuration and selection")
struct ActionRingTests {
    @Test("eight directions are clockwise from top, including the angle seam")
    func directions() {
        let points: [(Double, Double)] = [(0,-100),(70,-70),(100,0),(70,70),(0,100),(-70,70),(-100,0),(-70,-70)]
        for (index, point) in points.enumerated() {
            #expect(ActionRingGeometry.slot(x: point.0, y: point.1) == index)
        }
        #expect(ActionRingGeometry.slot(x: -0.001, y: -100) == 0)
        #expect(ActionRingGeometry.slot(x: 0.001, y: -100) == 0)
    }

    @Test("center, far outside, and nonfinite pointer values never choose an action")
    func cancelRegions() {
        #expect(ActionRingGeometry.slot(x: 0, y: 0) == nil)
        #expect(ActionRingGeometry.slot(x: 29, y: 0) == nil)
        #expect(ActionRingGeometry.slot(x: 200, y: 0) == nil)
        #expect(ActionRingGeometry.slot(x: .nan, y: 80) == nil)
        #expect(ActionRingGeometry.slot(x: 80, y: .infinity) == nil)
    }

    @Test("configuration rejects incompatible versions and malformed slot counts")
    func configuration() throws {
        let config = ActionRingConfiguration()
        #expect(try ActionRingConfiguration.decode(JSONEncoder().encode(config)) == config)
        let tooShort = ActionRingConfiguration(slots: [.copy])
        #expect(throws: (any Error).self) { try ActionRingConfiguration.decode(JSONEncoder().encode(tooShort)) }
        var future = config; future.version = 2
        #expect(throws: (any Error).self) { try ActionRingConfiguration.decode(JSONEncoder().encode(future)) }
        #expect(throws: (any Error).self) { try ActionRingConfiguration.decode(Data("{}".utf8)) }
    }

    @Test("the ring can only be restored on the physical haptic control")
    func mappingValidation() throws {
        let id = "sha256:1234567890abcdef"
        let valid = MXSavedMapping(deviceID: id, choices: [0x01A0: .actionsRing, 0x0053: .copy], enabledIntent: true)
        try MXMappingPreferenceDocument(mappingsByDeviceID: [id: valid]).validate()
        for choices: [UInt16: MXMappingAction] in [[0x0052: .actionsRing], [0x01A0: .paste]] {
            let invalid = MXSavedMapping(deviceID: id, choices: choices, enabledIntent: true)
            #expect(throws: MXMappingPreferenceError.self) {
                try MXMappingPreferenceDocument(mappingsByDeviceID: [id: invalid]).validate()
            }
        }
    }
}
