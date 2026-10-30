import Foundation
import UTUVOMouseLocalization

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

/// Verified format-8 layout from Nanostrike. DPI is five 5-byte stages;
/// byte 2 selects the default. Byte 1 is not the selected stage.
public enum ProfileLayout {
    public static let reportRateOffset = 0
    public static let resolutionIndexOffset = 2
    public static let dpiWordsOffset = 4
    public static let dpiStageCount = 5
    public static let analogButtonsOffset = 0x26
    public static let analogButtonCount = 2
    public static let buttonsOffset = 0x30
    public static let buttonSlotSize = 4
    public static let buttonSlotCount = 5
    public static let gShiftOffset = 0x44
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

    /// A catalog-backed summary for user-visible surfaces. The legacy
    /// `summary` remains available to callers that depend on its stable output.
    public func localizedSummary(language: MouseLanguage) -> String {
        let localizer = MouseLocalizer(language: language)
        let code = String(format: "0x%X", code)
        return switch kind {
        case .disabled:
            localizer.string("profile.action.disabled")
        case .mouse:
            localizer.string("profile.action.mouse", arguments: [code])
        case .key:
            localizer.string("profile.action.key", arguments: [code])
        case .consumer:
            localizer.string("profile.action.consumer", arguments: [code])
        case .function:
            localizer.string("profile.action.function", arguments: [code])
        case .raw:
            localizer.string("profile.action.raw", arguments: [raw.map { String(format: "%02X", $0) }.joined(separator: " ")])
        }
    }
}

/// One profile sector of the Superstrike's onboard memory.
public struct ProfileSector: Equatable, Sendable {
    /// The complete sector, including the trailing CRC.
    public var bytes: [UInt8]
    /// The memory sector this content came from.
    public var sector: Int

    /// The live stage from 0x8100 fn0B, when available. Nil decodes the default.
    public var activeDPIIndex: Int?

    public init(bytes: [UInt8], sector: Int, activeDPIIndex: Int? = nil) {
        self.bytes = bytes
        self.sector = sector
        self.activeDPIIndex = activeDPIIndex
    }

    public var count: Int { bytes.count }

    public var reportRateByte: UInt8 { bytes[ProfileLayout.reportRateOffset] }
    public var reportRateHz: Int { ProfileLayout.reportRateHz(forByte: reportRateByte) }

    public var selectedDPIIndex: Int {
        activeDPIIndex ?? (bytes.count > ProfileLayout.resolutionIndexOffset ? Int(bytes[ProfileLayout.resolutionIndexOffset]) : -1)
    }

    public var dpiStages: [DPIStage] {
        (0..<ProfileLayout.dpiStageCount).compactMap { index in
            let offset = ProfileLayout.dpiWordsOffset + index * DPIStage.byteCount
            guard offset + DPIStage.byteCount <= bytes.count else { return nil }
            return DPIStage(decoding: bytes[offset..<(offset + DPIStage.byteCount)])
        }
    }

    private var selectedDPIStage: DPIStage? {
        let stages = dpiStages
        return stages.indices.contains(selectedDPIIndex) ? stages[selectedDPIIndex] : nil
    }
    public var dpiX: Int { selectedDPIStage.map { Int($0.x) } ?? 0 }
    public var dpiY: Int { selectedDPIStage.map { Int($0.y) } ?? 0 }

