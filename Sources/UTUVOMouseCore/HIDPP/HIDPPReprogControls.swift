import Foundation

/// One programmable control of a mouse (feature 0x1B04).
///
/// The control ID alone does not tell what a button is — the capability flags
/// do. The known identifiers of the MX Master 4 M are 0x50 / 0x51 for the two
/// main buttons (never diverted), 0x52 middle, 0x53 back and 0x56 forward, but
/// only the flags are evidence.
public struct ReprogramControl: Sendable, Equatable, Identifiable {
    /// The index of the control in the device's control list.
    public let index: Int
    /// The control identifier.
    public let cid: UInt16
    /// The default task associated with the control.
    public let taskID: UInt16
    /// The capability flags: byte 4 of the reply plus byte 8 shifted up.
    public let flags: UInt16
    /// The device reported physical position.
    public let position: UInt8
    /// The device reported group number.
    public let group: UInt8
    /// The group membership mask.
    public let groupMask: UInt8

    public var id: Int { index }

    public init(index: Int, cid: UInt16, taskID: UInt16, flags: UInt16, position: UInt8, group: UInt8, groupMask: UInt8) {
        self.index = index
        self.cid = cid
        self.taskID = taskID
        self.flags = flags
        self.position = position
        self.group = group
        self.groupMask = groupMask
    }

    /// Bit 0: a mouse or pointer control.
    public var isMouse: Bool { flags & (1 << 0) != 0 }
    /// Bit 4: the control can be reprogrammed.
    public var isReprogrammable: Bool { flags & (1 << 4) != 0 }
    /// Bit 5: the control can be diverted temporarily.
    public var isDivertable: Bool { flags & (1 << 5) != 0 }
    /// Bit 6: the control can be diverted persistently.
    public var isPersistentlyDivertable: Bool { flags & (1 << 6) != 0 }
    /// Bit 7: the control is virtual, not a physical button.
    public var isVirtual: Bool { flags & (1 << 7) != 0 }

    /// The two main buttons of the mouse. They are never diverted.
    public var isMainButton: Bool { cid == 0x0050 || cid == 0x0051 }

    /// A control this app is allowed to divert.
    public var isDivertCandidate: Bool { isDivertable && !isVirtual && !isMainButton }

    /// A short description for the interface.
    public var summary: String {
        var parts: [String] = ["控制 ID \(String(cid, radix: 16, uppercase: true))"]
        if isMouse { parts.append("滑鼠鍵") }
        if isDivertable { parts.append("可改道") }
        if isPersistentlyDivertable { parts.append("可永久改道") }
        if isVirtual { parts.append("虛擬鍵") }
        if isMainButton { parts.append("主鍵，不改道") }
        return parts.joined(separator: "・")
    }
}

/// The reporting state of one control (feature 0x1B04, fn2).
public struct ControlReporting: Sendable, Equatable {
    public var cid: UInt16
    /// The reporting flags byte of the reply.
    public var flags: UInt8
    /// The control the device remaps to, 0 when none.
    public var remappedCID: UInt16
    /// The extended flags byte of the reply.
    public var extendedFlags: UInt8
    /// The raw reply, kept for the diagnostics.
    public var raw: [UInt8]

    /// Bit 0: the control is temporarily diverted.
    public var isTemporarilyDiverted: Bool { flags & 0b0000_0001 != 0 }
    /// Bit 2: the control is persistently diverted.
    public var isPersistentlyDiverted: Bool { flags & 0b0000_0100 != 0 }

    public init(cid: UInt16, flags: UInt8, remappedCID: UInt16, extendedFlags: UInt8, raw: [UInt8]) {
        self.cid = cid
        self.flags = flags
        self.remappedCID = remappedCID
        self.extendedFlags = extendedFlags
        self.raw = raw
    }
}

/// The change of the temporary diversion of one control (feature 0x1B04, fn3).
///
/// Only the temporary diversion is ever touched: the persistent state, the raw
/// XY state and the remap target stay exactly as the device had them.
public enum TemporaryDiversion: Sendable, Equatable {
    case enable
    case disable

    /// The change byte: bit 1 marks the temporary value as valid, bit 0 carries
    /// the value itself.
    public var changeByte: UInt8 {
        switch self {
        case .enable: 0b0000_0011
        case .disable: 0b0000_0010
        }
    }
}

/// Reads the programmable controls of a mouse (feature 0x1B04).
public struct ReprogramControlsClient: Sendable {
    public let client: HIDPPClient
    public let feature: HIDPPFeature

