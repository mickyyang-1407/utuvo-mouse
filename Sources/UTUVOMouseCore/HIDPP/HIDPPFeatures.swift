import Foundation
import UTUVOMouseLocalization

/// Battery state read from the unified battery feature (0x1004).
public struct BatteryStatus: Sendable, Equatable {
    /// Charge percentage, only filled when the device says it reports one.
    public var percentage: Int?
    public var charging: Bool?
    /// Why a value is unknown.
    public var note: String?
    /// Catalog key for an app-owned diagnostic note, when applicable.
    public var noteLocalizationKey: String?

    public init(percentage: Int? = nil, charging: Bool? = nil, note: String? = nil, noteLocalizationKey: String? = nil) {
        self.percentage = percentage
        self.charging = charging
        self.note = note
        self.noteLocalizationKey = noteLocalizationKey
    }

    public func message(language: MouseLanguage) -> String? {
        if let noteLocalizationKey { return MouseLocalizer(language: language).string(noteLocalizationKey) }
        return note
    }

    public static let unknown = BatteryStatus(noteLocalizationKey: "device.battery.note.notRead")
}

/// DPI state read from the classic adjustable DPI feature (0x2201).
public struct DPIState: Sendable, Equatable {
    public var current: Int?
    public var available: [Int]
    /// Why the current value is unknown.
    public var note: String?

    public init(current: Int? = nil, available: [Int] = [], note: String? = nil) {
        self.current = current
        self.available = available
        self.note = note
    }
}

/// SmartShift state (0x2110 classic, 0x2111 enhanced).
public struct SmartShiftState: Sendable, Equatable {
    /// 1 = free scrolling, 2 = ratchet.
    public var mode: Int?
    /// Automatic release threshold.
    public var threshold: Int?
    /// Current tunable torque in percent of the maximum force (enhanced feature).
    public var torque: Int?
    /// Capability bits (enhanced feature); bit 0 = tunable torque.
    public var capabilities: UInt8?
    /// Default automatic release threshold (enhanced feature).
    public var defaultThreshold: Int?
    /// Default tunable torque (enhanced feature).
    public var defaultTorque: Int?
    /// Maximum force in gram-force units (enhanced feature).
    public var maxForce: Int?
    /// Threshold bounds of the classic feature.
    public var minThreshold: Int?
    public var maxThreshold: Int?

    public init(
        mode: Int? = nil,
        threshold: Int? = nil,
        torque: Int? = nil,
        capabilities: UInt8? = nil,
        defaultThreshold: Int? = nil,
        defaultTorque: Int? = nil,
        maxForce: Int? = nil,
        minThreshold: Int? = nil,
        maxThreshold: Int? = nil
    ) {
        self.mode = mode
        self.threshold = threshold
        self.torque = torque
        self.capabilities = capabilities
        self.defaultThreshold = defaultThreshold
        self.defaultTorque = defaultTorque
        self.maxForce = maxForce
        self.minThreshold = minThreshold
        self.maxThreshold = maxThreshold
    }
}

/// Wheel control state (0x2121).
public struct WheelState: Sendable, Equatable {
    public var inverted: Bool?
    public var highResolution: Bool?
    /// false = the wheel keeps its native function, true = the wheel is diverted.
    public var diverted: Bool?
    /// The raw wheel mode byte.
    public var modeByte: UInt8?
    /// The capability byte of the wheel feature.
    public var capabilities: UInt8?
    /// Bits this build does not interpret; they are preserved on write.
    public var reserved: UInt8

    public init(
        inverted: Bool? = nil,
        highResolution: Bool? = nil,
        diverted: Bool? = nil,
        modeByte: UInt8? = nil,
        capabilities: UInt8? = nil,
        reserved: UInt8 = 0
    ) {
        self.inverted = inverted
        self.highResolution = highResolution
        self.diverted = diverted
        self.modeByte = modeByte
        self.capabilities = capabilities
        self.reserved = reserved
    }
}

