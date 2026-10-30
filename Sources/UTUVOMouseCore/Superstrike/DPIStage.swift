// Adapted from jwake/nanostrike (MIT). See LICENSES/Nanostrike-MIT.txt.
/// One DPI stage as stored in an onboard profile: five bytes.
///
/// > Important: the sector stores DPI **little-endian**. The HID++ wire
/// > protocol (`0x2202`) uses **big-endian** for the same values. Do not reuse
/// > this codec for wire data. See `docs/09-verified-device-readout.md`.
public struct DPIStage: Hashable, Sendable {
    public static let byteCount = 5

    public var x: UInt16
    public var y: UInt16
    /// Lift-off distance, as one of three named levels. See `LiftOff`.
    public var liftOff: UInt8

    /// The lift-off levels G Hub offers, which is the only place their meaning
    /// is written down: the device exposes no range for this field.
    /// `getSensorLodList` reports the value stored per stage, not what the
    /// sensor will accept. Confirmed by setting a deliberate mixture in G Hub
    /// and reading the sector back. See `docs/04`.
    public enum LiftOff: UInt8, Hashable, Sendable, CaseIterable {
        case low = 1
        case medium = 2
        case high = 3
    }

    /// The named level, or `nil` for a value outside the three G Hub offers.
    public var liftOffLevel: LiftOff? { LiftOff(rawValue: liftOff) }

    public init(x: UInt16, y: UInt16, liftOff: UInt8) {
        self.x = x
        self.y = y
        self.liftOff = liftOff
    }

    public init?(decoding bytes: some Collection<UInt8>) {
        guard bytes.count == Self.byteCount else { return nil }
        let b = Array(bytes)
        self.x = UInt16(b[0]) | UInt16(b[1]) << 8
        self.y = UInt16(b[2]) | UInt16(b[3]) << 8
        self.liftOff = b[4]
    }

    public var encoded: [UInt8] {
        [
            UInt8(x & 0xFF), UInt8(x >> 8),
            UInt8(y & 0xFF), UInt8(y >> 8),
            liftOff
        ]
    }
}

/// A profile's DPI stages and which one is active by default.
public struct DPITable: Hashable, Sendable {
    public var stages: [DPIStage]
    /// Index into `stages`. Cross-checks against `0x8100 getActiveProfileResolution`.
    public var defaultIndex: Int

    public init(stages: [DPIStage], defaultIndex: Int) {
        self.stages = stages
        self.defaultIndex = defaultIndex
    }

    public var activeStage: DPIStage? {
        stages.indices.contains(defaultIndex) ? stages[defaultIndex] : nil
    }
}

