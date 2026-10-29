import Foundation

/// CRC-16/CCITT-FALSE — polynomial 0x1021, initial value 0xFFFF, no reflection,
/// no final XOR. The Superstrike stores it big endian in the last two bytes of a
/// profile sector.
public enum CRC16CCITT {
    public static func compute(_ bytes: [UInt8]) -> UInt16 {
        var crc: UInt16 = 0xFFFF
        for byte in bytes {
            crc ^= UInt16(byte) << 8
            for _ in 0..<8 {
                if crc & 0x8000 != 0 {
                    crc = (crc << 1) ^ 0x1021
                } else {
                    crc <<= 1
                }
            }
        }
        return crc
    }
}

/// Byte offsets inside a Superstrike profile sector.
///
/// The Superstrike deviates from the generic layout: the button table starts at
/// 48 (not 32) and the live X/Y DPI words are the last two of the five DPI words
/// (bytes 9...10 and 11...12).
public enum ProfileLayout {
    public static let reportRateOffset = 0
    public static let resolutionIndexOffset = 1
    public static let shiftResolutionOffset = 2
    public static let dpiWordsOffset = 3
    public static let dpiXOffset = 9
    public static let dpiYOffset = 11
    public static let buttonsOffset = 48
    public static let buttonSlotSize = 4
    public static let buttonSlotCount = 16
    public static let gShiftOffset = 112
    public static let nameOffset = 160
    public static let nameLength = 48
    /// `Hz = 125 << byte`
    public static let reportRates = [125, 250, 500, 1000, 2000, 4000, 8000]
    public static let maximumDPI = 44_000

    public static func reportRateHz(forByte byte: UInt8) -> Int {
        guard byte < 32 else { return 0 }
        return 125 << byte
    }

    public static func reportRateByte(forHz hz: Int) -> UInt8? {
        for byte in 0..<32 where 125 << byte == hz { return UInt8(byte) }
        return nil
    }
}

/// A button assignment stored in the profile's button table.
public struct ButtonAction: Equatable, Sendable {
    public enum Kind: Equatable, Sendable {
        case disabled
        case mouse
        case key
        case consumer
        case function
        /// Anything this build does not understand; kept verbatim.
        case raw
    }

    public var kind: Kind
    /// Mouse mask, HID key code or consumer code depending on `kind`.
    public var code: UInt16
    /// Modifier mask for keyboard assignments.
    public var modifiers: UInt8
    /// The original four bytes.
    public var raw: [UInt8]

    public init(kind: Kind, code: UInt16 = 0, modifiers: UInt8 = 0, raw: [UInt8] = [0xFF, 0xFF, 0xFF, 0xFF]) {
        self.kind = kind
        self.code = code
        self.modifiers = modifiers
        self.raw = raw
    }

    public static let disabled = ButtonAction(kind: .disabled)

    /// Decodes one four byte button record.
    public static func decode(_ bytes: [UInt8]) -> ButtonAction {
        guard bytes.count >= 4 else { return .disabled }
        let raw = Array(bytes.prefix(4))
        switch bytes[0] >> 4 {
        case 0x8:  // SEND
            switch bytes[1] {
            case 0x01:
                return ButtonAction(kind: .mouse, code: (UInt16(bytes[2]) << 8) | UInt16(bytes[3]), raw: raw)
            case 0x02:
                return ButtonAction(kind: .key, code: UInt16(bytes[3]), modifiers: bytes[2], raw: raw)
            case 0x03:
                return ButtonAction(kind: .consumer, code: (UInt16(bytes[2]) << 8) | UInt16(bytes[3]), raw: raw)
            default:
                return ButtonAction(kind: .disabled, raw: raw)
            }
        case 0x9:  // FUNCTION
            return ButtonAction(kind: .function, code: UInt16(bytes[1]), raw: raw)
        default:
            if bytes[0] == 0xFF {
                return ButtonAction(kind: .disabled, raw: raw)
            }
            return ButtonAction(kind: .raw, raw: raw)
        }
    }

    /// Encodes one four byte button record.
    public func encoded() -> [UInt8] {
        switch kind {
        case .mouse:
            return [0x80, 0x01, UInt8(truncatingIfNeeded: code >> 8), UInt8(truncatingIfNeeded: code)]
        case .key:
            return [0x80, 0x02, modifiers, UInt8(truncatingIfNeeded: code)]
        case .consumer:
            return [0x80, 0x03, UInt8(truncatingIfNeeded: code >> 8), UInt8(truncatingIfNeeded: code)]
        case .function:
            return [0x90, UInt8(truncatingIfNeeded: code), 0xFF, 0x00]
        case .raw:
            return raw.count >= 4 ? Array(raw.prefix(4)) : [0xFF, 0xFF, 0xFF, 0xFF]
        case .disabled:
            return [0x80, 0x00, 0xFF, 0xFF]
        }
    }

    /// A short description for the interface.
    public var summary: String {
        switch kind {
        case .disabled: "停用"
        case .mouse: "滑鼠鍵 0x" + String(code, radix: 16, uppercase: true)
        case .key: "鍵盤 0x" + String(code, radix: 16, uppercase: true)
        case .consumer: "媒體鍵 0x" + String(code, radix: 16, uppercase: true)
        case .function: "內建功能 0x" + String(code, radix: 16, uppercase: true)
        case .raw: "自訂 " + raw.map { String(format: "%02X", $0) }.joined(separator: " ")
        }
    }
}