/// Capabilities of the analog button feature (0x1B0C) — the Superstrike HITS controls.
public struct HitsCapabilities: Sendable, Equatable {
    public var buttonCount: Int
    public var maxActuation: Int
    public var maxRapidTrigger: Int
    public var maxHaptics: Int

    public init(buttonCount: Int, maxActuation: Int, maxRapidTrigger: Int, maxHaptics: Int) {
        self.buttonCount = buttonCount
        self.maxActuation = maxActuation
        self.maxRapidTrigger = maxRapidTrigger
        self.maxHaptics = maxHaptics
    }
}

/// One analog button's live or stored HITS settings.
public struct HitsButtonConfig: Sendable, Equatable {
    public var button: Int
    public var actuation: Int
    /// Sensitivity 1...5, including when rapid trigger is disabled.
    public var rapidTrigger: Int
    public var haptics: Int
    /// Bit 0 is the enable switch; it is independent of sensitivity.
    public var rapidTriggerFlag: UInt8
    private var original: AnalogButtonRecord

    public var rapidTriggerEnabled: Bool {
        get { rapidTriggerFlag & 1 != 0 }
        set { rapidTriggerFlag = newValue ? 1 : 0 }
    }

    public init(button: Int, actuation: Int, rapidTrigger: Int, haptics: Int, rapidTriggerFlag: UInt8 = 0) {
        self.button = button
        self.actuation = actuation
        self.rapidTrigger = rapidTrigger
        self.haptics = haptics
        self.rapidTriggerFlag = rapidTriggerFlag & 1
        self.original = AnalogButtonRecord(actuationPoint: 1, rapidTriggerEnabled: false, rapidTriggerSensitivity: 1, hapticLevel: 0)
    }

    public init(button: Int, record: AnalogButtonRecord) {
        self.button = button
        self.actuation = Int(record.actuationPoint)
        self.rapidTrigger = Int(record.rapidTriggerSensitivity)
        self.haptics = Int(record.hapticLevel)
        self.rapidTriggerFlag = record.rapidTriggerEnabled ? 1 : 0
        self.original = record
    }

    public static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.button == rhs.button && lhs.actuation == rhs.actuation
            && lhs.rapidTrigger == rhs.rapidTrigger && lhs.haptics == rhs.haptics
            && lhs.rapidTriggerEnabled == rhs.rapidTriggerEnabled
    }

    /// Starts from the bytes of this record, preserving all reserved bits.
    public func validatedRecord(maxActuation: Int = 10, maxRapidTrigger: Int = 5, maxHaptics: Int = 5) throws -> AnalogButtonRecord {
        guard (0...1).contains(button) else {
            throw HIDPPError.localized(key: "error.features.hitsLeftRightOnly", arguments: [])
        }
        guard maxActuation >= 1, (1...min(maxActuation, 10)).contains(actuation) else {
            throw HIDPPError.localized(key: "error.features.hitsActuationRange", arguments: [String(min(maxActuation, 10))])
        }
        guard maxRapidTrigger >= 1, (1...min(maxRapidTrigger, 5)).contains(rapidTrigger) else {
            throw HIDPPError.localized(key: "error.features.hitsRapidRange", arguments: [String(min(maxRapidTrigger, 5))])
        }
        guard maxHaptics >= 0, (0...min(maxHaptics, 5)).contains(haptics) else {
            throw HIDPPError.localized(key: "error.features.hitsHapticsRange", arguments: [String(min(maxHaptics, 5))])
        }
        var record = original
        record.actuationPoint = UInt8(actuation)
        record.rapidTriggerSensitivity = UInt8(rapidTrigger)
        record.rapidTriggerEnabled = rapidTriggerEnabled
        record.hapticLevel = UInt8(haptics)
        return record
    }
}

/// Feature discovery and the typed readers for the settings this app supports.
extension HIDPPClient {

