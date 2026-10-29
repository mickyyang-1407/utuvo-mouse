import Foundation

/// Battery state read from the unified battery feature (0x1004).
public struct BatteryStatus: Sendable, Equatable {
    /// Charge percentage, only filled when the device says it reports one.
    public var percentage: Int?
    public var charging: Bool?
    /// Why a value is unknown.
    public var note: String?

    public init(percentage: Int? = nil, charging: Bool? = nil, note: String? = nil) {
        self.percentage = percentage
        self.charging = charging
        self.note = note
    }

    public static let unknown = BatteryStatus(note: "尚未讀取")
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

/// One analog button's settings (0x1B0C).
public struct HitsButtonConfig: Sendable, Equatable {
    public var button: Int
    /// Actuation point, 1...10.
    public var actuation: Int
    /// Rapid trigger sensitivity, 0 = off, 1...5.
    public var rapidTrigger: Int
    /// Click haptic intensity, 0...5.
    public var haptics: Int
    /// Firmware managed bit in the rapid trigger byte; it must survive a write.
    public var rapidTriggerFlag: UInt8

    public init(button: Int, actuation: Int, rapidTrigger: Int, haptics: Int, rapidTriggerFlag: UInt8 = 0) {
        self.button = button
        self.actuation = actuation
        self.rapidTrigger = rapidTrigger
        self.haptics = haptics
        self.rapidTriggerFlag = rapidTriggerFlag
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
            return BatteryStatus(note: "此裝置沒有統一電池功能 (0x1004)")
        }
        let capabilities = try await request(featureIndex: feature.index, function: 0, shortFallback: true)
        let status = try await request(featureIndex: feature.index, function: 1, shortFallback: true)
        guard !status.isEmpty else {
            return BatteryStatus(note: "電池狀態回應為空")
        }
        let reportsPercentage = capabilities.first.map { $0 & 0x01 != 0 } ?? false
        let percentage = reportsPercentage ? Int(status[0]) : nil
        let charging: Bool? = status.count >= 3 ? chargingState(status[2]) : nil
        return BatteryStatus(
            percentage: percentage,
            charging: charging,
            note: reportsPercentage ? nil : "裝置未回報電量百分比"
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
            throw HIDPPError.unsupported("此裝置沒有可調 DPI 功能 (0x2201)")
        }
        guard (100...44_000).contains(dpi) else {
            throw HIDPPError.unsupported("DPI 必須介於 100 與 44000")
        }
        let state = try await readDPI()
        if !state.available.isEmpty, !state.available.contains(dpi) {
            throw HIDPPError.unsupported("裝置不支援 \(dpi) DPI（可用值：\(state.available.prefix(6).map(String.init).joined(separator: ", "))…）")
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
            throw HIDPPError.unsupported("此裝置沒有 SmartShift 功能")
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
            throw HIDPPError.unsupported("此裝置沒有輪組控制功能 (0x2121)")
        }
        let config = try await request(featureIndex: feature.index, function: 1, shortFallback: true)
        var flags = config.first ?? 0
        if let inverted { flags = inverted ? (flags | 0b100) : (flags & ~0b100) }
        if let highResolution { flags = highResolution ? (flags | 0b010) : (flags & ~0b010) }
        if let diverted { flags = diverted ? (flags | 0b001) : (flags & ~0b001) }
        _ = try await request(featureIndex: feature.index, function: 2, payload: [flags])
    }

    /// Reads the analog button capabilities (0x1B0C).
    public func readHitsCapabilities() async throws -> HitsCapabilities {
        guard let feature = try await resolveFeature(HIDPPFeatureID.analogButtons) else {
            throw HIDPPError.unsupported("此裝置沒有類比按鍵功能 (0x1B0C)")
        }
        let caps = try await request(featureIndex: feature.index, function: 0, shortFallback: true)
        guard caps.count >= 5 else {
            throw HIDPPError.malformedReport("analog button capabilities answered \(caps.count) bytes")
        }
        var buttonCount = Int(caps[1])
        // The firmware over-reports; only the two main buttons are user accessible.
        if buttonCount > 2 { buttonCount = 2 }
        var maxActuation = Int(caps[2] >> 2)
        var maxRapidTrigger = Int(caps[3] >> 2)
        var maxHaptics = Int(caps[4] >> 2)
        if maxActuation == 0 { maxActuation = 10 }
        if maxRapidTrigger == 0 { maxRapidTrigger = 5 }
        if maxHaptics == 0 { maxHaptics = 5 }
        return HitsCapabilities(
            buttonCount: buttonCount,
            maxActuation: maxActuation,
            maxRapidTrigger: maxRapidTrigger,
            maxHaptics: maxHaptics
        )
    }

    /// Reads one analog button's settings (0x1B0C).
    public func readHitsButton(_ button: Int) async throws -> HitsButtonConfig {
        guard let feature = try await resolveFeature(HIDPPFeatureID.analogButtons) else {
            throw HIDPPError.unsupported("此裝置沒有類比按鍵功能 (0x1B0C)")
        }
        let data = try await request(featureIndex: feature.index, function: 2, payload: [UInt8(button)], shortFallback: true)
        guard data.count >= 4 else {
            throw HIDPPError.malformedReport("analog button config answered \(data.count) bytes")
        }
        return HitsButtonConfig(
            button: Int(data[0]),
            actuation: Int(data[1] >> 2),
            rapidTrigger: Int(data[2] >> 2),
            haptics: Int(data[3] >> 2),
            rapidTriggerFlag: data[2] & 0x01
        )
    }

