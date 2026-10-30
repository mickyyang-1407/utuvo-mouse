import Foundation
import CryptoKit
import UTUVOMouseLocalization

/// The two mice this app drives.
public enum MouseModel: String, Sendable, CaseIterable {
    case mxMaster4 = "MX Master 4 M"
    case superstrike = "PRO X2 SUPERSTRIKE"
    case receiver = "LIGHTSPEED 接收器"
    case unknown = "未知型號"
}

/// Product IDs verified for the configuration paths in this app.
public enum MouseIdentification {
    public static let logitechVendorID = 0x046D
    public static let mxMaster4 = 0xB042
    public static let superstrike = 0xC0A8
    public static let lightspeedReceiver = 0xC54D

    /// Shared features never establish a model. The receiver's own PID is not
    /// the paired mouse's identity; a complete device-name reply is required.
    public static func model(vendorID: Int, productID: Int, pairedDeviceName: String? = nil) -> MouseModel {
        guard vendorID == logitechVendorID else { return .unknown }
        switch productID {
        case mxMaster4: return .mxMaster4
        case superstrike: return .superstrike
        case lightspeedReceiver:
            guard let name = cleanName(pairedDeviceName) else { return .receiver }
            let normalized = name.uppercased().replacingOccurrences(of: " ", with: "")
            return normalized == "PROX2SUPERSTRIKE" ? .superstrike : .unknown
        default: return .unknown
        }
    }

    public static func cleanName(_ name: String?) -> String? {
        guard let name else { return nil }
        let value = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty, value.utf8.count <= 128,
              !value.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) }) else { return nil }
        return value
    }
}

public extension MouseModel {
    var supportsConfiguration: Bool { self == .mxMaster4 || self == .superstrike }
}

/// How a device is connected.
public enum DeviceTransportKind: String, Sendable {
    case bluetooth = "Bluetooth"
    case usb = "USB"
    case receiver = "LIGHTSPEED 接收器"
    case unknown = "未知"
}

public extension MouseModel {
    func displayTitle(language: MouseLanguage) -> String {
        switch self {
        case .mxMaster4, .superstrike: rawValue
        case .receiver: MouseLocalizer(language: language).string("model.receiver")
        case .unknown: MouseLocalizer(language: language).string("model.unknown")
        }
    }
}

public extension DeviceTransportKind {
    func displayTitle(language: MouseLanguage) -> String {
        switch self {
        case .bluetooth, .usb: rawValue
        case .receiver: MouseLocalizer(language: language).string("transport.receiver")
        case .unknown: MouseLocalizer(language: language).string("transport.unknown")
        }
    }
}

/// Identity of one physical mouse.
///
/// The stable identifier is a one way hash: the serial number and the Bluetooth
/// address never leave the app.
public struct DeviceIdentity: Sendable, Equatable {
    public var stableID: String
    public var model: MouseModel
    public var vendorID: Int
    public var productID: Int
    public var transport: DeviceTransportKind
    /// The HID++ device index this device answers on (0xFF direct, 1...6 receiver slot).
    public var deviceIndex: UInt8
    public var productName: String

    public init(
        stableID: String,
        model: MouseModel,
        vendorID: Int,
        productID: Int,
        transport: DeviceTransportKind,
        deviceIndex: UInt8,
        productName: String
    ) {
        self.stableID = stableID
        self.model = model
        self.vendorID = vendorID
        self.productID = productID
        self.transport = transport
        self.deviceIndex = deviceIndex
        self.productName = productName
    }
}

public extension DeviceIdentity {
    func displayName(language: MouseLanguage) -> String {
        if model.supportsConfiguration { return model.displayTitle(language: language) }
        return MouseIdentification.cleanName(productName) ?? model.displayTitle(language: language)
    }
}

/// Builds stable, non reversible device identifiers.
public enum StableIdentifier {
    public static func make(vendorID: Int, productID: Int, seed: String) -> String {
        let digest = SHA256.hash(data: Data("\(vendorID):\(productID):\(seed)".utf8))
        let hex = digest.prefix(8).map { String(format: "%02x", $0) }.joined()
        return "sha256:" + hex
    }
}