    /// Resolves a feature ID to its runtime index through the root feature (0x0000).
    ///
    /// The reply is `[index, flags, version]`; an index of 0 means the device does
    /// not implement the feature.
    public func resolveFeature(_ id: UInt16) async throws -> HIDPPFeature? {
        let data = try await request(
            featureIndex: 0,
            function: 0,
            payload: [UInt8(truncatingIfNeeded: id >> 8), UInt8(truncatingIfNeeded: id)],
            shortFallback: true
        )
        guard data.count >= 3 else {
            throw HIDPPError.malformedReport("root getFeature answered \(data.count) bytes")
        }
        let index = data[0]
        guard index != 0x00, index != 0xFF else { return nil }
        return HIDPPFeature(id: id, index: index, version: data[2], flags: data[1])
    }

    /// Enumerates every feature the device implements (feature set 0x0001).
    public func enumerateFeatures() async throws -> [HIDPPFeature] {
        guard let featureSet = try await resolveFeature(HIDPPFeatureID.featureSet) else { return [] }
        let countData = try await request(featureIndex: featureSet.index, function: 0, shortFallback: true)
        guard let count = countData.first, count >= 1 else { return [] }
        var features: [HIDPPFeature] = []
        for index in 1...count {
            let data = try await request(featureIndex: featureSet.index, function: 1, payload: [index], shortFallback: true)
            guard data.count >= 3 else { continue }
            let id = (UInt16(data[0]) << 8) | UInt16(data[1])
            features.append(HIDPPFeature(id: id, index: index, version: 0, flags: data[2]))
        }
        return features
    }

    /// Reads the battery state (0x1004).
    ///
    /// The percentage is only reported when the device's capability byte says it
    /// knows the charge level; otherwise the value stays unknown.
    public func readBattery() async throws -> BatteryStatus {
        guard let feature = try await resolveFeature(HIDPPFeatureID.unifiedBattery) else {
            return BatteryStatus(noteLocalizationKey: "device.battery.note.noFeature")
        }
        let capabilities = try await request(featureIndex: feature.index, function: 0, shortFallback: true)
        let status = try await request(featureIndex: feature.index, function: 1, shortFallback: true)
        guard !status.isEmpty else {
            return BatteryStatus(noteLocalizationKey: "device.battery.note.empty")
        }
        let reportsPercentage = capabilities.first.map { $0 & 0x01 != 0 } ?? false
        let percentage = reportsPercentage ? Int(status[0]) : nil
        let charging: Bool? = status.count >= 3 ? chargingState(status[2]) : nil
        return BatteryStatus(
            percentage: percentage,
            charging: charging,
            noteLocalizationKey: reportsPercentage ? nil : "device.battery.note.noPercentage"
        )
    }

    /// Reads the DPI state of the classic adjustable DPI feature (0x2201).
    ///
    /// The replies carry the sensor index back in byte 0. The DPI list may contain
    /// range markers: a word with the top three bits set is a marker whose low 13
    /// bits are the step, the preceding literal is the range start and the next
    /// literal the range end.
    public func readDPI() async throws -> DPIState {
        guard let feature = try await resolveFeature(HIDPPFeatureID.adjustableDPI) else {
            return DPIState()
        }
        let sensorPayload: [UInt8] = [0x00, 0x00, 0x00]
        guard let countData = try? await request(featureIndex: feature.index, function: 0, payload: sensorPayload),
              let sensorCount = countData.first, sensorCount > 0 else {
            return DPIState()
        }
        var words: [Int] = []
        if let listData = try? await request(featureIndex: feature.index, function: 1, payload: sensorPayload) {
            // Byte 0 echoes the sensor index; a wrong echo means the reply does
            // not belong to this request.
            guard listData.count >= 3, listData[0] == 0x00 else {
                return DPIState(note: "裝置回報的感應器索引不符，DPI 未知")
            }
            var index = 1
            while index + 1 < listData.count {
                let word = (Int(listData[index]) << 8) | Int(listData[index + 1])
                if word == 0 { break }
                words.append(word)
                index += 2
            }
        }
        let available: [Int]
        do {
            available = try expandDPIWords(words)
        } catch {
            return DPIState(note: "裝置回報的 DPI 清單無法解析，DPI 未知")
        }
        guard !available.isEmpty else {
            return DPIState(note: "裝置沒有回報可用的 DPI 清單")
        }
        var current: Int?
        var note: String?
        if let value = try? await request(featureIndex: feature.index, function: 2, payload: sensorPayload), value.count >= 3 {
            if value[0] != 0x00 {
                return DPIState(available: available, note: "裝置回報的感應器索引不符，DPI 未知")
            }
            let reported = (Int(value[1]) << 8) | Int(value[2])
            if available.contains(reported) {
                current = reported
            } else {
                note = "裝置回報的 DPI（\(reported)）不在它自己的清單裡，視為未知"
            }
        } else {
            note = "裝置沒有回報目前的 DPI"
        }
        return DPIState(current: current, available: available, note: note)
    }