/// One profile sector of the Superstrike's onboard memory.
public struct ProfileSector: Equatable, Sendable {
    /// The complete sector, including the trailing CRC.
    public var bytes: [UInt8]
    /// The memory sector this content came from.
    public var sector: Int

    public init(bytes: [UInt8], sector: Int) {
        self.bytes = bytes
        self.sector = sector
    }

    public var count: Int { bytes.count }

    public var reportRateByte: UInt8 { bytes[ProfileLayout.reportRateOffset] }
    public var reportRateHz: Int { ProfileLayout.reportRateHz(forByte: reportRateByte) }

    public var dpiX: Int {
        Int(bytes[ProfileLayout.dpiXOffset]) | (Int(bytes[ProfileLayout.dpiXOffset + 1]) << 8)
    }

    public var dpiY: Int {
        Int(bytes[ProfileLayout.dpiYOffset]) | (Int(bytes[ProfileLayout.dpiYOffset + 1]) << 8)
    }

    /// The stored CRC, big endian in the last two bytes.
    public var storedCRC: UInt16? {
        guard bytes.count >= 2 else { return nil }
        return (UInt16(bytes[bytes.count - 2]) << 8) | UInt16(bytes[bytes.count - 1])
    }

    /// Whether the trailing CRC matches the content.
    public var hasValidCRC: Bool {
        guard bytes.count >= 2 else { return false }
        let expected = CRC16CCITT.compute(Array(bytes.prefix(bytes.count - 2)))
        return expected == storedCRC
    }

    /// The profile name, UTF-16LE.
    public var name: String {
        guard bytes.count >= ProfileLayout.nameOffset + ProfileLayout.nameLength else { return "" }
        var units: [UInt16] = []
        var index = ProfileLayout.nameOffset
        while index + 1 < ProfileLayout.nameOffset + ProfileLayout.nameLength {
            let unit = UInt16(bytes[index]) | (UInt16(bytes[index + 1]) << 8)
            if unit == 0x0000 || unit == 0xFFFF { break }
            units.append(unit)
            index += 2
        }
        return String(decoding: units, as: UTF16.self)
            .trimmingCharacters(in: .whitespaces)
    }

    /// The 16 button slots of this profile.
    public var buttonSlots: [ButtonAction] {
        (0..<ProfileLayout.buttonSlotCount).map { slot in
            let offset = ProfileLayout.buttonsOffset + slot * ProfileLayout.buttonSlotSize
            guard offset + 4 <= bytes.count else { return .disabled }
            return ButtonAction.decode(Array(bytes[offset..<(offset + 4)]))
        }
    }

    /// Returns a copy with the CRC recomputed over the content.
    public func withRecomputedCRC() -> ProfileSector {
        var copy = self
        guard copy.bytes.count >= 2 else { return copy }
        let crc = CRC16CCITT.compute(Array(copy.bytes.prefix(copy.bytes.count - 2)))
        copy.bytes[copy.bytes.count - 2] = UInt8(truncatingIfNeeded: crc >> 8)
        copy.bytes[copy.bytes.count - 1] = UInt8(truncatingIfNeeded: crc)
        return copy
    }

    /// Returns a copy with the X/Y DPI words replaced. Every other byte is kept.
    public func settingDPI(x: Int, y: Int) throws -> ProfileSector {
        guard (100...ProfileLayout.maximumDPI).contains(x), (100...ProfileLayout.maximumDPI).contains(y) else {
            throw HIDPPError.unsupported("DPI 必須介於 100 與 \(ProfileLayout.maximumDPI)")
        }
        var copy = self
        copy.bytes[ProfileLayout.dpiXOffset] = UInt8(truncatingIfNeeded: x)
        copy.bytes[ProfileLayout.dpiXOffset + 1] = UInt8(truncatingIfNeeded: x >> 8)
        copy.bytes[ProfileLayout.dpiYOffset] = UInt8(truncatingIfNeeded: y)
        copy.bytes[ProfileLayout.dpiYOffset + 1] = UInt8(truncatingIfNeeded: y >> 8)
        return copy
    }

    /// Returns a copy with the report rate byte replaced.
    public func settingReportRate(hz: Int) throws -> ProfileSector {
        guard let byte = ProfileLayout.reportRateByte(forHz: hz) else {
            throw HIDPPError.unsupported("不支援的回報率 \(hz) Hz")
        }
        var copy = self
        copy.bytes[ProfileLayout.reportRateOffset] = byte
        return copy
    }

    /// Returns a copy with one button slot replaced. Every other byte is kept.
    public func settingButton(slot: Int, action: ButtonAction) throws -> ProfileSector {
        guard slot >= 0, slot < ProfileLayout.buttonSlotCount else {
            throw HIDPPError.unsupported("按鍵槽位 \(slot) 超出範圍")
        }
        let offset = ProfileLayout.buttonsOffset + slot * ProfileLayout.buttonSlotSize
        guard offset + 4 <= bytes.count else {
            throw HIDPPError.unsupported("按鍵表超出此 sector 範圍")
        }
        var copy = self
        let encoded = action.encoded()
        copy.bytes.replaceSubrange(offset..<(offset + 4), with: encoded)
        return copy
    }
}