    public init(client: HIDPPClient, feature: HIDPPFeature) {
        self.client = client
        self.feature = feature
    }

    public static func resolve(for client: HIDPPClient) async throws -> ReprogramControlsClient? {
        guard let feature = try await client.resolveFeature(HIDPPFeatureID.specialKeysAndMSEButtons) else { return nil }
        return ReprogramControlsClient(client: client, feature: feature)
    }

    /// The number of controls the device implements (fn0).
    public func readControlCount() async throws -> Int {
        let data = try await client.request(featureIndex: feature.index, function: 0, shortFallback: true)
        guard let count = data.first else {
            throw HIDPPError.malformedReport("control count answered \(data.count) bytes")
        }
        return Int(count)
    }

    /// The information about one control (fn1).
    ///
    /// The reply holds the control ID, its task ID, the capability flags, the
    /// position, the group, the group mask and one more byte of flags.
    public func readControlInfo(index: Int) async throws -> ReprogramControl {
        let data = try await client.request(featureIndex: feature.index, function: 1, payload: [UInt8(index)], shortFallback: true)
        guard data.count >= 9 else {
            throw HIDPPError.malformedReport("control info answered \(data.count) bytes")
        }
        let cid = (UInt16(data[0]) << 8) | UInt16(data[1])
        let taskID = (UInt16(data[2]) << 8) | UInt16(data[3])
        let flags = UInt16(data[4]) | (UInt16(data[8]) << 8)
        return ReprogramControl(
            index: index,
            cid: cid,
            taskID: taskID,
            flags: flags,
            position: data[5],
            group: data[6],
            groupMask: data[7]
        )
    }

    /// Every control the device implements.
    public func readControls() async throws -> [ReprogramControl] {
        let count = try await readControlCount()
        guard (1...32).contains(count) else {
            throw HIDPPError.malformedReport("unsupported control count \(count)")
        }
        var controls: [ReprogramControl] = []
        for index in 0..<count {
            controls.append(try await readControlInfo(index: index))
        }
        return controls
    }

    /// The reporting state of one control (fn2).
    public func readReporting(cid: UInt16) async throws -> ControlReporting {
        let data = try await client.request(
            featureIndex: feature.index,
            function: 2,
            payload: [UInt8(truncatingIfNeeded: cid >> 8), UInt8(truncatingIfNeeded: cid), 0x00],
            shortFallback: true
        )
        guard data.count >= 3 else {
            throw HIDPPError.malformedReport("control reporting answered \(data.count) bytes")
        }
        let echoed = (UInt16(data[0]) << 8) | UInt16(data[1])
        guard echoed == cid else {
            throw HIDPPError.unsupported("裝置回報的控制 ID 與請求不符")
        }
        let remapped = data.count >= 5 ? (UInt16(data[3]) << 8) | UInt16(data[4]) : 0
        return ControlReporting(
            cid: cid,
            flags: data[2],
            remappedCID: remapped,
            extendedFlags: data.count >= 6 ? data[5] : 0,
            raw: Array(data.prefix(8))
        )
    }

    /// Changes the temporary diversion of one control (fn3).
    ///
    /// The payload carries the change byte, a remap target of `0x0000` (which
    /// keeps the current remap) and the extended change byte. Every validity bit
    /// other than the temporary one stays zero, so the persistent state and the
    /// raw XY state are preserved.
    @discardableResult
    public func writeTemporaryDiversion(cid: UInt16, change: TemporaryDiversion) async throws -> [UInt8] {
        var payload: [UInt8] = [
            UInt8(truncatingIfNeeded: cid >> 8),
            UInt8(truncatingIfNeeded: cid),
            change.changeByte,
            0x00,  // remap: 0x0000 keeps the current remap
            0x00,
            0x00,  // extended changes: nothing valid, nothing changes
        ]
        payload.append(contentsOf: repeatElement(0, count: 16 - payload.count))
        return try await client.request(featureIndex: feature.index, function: 3, payload: payload)
    }

    /// The controls that are currently pressed, from a notification frame.
    ///
    /// Only the first eight bytes of the payload are used: four big endian
    /// control IDs. A zero ID marks an unused slot and is ignored.
    public static func pressedControls(in payload: [UInt8]) -> [UInt16] {
        var controls: [UInt16] = []
        var index = 0
        while index + 1 < payload.count, index < 8, controls.count < 4 {
            let cid = (UInt16(payload[index]) << 8) | UInt16(payload[index + 1])
            if cid != 0x0000 { controls.append(cid) }
            index += 2
        }
        return controls
    }
}