    /// Sets the DPI through the classic feature (0x2201).
    ///
    /// The device only accepts a value it reports itself, so the requested DPI is
    /// checked against the list first.
    public func setDPI(_ dpi: Int) async throws {
        guard let feature = try await resolveFeature(HIDPPFeatureID.adjustableDPI) else {
            throw HIDPPError.localized(key: "error.features.dpiUnavailable", arguments: [])
        }
        guard (100...44_000).contains(dpi) else {
            throw HIDPPError.localized(key: "error.features.dpiRange", arguments: [])
        }
        let state = try await readDPI()
        if !state.available.isEmpty, !state.available.contains(dpi) {
            throw HIDPPError.localized(key: "error.features.dpiUnsupported", arguments: [String(dpi), state.available.prefix(6).map(String.init).joined(separator: ", ")])
        }
        _ = try await request(
            featureIndex: feature.index,
            function: 3,
            payload: [
                0x00,
                UInt8(truncatingIfNeeded: dpi >> 8),
                UInt8(truncatingIfNeeded: dpi),
            ]
        )
    }

    /// Reads the SmartShift state (0x2111 enhanced, falling back to 0x2110).
    ///
    /// The enhanced feature reports `[capabilities, default threshold, default
    /// torque %, max force]` and a status of `[wheel mode, threshold, torque %]`.
    public func readSmartShift() async throws -> SmartShiftState {
        let enhanced = try await resolveFeature(HIDPPFeatureID.smartShiftEnhanced)
        let classic = try await resolveFeature(HIDPPFeatureID.smartShift)
        guard let feature = enhanced ?? classic else { return SmartShiftState() }
        var state = SmartShiftState()
        if let caps = try? await request(featureIndex: feature.index, function: 0, shortFallback: true), caps.count >= 3 {
            if enhanced != nil {
                state.capabilities = caps[0]
                state.defaultThreshold = Int(caps[1])
                state.defaultTorque = Int(caps[2])
                state.maxForce = caps.count >= 4 ? Int(caps[3]) : nil
            } else {
                state.minThreshold = Int(caps[1])
                state.maxThreshold = Int(caps[2])
            }
        }
        if let config = try? await request(featureIndex: feature.index, function: 1, shortFallback: true), config.count >= 2 {
            state.mode = Int(config[0])
            state.threshold = Int(config[1])
            if enhanced != nil, config.count >= 3 {
                state.torque = Int(config[2])
            }
        }
        return state
    }

    /// Writes the SmartShift mode and threshold, preserving the torque value.
    public func setSmartShift(mode: Int?, threshold: Int?) async throws {
        let enhanced = try await resolveFeature(HIDPPFeatureID.smartShiftEnhanced)
        let classic = try await resolveFeature(HIDPPFeatureID.smartShift)
        guard let feature = enhanced ?? classic else {
            throw HIDPPError.localized(key: "error.features.smartShiftUnavailable", arguments: [])
        }
        // Read the current configuration first so untouched fields survive.
        let current = try await request(featureIndex: feature.index, function: 1, shortFallback: true)
        var payload = [UInt8](repeating: 0, count: enhanced != nil ? 3 : 2)
        for index in payload.indices where index < current.count {
            payload[index] = current[index]
        }
        if let mode, mode > 0 { payload[0] = UInt8(mode) }
        if let threshold, threshold > 0 { payload[1] = UInt8(threshold) }
        _ = try await request(featureIndex: feature.index, function: 2, payload: payload)
    }

