import Foundation
import UTUVOMouseLocalization

/// HID++ report identifiers (byte 0 of every report).
public enum HIDPPReportID: UInt8, Sendable, CaseIterable {
    /// Short report: 7 bytes on the wire.
    case short = 0x10
    /// Long report: 20 bytes on the wire.
    case long = 0x11

    /// Total byte count of a report with this identifier.
    public var reportLength: Int {
        switch self {
        case .short: 7
        case .long: 20
        }
    }

    /// Number of payload bytes carried by a report (everything after the 4 byte header).
    public var payloadLength: Int {
        switch self {
        case .short: 3
        case .long: 16
        }
    }
}

/// Software identifier used in the low nibble of byte 3.
///
/// Requests carry 1...15. A device sends 0 in its own notifications, so a report
/// with software ID 0 is an event and never a reply to one of our requests.
public enum HIDPPSoftwareID {
    /// This application's identifier inside requests.
    public static let application: UInt8 = 0x0A
    /// Identifier a device uses for asynchronous notifications.
    public static let device: UInt8 = 0x00
    public static let isValidForRequests: Bool = { (1...15).contains(application) }()
}

/// Marker that occupies byte 2 of an error reply.
///
/// An error reply does not carry a payload: byte 3 repeats the feature index of
/// the failed request, byte 4 repeats its function and software ID, byte 5 holds
/// the reason code.
public enum HIDPPErrorMarker: UInt8, Sendable {
    /// HID++ 1.0 style error reply.
    case hidpp1 = 0x8F
    /// HID++ 2.0 style error reply.
    case hidpp2 = 0xFF
}

/// Well-known HID++ 2.0 feature identifiers.
public enum HIDPPFeatureID {
    public static let root: UInt16 = 0x0000
    public static let featureSet: UInt16 = 0x0001
    public static let deviceName: UInt16 = 0x0005
    public static let unifiedBattery: UInt16 = 0x1004
    public static let specialKeysAndMSEButtons: UInt16 = 0x1B04
    public static let analogButtons: UInt16 = 0x1B0C
    public static let smartShift: UInt16 = 0x2110
    public static let smartShiftEnhanced: UInt16 = 0x2111
    public static let wheelControl: UInt16 = 0x2121
    public static let adjustableDPI: UInt16 = 0x2201
    public static let extendedAdjustableDPI: UInt16 = 0x2202
    public static let extendedReportRate: UInt16 = 0x8061
    public static let onboardProfiles: UInt16 = 0x8100
}

/// A feature as reported by the root feature (0x0000).
public struct HIDPPFeature: Hashable, Sendable {
    /// The 16 bit feature identifier (for example `0x2201`).
    public let id: UInt16
    /// The per-device index used in reports (0...255). 0 means "not present".
    public let index: UInt8
    /// Feature version reported by the device.
    public let version: UInt8
    /// Feature flags reported by the device (obsolete / hidden / engineering).
    public let flags: UInt8

    public init(id: UInt16, index: UInt8, version: UInt8, flags: UInt8 = 0) {
        self.id = id
        self.index = index
        self.version = version
        self.flags = flags
    }
}

/// Errors raised by the HID++ layer.
public enum HIDPPError: Error, Equatable, Sendable, LocalizedError {
    case malformedReport(String)
    case timeout(featureIndex: UInt8, function: UInt8)
    case deviceError(reason: UInt8)
    case transportFailure(String)
    case unsupported(String)
    case localized(key: String, arguments: [String])

    public var errorDescription: String? {
        switch self {
        case .malformedReport(let detail):
            "回應格式不正確：\(detail)"
        case .timeout:
            "等待回應逾時"
        case .deviceError(let reason):
            "裝置回報錯誤：\(HIDPPErrorCode.reason(reason))"
        case .transportFailure(let detail):
            "傳輸失敗：\(detail)"
        case .unsupported(let detail):
            "不支援：\(detail)"
        case .localized(let key, let arguments):
            MouseLocalizer(language: .traditionalChinese).string(key, arguments: arguments)
        }
    }

    public func localizedMessage(language: MouseLanguage) -> String {
        let text = MouseLocalizer(language: language)
        return switch self {
        case .malformedReport(let detail): text.string("error.hidpp.malformed", arguments: [detail])
        case .timeout(let feature, let function):
            text.string("error.hidpp.timeout", arguments: [String(format: "0x%02X", feature), String(format: "0x%02X", function)])
        case .deviceError(let reason): text.string("error.hidpp.device", arguments: [HIDPPErrorCode.localizedReason(reason, language: language)])
        case .transportFailure(let detail): text.string("error.hidpp.transport", arguments: [detail])
        case .unsupported(let detail): text.string("error.hidpp.unsupported", arguments: [detail])
        case .localized(let key, let arguments): text.string(key, arguments: arguments)
        }
    }
}

/// Names for the HID++ error reason code (byte 5 of an error reply).
public enum HIDPPErrorCode {
    public static func localizedReason(_ code: UInt8, language: MouseLanguage) -> String {
        let key: String
        switch code {
        case 0x00: key = "error.hidpp.reason.ok"
        case 0x01: key = "error.hidpp.reason.unknown"
        case 0x02: key = "error.hidpp.reason.parameter"
        case 0x03: key = "error.hidpp.reason.range"
        case 0x04: key = "error.hidpp.reason.hardware"
        case 0x05: key = "error.hidpp.reason.internal"
        case 0x06: key = "error.hidpp.reason.index"
        case 0x07: key = "error.hidpp.reason.feature"
        case 0x08: key = "error.hidpp.reason.busy"
        case 0x09: key = "error.hidpp.reason.unsupported"
        default: return String(format: "0x%02X", code)
        }
        return MouseLocalizer(language: language).string(key)
    }

    public static func reason(_ code: UInt8) -> String {
        switch code {
        case 0x00: "無錯誤"
        case 0x01: "未知錯誤"
        case 0x02: "參數無效"
        case 0x03: "超出範圍"
        case 0x04: "硬體錯誤"
        case 0x05: "Logitech 內部錯誤"
        case 0x06: "無效的功能索引"
        case 0x07: "無效的功能代碼"
        case 0x08: "裝置忙碌"
        case 0x09: "不支援此操作"
        default: "未知錯誤 0x\(String(code, radix: 16, uppercase: true))"
        }
    }
}