    public var hitsButtons: [HitsButtonConfig] {
        (0..<ProfileLayout.analogButtonCount).compactMap { button in
            let offset = ProfileLayout.analogButtonsOffset + button * AnalogButtonRecord.byteCount
            guard offset + AnalogButtonRecord.byteCount <= bytes.count,
                  let record = AnalogButtonRecord(decoding: bytes[offset..<(offset + AnalogButtonRecord.byteCount)]) else { return nil }
            return HitsButtonConfig(button: button, record: record)
        }
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

    /// Format 8 has no verified profile-name field. Do not decode unknown bytes.
    public var name: String { "" }

    /// The five verified main button records.
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

    /// Patches the selected stage, preserving its lift-off byte and other stages.
    /// Saves the same stage as default so the requested DPI survives reconnect.
    public func settingDPI(x: Int, y: Int) throws -> ProfileSector {
        guard (100...ProfileLayout.maximumDPI).contains(x), (100...ProfileLayout.maximumDPI).contains(y) else {
            throw HIDPPError.localized(key: "error.profile.dpiRange", arguments: ["100", String(ProfileLayout.maximumDPI)])
        }
        guard bytes.count == 255, var stage = selectedDPIStage else {
            throw HIDPPError.malformedReport("invalid selected DPI stage")
        }
        stage.x = UInt16(x); stage.y = UInt16(y)
        let offset = ProfileLayout.dpiWordsOffset + selectedDPIIndex * DPIStage.byteCount
        var copy = self
        copy.bytes.replaceSubrange(offset..<(offset + DPIStage.byteCount), with: stage.encoded)
        copy.bytes[ProfileLayout.resolutionIndexOffset] = UInt8(selectedDPIIndex)
        return copy
    }

    /// Copies known live values into this sector's own record, preserving its
    /// reserved bits. Used to save current HITS without resetting the other key.
    public func settingHITS(_ config: HitsButtonConfig) throws -> ProfileSector {
        guard bytes.count == 255, hitsButtons.indices.contains(config.button) else {
            throw HIDPPError.localized(key: "error.features.hitsLeftRightOnly", arguments: [])
        }
        _ = try config.validatedRecord()
        var stored = hitsButtons[config.button]
        stored.actuation = config.actuation
        stored.rapidTrigger = config.rapidTrigger
        stored.rapidTriggerEnabled = config.rapidTriggerEnabled
        stored.haptics = config.haptics
        let offset = ProfileLayout.analogButtonsOffset + config.button * AnalogButtonRecord.byteCount
        var copy = self
        copy.bytes.replaceSubrange(offset..<(offset + AnalogButtonRecord.byteCount), with: try stored.validatedRecord().encoded)
        return copy
    }

    /// Uses the sector's own reserved bits, never a live reply's reserved bits.
    public func settingHITS(_ draft: HIDPPClient.HitsDraft) throws -> ProfileSector {
        guard bytes.count == 255, (0..<ProfileLayout.analogButtonCount).contains(draft.button) else {
            throw HIDPPError.localized(key: "error.features.hitsLeftRightOnly", arguments: [])
        }
        let current = hitsButtons[draft.button]
        let updated = try draft.applying(to: current)
        let offset = ProfileLayout.analogButtonsOffset + draft.button * AnalogButtonRecord.byteCount
        var copy = self
        copy.bytes.replaceSubrange(offset..<(offset + AnalogButtonRecord.byteCount), with: try updated.validatedRecord().encoded)
        return copy
    }

    /// Returns a copy with the report rate byte replaced.
    public func settingReportRate(hz: Int) throws -> ProfileSector {
        guard ProfileLayout.reportRates.contains(hz), let byte = ProfileLayout.reportRateByte(forHz: hz) else {
            throw HIDPPError.localized(key: "error.profile.reportRate", arguments: [String(hz)])
        }
        var copy = self
        copy.bytes[ProfileLayout.reportRateOffset] = byte
        return copy
    }

    /// Returns a copy with one button slot replaced. Every other byte is kept.
    public func settingButton(slot: Int, action: ButtonAction) throws -> ProfileSector {
        guard slot >= 0, slot < ProfileLayout.buttonSlotCount else {
            throw HIDPPError.localized(key: "error.profile.buttonSlotRange", arguments: [String(slot)])
        }
        let offset = ProfileLayout.buttonsOffset + slot * ProfileLayout.buttonSlotSize
        guard offset + 4 <= bytes.count else {
            throw HIDPPError.localized(key: "error.profile.buttonTableRange", arguments: [])
        }
        var copy = self
        let encoded = action.encoded()
        copy.bytes.replaceSubrange(offset..<(offset + 4), with: encoded)
        return copy
    }
}