    /// Reads the wheel control flags (0x2121).
    ///
    /// Byte 0 of the wheel mode carries the target in bit 0 (native or diverted),
    /// the resolution in bit 1 (low or high) and the direction inversion in bit 2.
    /// The remaining bits and bytes belong to the firmware and are preserved.
    public func readWheel() async throws -> WheelState {
        guard let feature = try await resolveFeature(HIDPPFeatureID.wheelControl) else { return WheelState() }
        var state = WheelState()
        if let caps = try? await request(featureIndex: feature.index, function: 0, shortFallback: true),
           let first = caps.first {
            state.capabilities = first
        }
        guard let config = try? await request(featureIndex: feature.index, function: 1, shortFallback: true),
              let flags = config.first else { return state }
        state.modeByte = flags
        state.inverted = flags & 0b100 != 0
        state.highResolution = flags & 0b010 != 0
        state.diverted = flags & 0b001 != 0
        state.reserved = flags & 0b1111_1000
        return state
    }

    /// Writes the wheel control flags, preserving the bits this build does not know.
    public func setWheel(inverted: Bool?, highResolution: Bool?, diverted: Bool?) async throws {
        guard let feature = try await resolveFeature(HIDPPFeatureID.wheelControl) else {
            throw HIDPPError.localized(key: "error.features.wheelUnavailable", arguments: [])
        }
        let config = try await request(featureIndex: feature.index, function: 1, shortFallback: true)
        var flags = config.first ?? 0
        if let inverted { flags = inverted ? (flags | 0b100) : (flags & ~0b100) }
        if let highResolution { flags = highResolution ? (flags | 0b010) : (flags & ~0b010) }
        if let diverted { flags = diverted ? (flags | 0b001) : (flags & ~0b001) }
        _ = try await request(featureIndex: feature.index, function: 2, payload: [flags])
    }

    /// The sensor's accepted values, not an assumed constant DPI step.
    /// Range words can cross the 13-byte page boundary; join before decoding.
    public func readDPIGrid(axis: UInt8) async throws -> DPIGrid {
        guard axis < 2, let feature = try await resolveFeature(0x2202) else {
            throw HIDPPError.malformedReport("extended DPI grid unavailable")
        }
        var stream: [UInt8] = []
        var terminated = false
        for page: UInt8 in 0..<8 {
            let data = try await request(featureIndex: feature.index, function: 2, payload: [0, axis, page])
            guard data.count > 3, data[0] == 0, data[1] == axis, data[2] == page else {
                throw HIDPPError.malformedReport("DPI range page header mismatch")
            }
            stream.append(contentsOf: data[3...])
            terminated = stride(from: 0, to: stream.count - 1, by: 2).contains { stream[$0] == 0 && stream[$0+1] == 0 }
            if terminated { break }
        }
        let grid = DPIGrid(decodingRangeStream: stream)
        guard terminated, !grid.ranges.isEmpty,
              grid.ranges.allSatisfy({ $0.lowerBound >= 100 && $0.upperBound <= 44000 && $0.upperBound > $0.lowerBound && $0.step > 0 }) else {
            throw HIDPPError.malformedReport("incomplete or invalid DPI grid")
        }
        return grid
    }