    /// Writes one analog button's settings (0x1B0C).
    ///
    /// The actuation point and the haptic strength are packed into bits 7...2. The
    /// rapid trigger byte keeps a firmware managed flag in bit 0 — but when rapid
    /// trigger is switched off the byte has to be exactly zero.
    public func setHitsButton(_ config: HitsButtonConfig, maxActuation: Int, maxRapidTrigger: Int, maxHaptics: Int) async throws {
        guard let feature = try await resolveFeature(HIDPPFeatureID.analogButtons) else {
            throw HIDPPError.unsupported("此裝置沒有類比按鍵功能 (0x1B0C)")
        }
        guard (1...max(1, min(maxActuation, 10))).contains(config.actuation) else {
            throw HIDPPError.unsupported("觸發點必須介於 1 與 \(min(maxActuation, 10))")
        }
        guard (0...max(0, min(maxRapidTrigger, 5))).contains(config.rapidTrigger) else {
            throw HIDPPError.unsupported("快速觸發必須介於 0 與 \(min(maxRapidTrigger, 5))")
        }
        guard (0...max(0, min(maxHaptics, 5))).contains(config.haptics) else {
            throw HIDPPError.unsupported("回饋強度必須介於 0 與 \(min(maxHaptics, 5))")
        }
        let actuationWire = UInt8((config.actuation & 0x3F) << 2)
        let rapidTriggerWire: UInt8 = config.rapidTrigger == 0
            ? 0
            : UInt8(((config.rapidTrigger & 0x3F) << 2) | Int(config.rapidTriggerFlag & 0x01))
        let hapticsWire = UInt8((config.haptics & 0x3F) << 2)
        _ = try await request(
            featureIndex: feature.index,
            function: 1,
            payload: [UInt8(config.button), actuationWire, rapidTriggerWire, hapticsWire]
        )
    }

    /// The draft of one HITS change.
    ///
    /// A field that is `nil` is not written. The rapid trigger is special: the
    /// getter keeps returning the last level when rapid trigger is switched off,
    /// so its state cannot be read back — it has to be chosen explicitly.
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
    }

    /// Applies a HITS draft.
    ///
    /// The current configuration is read again first, only the fields the user
    /// changed are written, and every other byte — including the firmware flag
    /// in the rapid trigger byte — survives. The rapid trigger has to be chosen
    /// explicitly, because the device does not report its state reliably.
    public func applyHits(draft: HitsDraft, maxActuation: Int, maxRapidTrigger: Int, maxHaptics: Int) async throws {
        guard !draft.isEmpty else { throw HIDPPError.unsupported("沒有任何變更") }
        guard draft.button == 0 || draft.button == 1 else {
            throw HIDPPError.unsupported("只支援左鍵與右鍵")
        }
        let current = try await readHitsButton(draft.button)
        guard current.button == draft.button else {
            throw HIDPPError.unsupported("裝置回報的按鍵索引不符")
        }
        var updated = current
        if let actuation = draft.actuation {
            guard (1...max(1, min(maxActuation, 10))).contains(actuation) else {
                throw HIDPPError.unsupported("觸發點必須介於 1 與 \(min(maxActuation, 10))")
            }
            updated.actuation = actuation
        }
        if let haptics = draft.haptics {
            guard (0...max(0, min(maxHaptics, 5))).contains(haptics) else {
                throw HIDPPError.unsupported("回饋強度必須介於 0 與 \(min(maxHaptics, 5))")
            }
            updated.haptics = haptics
        }
        if let rapidTrigger = draft.rapidTrigger {
            guard (0...max(0, min(maxRapidTrigger, 5))).contains(rapidTrigger) else {
                throw HIDPPError.unsupported("快速觸發必須介於 0 與 \(min(maxRapidTrigger, 5))")
            }
            updated.rapidTrigger = rapidTrigger
        } else {
            // Without an explicit choice the rapid trigger byte would be rewritten
            // with a cached level, which could switch it on by accident.
            throw HIDPPError.unsupported("快速觸發的狀態無法讀回，請先明確選擇關閉或一個數值")
        }
        try await setHitsButton(updated, maxActuation: maxActuation, maxRapidTrigger: maxRapidTrigger, maxHaptics: maxHaptics)
        // Read back: only the fields that were written may have changed.
        let verify = try await readHitsButton(draft.button)
        if let rapidTrigger = draft.rapidTrigger, rapidTrigger > 0, verify.rapidTrigger != rapidTrigger {
            throw HIDPPError.unsupported("快速觸發等級讀回不一致（\(verify.rapidTrigger)）")
        }
        if let actuation = draft.actuation, verify.actuation != actuation {
            throw HIDPPError.unsupported("觸發點讀回不一致（\(verify.actuation)）")
        }
        if let haptics = draft.haptics, verify.haptics != haptics {
            throw HIDPPError.unsupported("回饋強度讀回不一致（\(verify.haptics)）")
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
                throw HIDPPError.unsupported("DPI 清單的區間標記沒有步進值")
            }
            guard index + 1 < words.count, let start = values.last else {
                throw HIDPPError.unsupported("DPI 清單的區間標記缺少起點")
            }
            let end = words[index + 1]
            guard (100...44_000).contains(end) else {
                throw HIDPPError.unsupported("DPI 區間終點超出範圍 \(end)")
            }
            guard end > start else {
                throw HIDPPError.unsupported("DPI 清單的區間是遞減的")
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
            throw HIDPPError.unsupported("DPI 清單含有超出範圍的值 \(word)")
        }
        values.append(word)
        index += 1
    }
    guard values.count > 1 else { return values }
    for position in 1..<values.count where values[position] <= values[position - 1] {
        throw HIDPPError.unsupported("DPI 清單不是遞增的")
    }
    return values
}
