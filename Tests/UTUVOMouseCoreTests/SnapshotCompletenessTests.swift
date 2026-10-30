import Testing
@testable import UTUVOMouseCore

@Suite("Authoritative device state")
struct SnapshotCompletenessTests {
    private func superstrike() -> DeviceSnapshot {
        let identity = DeviceIdentity(
            stableID: "synthetic", model: .superstrike, vendorID: 0x046D,
            productID: 0xC0A8, transport: .usb, deviceIndex: 0xFF,
            productName: "Synthetic Superstrike"
        )
        var snapshot = DeviceSnapshot(identity: identity, features: [0x8100: 4])
        snapshot.protocolVersion = "4.2"
        let info = OnboardInfo(
            memoryModel: 1, profileFormat: 8, macroEnabled: 1, profileCount: 5,
            outOfBounds: 1, buttonCount: 5, sectorCount: 16, sectorSize: 255,
            shift: 10, raw: []
        )
        let control = ProfileSector(bytes: .init(repeating: 0, count: 255), sector: 0).withRecomputedCRC()
        snapshot.plan = SuperstrikePlan(
            info: info, mode: 1, runningSector: 1, storedSector: 1,
            isRunning: true, enabledSectors: [1], controlBytes: control.bytes, activeDPIIndex: 1
        )
        var profileBytes = control.bytes
        profileBytes[0] = 3
        profileBytes[2] = 1
        profileBytes[9] = 0x80; profileBytes[10] = 0x0C
        profileBytes[11] = 0x80; profileBytes[12] = 0x0C
        snapshot.profile = ProfileSector(bytes: profileBytes, sector: 1).withRecomputedCRC()
        return snapshot
    }

    @Test("only a complete valid profile read can resolve flash uncertainty")
    func profileReadMustBeComplete() {
        let valid = superstrike()
        #expect(valid.hasCompleteState)
        var missingPlan = valid
        missingPlan.plan = nil
        #expect(!missingPlan.hasCompleteState)
        var missingSector = valid
        missingSector.profile = nil
        #expect(!missingSector.hasCompleteState)
        var badCRC = valid
        badCRC.profile!.bytes[20] ^= 0x01
        #expect(!badCRC.hasCompleteState)
        var wrongSector = valid
        wrongSector.profile!.sector = 2
        #expect(!wrongSector.hasCompleteState)
        var badControlCRC = valid
        badControlCRC.plan!.controlBytes[20] ^= 0x01
        #expect(!badControlCRC.hasCompleteState)
        var badDPI = valid
        badDPI.profile!.bytes[9] = 0; badDPI.profile!.bytes[10] = 0
        badDPI.profile = badDPI.profile!.withRecomputedCRC()
        #expect(!badDPI.hasCompleteState)
        var badRate = valid
        badRate.profile!.bytes[0] = 255
        badRate.profile = badRate.profile!.withRecomputedCRC()
        #expect(!badRate.hasCompleteState)
    }

    @Test("a ping alone or one missing analog button remains a partial read")
    func partialAnalogReadIsNotAuthoritative() {
        var snapshot = superstrike()
        snapshot.features[0x1B0C] = 3
        snapshot.hitsCapabilities = .init(buttonCount: 2, maxActuation: 10, maxRapidTrigger: 5, maxHaptics: 5)
        #expect(!snapshot.hasCompleteState)
        snapshot.hitsButtons = [.init(button: 0, actuation: 5, rapidTrigger: 2, haptics: 3)]
        #expect(!snapshot.hasCompleteState)
        snapshot.hitsButtons.append(.init(button: 1, actuation: 5, rapidTrigger: 2, haptics: 3))
        #expect(snapshot.hasCompleteState)
        snapshot.protocolVersion = nil
        #expect(!snapshot.hasCompleteState)
    }
}