    /// 0x2202 fn5: current X, default X, current Y, default Y (big endian).
    /// Cross-checked with Nanostrike's independently verified asymmetric values.
    public func readSensorDPI() async throws -> (x: Int, y: Int) {
        guard let feature = try await resolveFeature(0x2202) else {
            throw HIDPPError.malformedReport("extended DPI feature unavailable")
        }
        let data = try await request(featureIndex: feature.index, function: 5, payload: [0])
        guard data.count >= 10, data[0] == 0 else {
            throw HIDPPError.malformedReport("invalid sensor DPI reply")
        }
        return (Int(data[1]) << 8 | Int(data[2]), Int(data[5]) << 8 | Int(data[6]))
    }

    /// Reads the analog button capabilities (0x1B0C).
    public func readHitsCapabilities() async throws -> HitsCapabilities {
        guard let feature = try await resolveFeature(HIDPPFeatureID.analogButtons) else {
            throw HIDPPError.localized(key: "error.features.analogButtonsUnavailable", arguments: [])
        }
        let caps = try await request(featureIndex: feature.index, function: 0, shortFallback: true)
        guard caps.count >= 5 else {
            throw HIDPPError.malformedReport("analog button capabilities answered \(caps.count) bytes")
        }
        let mask = UInt16(caps[0]) << 8 | UInt16(caps[1])
        guard mask == 0x0003 else {
            throw HIDPPError.malformedReport("unsupported analog button bitfield")
        }
        let buttonCount = mask.nonzeroBitCount
        let maxActuation = Int(caps[2] >> 2)
        let maxRapidTrigger = Int(caps[3] >> 2)
        let maxHaptics = Int(caps[4] >> 2)
        guard maxActuation > 0, maxRapidTrigger > 0 else {
            throw HIDPPError.malformedReport("invalid analog button ranges")
        }
        return HitsCapabilities(
            buttonCount: buttonCount,
            maxActuation: maxActuation,
            maxRapidTrigger: maxRapidTrigger,
            maxHaptics: maxHaptics
        )
    }

    /// Reads the index and all three packed bytes, including reserved bits.
    public func readHitsButton(_ button: Int) async throws -> HitsButtonConfig {
        guard (0...1).contains(button) else {
            throw HIDPPError.localized(key: "error.features.hitsLeftRightOnly", arguments: [])
        }
        guard let feature = try await resolveFeature(HIDPPFeatureID.analogButtons) else {
            throw HIDPPError.localized(key: "error.features.analogButtonsUnavailable", arguments: [])
        }
        let data = try await request(featureIndex: feature.index, function: 2, payload: [UInt8(button)], shortFallback: true)
        guard data.count >= 4, Int(data[0] & 0x0F) == button,
              let record = AnalogButtonRecord(decoding: data[1...3]) else {
            throw HIDPPError.localized(key: "error.features.hitsButtonIndex", arguments: [])
        }
        let config = HitsButtonConfig(button: button, record: record)
        _ = try config.validatedRecord()
        return config
    }

    /// Volatile live write. Daily settings are saved through SuperstrikeService.
    public func setHitsButton(_ config: HitsButtonConfig, maxActuation: Int, maxRapidTrigger: Int, maxHaptics: Int) async throws {
        let record = try config.validatedRecord(maxActuation: maxActuation, maxRapidTrigger: maxRapidTrigger, maxHaptics: maxHaptics)
        guard let feature = try await resolveFeature(HIDPPFeatureID.analogButtons) else {
            throw HIDPPError.localized(key: "error.features.analogButtonsUnavailable", arguments: [])
        }
        _ = try await request(featureIndex: feature.index, function: 1, payload: [UInt8(config.button)] + record.encoded)
    }

    /// Nil preserves a field. UI choice 0 disables rapid trigger while keeping
    /// its valid sensitivity; choices 1...5 set sensitivity and enable it.
    public struct HitsDraft: Sendable, Equatable {
        public var button: Int
        public var actuation: Int?
        public var rapidTrigger: Int?
        public var haptics: Int?

        public init(button: Int, actuation: Int? = nil, rapidTrigger: Int? = nil, haptics: Int? = nil) {
            self.button = button
            self.actuation = actuation
            self.rapidTrigger = rapidTrigger
            self.haptics = haptics
        }

