// Adapted from jwake/nanostrike (MIT). See LICENSES/Nanostrike-MIT.txt.
/// One analog (HITS) button's settings as three packed bytes.
///
/// This layout was recovered independently from the Windows x86-64 profile
/// library and from G Hub's arm64 `setConfig`, and confirmed against the device.
/// It is identical on the wire and in onboard profile storage.
///
///     byte 0   bits 7..2  actuation point
///     byte 1   bits 7..2  rapid trigger sensitivity, bit 0 rapid trigger enable
///     byte 2   bits 7..2  haptic level
///
/// The remaining five bits (byte 0 bits 1..0, byte 1 bit 1, byte 2 bits 1..0)
/// have no known meaning, and Logitech's own setters clear them. They are
/// nonetheless carried through a decode/encode round trip unchanged rather than
/// being written back as zero: `ProfileSector.replacingAnalogButtons` patches
/// these bytes into a sector and recomputes its CRC, so a bit dropped here would
/// reach the hardware under a valid checksum, with no way for the device to
/// notice. Preserving them costs three bytes of storage.
///
/// See `docs/03-feature-1b0c-hits-analog-buttons.md`.
public struct AnalogButtonRecord: Hashable, Sendable {
    public static let byteCount = 3

    /// Step index, 1...`analogButtonLevelResolution`. Not a distance.
    public var actuationPoint: UInt8
    public var rapidTriggerEnabled: Bool
    /// Step index, 1...`rapidTriggerSensitivityResolution`.
    public var rapidTriggerSensitivity: UInt8
    /// Step index, 0...`hapticsResolution`. Zero disables haptics.
    public var hapticLevel: UInt8

    /// The bytes this record was decoded from, so that bits outside the known
    /// fields can be reproduced exactly. Zero for a record built from fields,
    /// which is the same as what the old encoder always emitted.
    private var rawBytes: [UInt8]

    public init(
        actuationPoint: UInt8,
        rapidTriggerEnabled: Bool,
        rapidTriggerSensitivity: UInt8,
        hapticLevel: UInt8
    ) {
        self.actuationPoint = actuationPoint
        self.rapidTriggerEnabled = rapidTriggerEnabled
        self.rapidTriggerSensitivity = rapidTriggerSensitivity
        self.hapticLevel = hapticLevel
        // No original bytes to preserve, so the reserved bits default to zero.
        self.rawBytes = [UInt8](repeating: 0, count: Self.byteCount)
    }

    public init?(decoding bytes: some Collection<UInt8>) {
        guard bytes.count == Self.byteCount else { return nil }
        let b = Array(bytes)
        self.actuationPoint = b[0] >> 2
        self.rapidTriggerSensitivity = b[1] >> 2
        self.rapidTriggerEnabled = b[1] & 0x01 != 0
        self.hapticLevel = b[2] >> 2
        self.rawBytes = b
    }

    /// The known fields patched into the bytes this record came from, so that
    /// decoding and re-encoding is byte-for-byte lossless.
    public var encoded: [UInt8] {
        [
            actuationPoint << 2 | (rawBytes[0] & 0x03),
            rapidTriggerSensitivity << 2 | (rawBytes[1] & 0x02) | (rapidTriggerEnabled ? 1 : 0),
            hapticLevel << 2 | (rawBytes[2] & 0x03)
        ]
    }

    // Equality is over the decoded fields only, deliberately excluding the
    // preserved bits. `ProfileSector.matches(liveAnalogButtons:)` compares
    // records read from a sector against records built from a live HID++ reply,
    // which has no bytes to preserve; treating a reserved bit as a difference
    // would make that check fail on a device whose stored profile happened to
    // have one set, which is exactly the false alarm the check must not raise.
    public static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.actuationPoint == rhs.actuationPoint
            && lhs.rapidTriggerEnabled == rhs.rapidTriggerEnabled
            && lhs.rapidTriggerSensitivity == rhs.rapidTriggerSensitivity
            && lhs.hapticLevel == rhs.hapticLevel
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(actuationPoint)
        hasher.combine(rapidTriggerEnabled)
        hasher.combine(rapidTriggerSensitivity)
        hasher.combine(hapticLevel)
    }
}