/// Everything the app knows about one mouse at one moment.
///
/// Values that could not be read stay `nil` — they are never filled with defaults.
public struct DeviceSnapshot: Sendable, Equatable, Identifiable {
    public var id: String
    public var identity: DeviceIdentity
    /// Feature identifiers the device exposes, mapped to their runtime index.
    public var features: [UInt16: UInt8] = [:]
    public var battery: BatteryStatus = .unknown
    public var dpi: DPIState?
    public var smartShift: SmartShiftState?
    public var wheel: WheelState?
    public var hitsCapabilities: HitsCapabilities?
    /// Intersection of both sensor axes, for symmetric DPI controls.
    public var supportedProfileDPI: [Int] = []
    public var hitsButtons: [HitsButtonConfig] = []
    /// The running onboard profile (Superstrike).
    public var profile: ProfileSector?
    /// The onboard memory plan of a Superstrike.
    public var plan: SuperstrikePlan?
    /// The raw reply of the onboard memory info (fn0).
    public var onboardInfoRaw: [UInt8] = []
    /// The HID++ protocol version the device reported.
    public var protocolVersion: String?
    /// The programmable controls of a mouse (0x1B04).
    public var reprogControls: [ReprogramControl] = []
    /// True when the device answered and every value of this snapshot could be
    /// read. A partial read is not a known state.
    public var isStateAuthoritative: Bool = false
    /// The transport instance this snapshot came from. It changes on a hot plug.
    public var connectionEpoch: UUID?
    /// Set when the device could not be opened, for example because macOS denied
    /// the access. The row stays visible with the reason.
    public var accessError: String?
    /// True when the device needs the Input Monitoring permission.
    public var needsInputMonitoring: Bool = false
    /// 1 = onboard, 2 = host control.
    public var onboardMode: Int?
    /// Problems that happened while reading this device.
    public var issues: [String] = []
    /// True when the values come from the demo data set, not from a device.
    public var isDemo: Bool = false

    public init(identity: DeviceIdentity, features: [UInt16: UInt8] = [:]) {
        self.id = identity.stableID
        self.identity = identity
        self.features = features
    }

    /// Minimum complete state needed before a refresh can resolve uncertainty.
    /// A valid ping or a different, partially read profile is insufficient.
    public var hasCompleteState: Bool {
        guard protocolVersion != nil, !features.isEmpty, accessError == nil else { return false }
        switch identity.model {
        case .mxMaster4:
            guard let dpi, let current = dpi.current, dpi.available.contains(current) else { return false }
            if features[HIDPPFeatureID.smartShiftEnhanced] != nil || features[HIDPPFeatureID.smartShift] != nil {
                guard let state = smartShift, let mode = state.mode, [1, 2].contains(mode), state.threshold != nil else { return false }
            }
            if features[HIDPPFeatureID.wheelControl] != nil, wheel?.modeByte == nil { return false }
        case .superstrike:
            guard let plan, let profile,
                  [1, 2].contains(plan.mode),
                  plan.info.memoryModel == SuperstrikeService.supportedMemoryModel,
                  plan.info.profileFormat == SuperstrikeService.supportedProfileFormat,
                  plan.info.sectorSize == SuperstrikeService.supportedSectorSize,
                  (!plan.isRunning || plan.activeDPIIndex != nil),
                  plan.controlBytes.count == plan.info.sectorSize,
                  ProfileSector(bytes: plan.controlBytes, sector: 0).hasValidCRC,
                  profile.bytes.count == plan.info.sectorSize,
                  profile.sector == plan.storedSector,
                  (100...ProfileLayout.maximumDPI).contains(profile.dpiX),
                  (100...ProfileLayout.maximumDPI).contains(profile.dpiY),
                  ProfileLayout.reportRates.contains(profile.reportRateHz),
                  profile.hasValidCRC else { return false }
            if features[HIDPPFeatureID.analogButtons] != nil {
                guard let caps = hitsCapabilities, caps.buttonCount > 0,
                      hitsButtons.count == caps.buttonCount,
                      Set(hitsButtons.map(\.button)) == Set(0..<caps.buttonCount) else { return false }
            }
        case .receiver, .unknown:
            return false
        }
        return true
    }
}