        public var isEmpty: Bool { actuation == nil && rapidTrigger == nil && haptics == nil }

        public func applying(to current: HitsButtonConfig, maxActuation: Int = 10, maxRapidTrigger: Int = 5, maxHaptics: Int = 5) throws -> HitsButtonConfig {
            guard !isEmpty else { throw HIDPPError.localized(key: "error.features.noChanges", arguments: []) }
            guard button == current.button else { throw HIDPPError.localized(key: "error.features.hitsButtonIndex", arguments: []) }
            var updated = current
            if let actuation { updated.actuation = actuation }
            if let haptics { updated.haptics = haptics }
            if let rapidTrigger {
                guard (0...5).contains(rapidTrigger) else {
                    throw HIDPPError.localized(key: "error.features.hitsRapidRange", arguments: [String(min(maxRapidTrigger, 5))])
                }
                updated.rapidTriggerEnabled = rapidTrigger > 0
                if rapidTrigger > 0 { updated.rapidTrigger = rapidTrigger }
            }
            _ = try updated.validatedRecord(maxActuation: maxActuation, maxRapidTrigger: maxRapidTrigger, maxHaptics: maxHaptics)
            return updated
        }
    }

    /// Changes only requested fields, and verifies enabled state as well as level.
    public func applyHits(draft: HitsDraft, maxActuation: Int, maxRapidTrigger: Int, maxHaptics: Int) async throws {
        let current = try await readHitsButton(draft.button)
        let updated = try draft.applying(to: current, maxActuation: maxActuation, maxRapidTrigger: maxRapidTrigger, maxHaptics: maxHaptics)
        try await setHitsButton(updated, maxActuation: maxActuation, maxRapidTrigger: maxRapidTrigger, maxHaptics: maxHaptics)
        let verify = try await readHitsButton(draft.button)
        guard try verify.validatedRecord() == updated.validatedRecord() else {
            throw HIDPPError.localized(key: "error.features.hitsVerify", arguments: [])
        }
    }

}

/// Maps the charging status byte of the unified battery feature.
private func chargingState(_ raw: UInt8) -> Bool? {
    switch raw {
    case 0: false   // discharging
    case 1: true    // charging
    case 2: true    // almost fully charged
    case 3: false   // charging complete
    default: nil
    }
}

/// Expands the DPI words of the classic adjustable DPI feature.
///
/// A word with the top three bits set is a range marker: its low 13 bits are the
/// step, the preceding literal is the range start and the following literal the
/// range end.
private func expandDPIWords(_ words: [Int]) throws -> [Int] {
    var values: [Int] = []
    var index = 0
    while index < words.count {
        let word = words[index]
        if word >> 13 == 0b111 {
            // A range marker: the step, the start (the previous literal) and the
            // end (the next literal).
            let step = word & 0x1FFF
            guard step > 0 else {
                throw HIDPPError.localized(key: "error.features.dpiRangeMissingStep", arguments: [])
            }
            guard index + 1 < words.count, let start = values.last else {
                throw HIDPPError.localized(key: "error.features.dpiRangeMissingStart", arguments: [])
            }
            let end = words[index + 1]
            guard (100...44_000).contains(end) else {
                throw HIDPPError.localized(key: "error.features.dpiEndRange", arguments: [String(end)])
            }
            guard end > start else {
                throw HIDPPError.localized(key: "error.features.dpiDescending", arguments: [])
            }
            var value = start + step
            while value < end {
                values.append(value)
                value += step
            }
            values.append(end)
            index += 2
            continue
        }
        guard (100...44_000).contains(word) else {
            throw HIDPPError.localized(key: "error.features.dpiValueRange", arguments: [String(word)])
        }
        values.append(word)
        index += 1
    }
    guard values.count > 1 else { return values }
    for position in 1..<values.count where values[position] <= values[position - 1] {
        throw HIDPPError.localized(key: "error.features.dpiNotAscending", arguments: [])
    }
    return values
}
