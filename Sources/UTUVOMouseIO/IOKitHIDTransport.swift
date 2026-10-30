import Foundation
import IOKit
import IOKit.hid
import UTUVOMouseCore
import UTUVOMouseLocalization

/// Facts about one HID interface, read from the IORegistry.
public struct HIDInterfaceDescriptor: Hashable, Sendable {
    public var vendorID: Int
    public var productID: Int
    public var transport: String
    public var usagePage: Int
    public var usage: Int
    public var locationID: Int
    public var serialNumber: String
    public var productName: String
    public var registryID: UInt64

    public init(device: IOHIDDevice) {
        func int(_ key: String) -> Int {
            (IOHIDDeviceGetProperty(device, key as CFString) as? NSNumber)?.intValue ?? 0
        }
        func string(_ key: String) -> String {
            (IOHIDDeviceGetProperty(device, key as CFString) as? String) ?? ""
        }
        vendorID = int(kIOHIDVendorIDKey)
        productID = int(kIOHIDProductIDKey)
        transport = string(kIOHIDTransportKey)
        usagePage = int(kIOHIDPrimaryUsagePageKey)
        usage = int(kIOHIDPrimaryUsageKey)
        locationID = int(kIOHIDLocationIDKey)
        serialNumber = string(kIOHIDSerialNumberKey)
        productName = string(kIOHIDProductKey)
        registryID = Self.registryEntryID(of: device)
    }

    /// A vendor defined collection carries HID++ on its own.
    public var isVendorCollection: Bool { usagePage == 0xFF00 || usagePage == 0xFF43 }

    /// The generic mouse collection. On a Bluetooth mouse it also carries HID++.
    public var isMouseCollection: Bool { usagePage == 0x01 && usage == 0x02 }

    /// One physical device may publish several interfaces; they share this key.
    public var physicalKey: String {
        serialNumber.isEmpty ? "loc-\(locationID)-\(productID)" : "ser-\(serialNumber)"
    }

    public var transportKind: DeviceTransportKind {
        let name = transport.lowercased()
        if name.hasPrefix("bluetooth") { return .bluetooth }
        if name == "usb" { return productID == TargetProducts.receiver ? .receiver : .usb }
        return .unknown
    }

    static func registryEntryID(of device: IOHIDDevice) -> UInt64 {
        let service = IOHIDDeviceGetService(device)
        guard service != 0 else { return 0 }
        var entryID: UInt64 = 0
        guard IORegistryEntryGetRegistryEntryID(service, &entryID) == KERN_SUCCESS else { return 0 }
        return entryID
    }
}

/// The product identifiers this app is allowed to open.
public enum TargetProducts {
    /// MX Master 4 M over Bluetooth.
    public static let mxMaster4 = 0xB042
    /// PRO X2 SUPERSTRIKE over a direct USB cable.
    public static let superstrikeDirect = 0xC0A8
    /// LIGHTSPEED receiver that can host the Superstrike.
    public static let receiver = 0xC54D

    public static let allowed: Set<Int> = [mxMaster4, superstrikeDirect, receiver]
}

/// A run loop on a dedicated thread.
///
/// The HID system only enumerates devices when the manager is scheduled on the
/// main run loop, so the app uses the main run loop for the HID callbacks and
/// keeps every wait for a reply off the main actor.
@available(*, deprecated, message: "The HID manager has to run on the main run loop")
public final class HIDRunLoop: @unchecked Sendable {
    public init() {}
}

/// HID++ over one IOHID interface.
///
/// The device is opened without seizing it, so the mouse keeps working normally
/// and no input is intercepted.
public final class IOKitHIDTransport: HIDPPTransport, @unchecked Sendable {
    private static let bufferSize = 64

    public let descriptor: HIDInterfaceDescriptor
    /// A unique token for this transport instance. The registry entry id can be
    /// reused after a hot plug, this token cannot.
    public let connectionToken = UUID()
    private let device: IOHIDDevice
    private let buffer: UnsafeMutablePointer<UInt8>
    private let lock = NSLock()
    private var handler: (@Sendable ([UInt8]) -> Void)?
    private var isOpen = false
    private var receiverAnnounced = false

    public init(device: IOHIDDevice) {
        self.device = device
        self.descriptor = HIDInterfaceDescriptor(device: device)
        buffer = .allocate(capacity: Self.bufferSize)
        buffer.initialize(repeating: 0, count: Self.bufferSize)
    }

    deinit {
        close()
        buffer.deinitialize(count: Self.bufferSize)
        buffer.deallocate()
    }

    /// Opens the interface. A permission problem is reported, never worked around.
    public func open() throws {
        try lock.withLock {
            guard !isOpen else { return }
            let result = IOHIDDeviceOpen(device, IOOptionBits(kIOHIDOptionsTypeNone))
            guard result == kIOReturnSuccess else {
                throw IOKitHIDError.openFailed(UInt32(bitPattern: result))
            }
            isOpen = true
            let context = Unmanaged.passUnretained(self).toOpaque()
            IOHIDDeviceRegisterInputReportCallback(
                device,
                buffer,
                Self.bufferSize,
                { context, _, _, _, reportID, report, length in
                    guard let context else { return }
                    let transport = Unmanaged<IOKitHIDTransport>.fromOpaque(context).takeUnretainedValue()
                    transport.deliver(reportID: reportID, report: report, length: length)
                },
                context
            )
        }
    }

    /// Closes the interface while the device is still present.
    public func close() {
        lock.withLock {
            guard isOpen else { return }
            isOpen = false
            IOHIDDeviceRegisterInputReportCallback(device, buffer, Self.bufferSize, nil, nil)
            IOHIDDeviceClose(device, IOOptionBits(kIOHIDOptionsTypeNone))
        }
    }

    public func send(_ bytes: [UInt8]) throws {
        guard let reportID = bytes.first else {
            throw HIDPPError.localized(key: "error.transport.emptyReport", arguments: [])
        }
        let result = bytes.withUnsafeBufferPointer { pointer -> IOReturn in
            guard let base = pointer.baseAddress else { return IOReturn(bitPattern: 0xE00002C2) }
            return IOHIDDeviceSetReport(device, kIOHIDReportTypeOutput, CFIndex(reportID), base, pointer.count)
        }
        guard result == kIOReturnSuccess else {
            throw HIDPPError.localized(
                key: "error.transport.setReport",
                arguments: [String(format: "0x%08X", UInt32(bitPattern: result))]
            )
        }
    }

    /// Requests paired-device arrival notifications once per receiver connection.
    /// This changes no pairing or mouse setting. A sleeping mouse may still be absent.
    public func announceReceiverIfNeeded(force: Bool = false) async throws {
        guard descriptor.productID == TargetProducts.receiver else { return }
        let needed = lock.withLock { force || !receiverAnnounced }
        guard needed else { return }
        try send([0x10, 0xFF, 0x80, 0x02, 0x02, 0x00, 0x00])
        lock.withLock { receiverAnnounced = true }
        try await Task.sleep(for: .milliseconds(400))
    }

    public func setReportHandler(_ handler: @escaping @Sendable ([UInt8]) -> Void) {
        lock.withLock { self.handler = handler }
    }

    private func deliver(reportID: UInt32, report: UnsafeMutablePointer<UInt8>, length: CFIndex) {
        guard length > 0, length <= Self.bufferSize else { return }
        let leadingIsHIDPP = HIDPPReportID(rawValue: report[0]) != nil
        let headerIsHIDPP = UInt8(exactly: reportID).flatMap(HIDPPReportID.init(rawValue:)) != nil
        // Pointer and wheel reports share this interface; drop them before copying.
        guard leadingIsHIDPP || headerIsHIDPP else { return }
        var bytes = Array(UnsafeBufferPointer(start: report, count: length))
        // Some interfaces deliver the report without its identifier.
        if !leadingIsHIDPP, let id = UInt8(exactly: reportID) {
            bytes.insert(id, at: 0)
        }
        let handler = lock.withLock { self.handler }
        handler?(bytes)
    }
}

/// Errors of the IOKit layer.
public enum IOKitHIDError: Error, Equatable, Sendable, LocalizedError {
    case openFailed(UInt32)
    case notPermitted

    public var errorDescription: String? {
        switch self {
        case .openFailed(let code):
            // kIOReturnNotPermitted / kIOReturnNotPrivileged.
            if code == 0xE000_02E2 || code == 0xE000_02C1 {
                return "macOS 拒絕存取此 HID 裝置。請在「系統設定 → 隱私權與安全性 → 輸入監控」允許本 App。"
            }
            return String(format: "無法開啟 HID 裝置（IOReturn 0x%08X）", code)
        case .notPermitted:
            return "macOS 拒絕存取此 HID 裝置。"
        }
    }

    public var accessFailure: HIDAccessFailure {
        switch self {
        case .notPermitted: .inputMonitoringRequired
        case .openFailed(let code) where code == 0xE000_02E2 || code == 0xE000_02C1: .inputMonitoringRequired
        case .openFailed(let code): .openFailed(code)
        }
    }
}

public enum HIDAccessFailure: Equatable, Sendable {
    case inputMonitoringRequired
    case openFailed(UInt32)
    case unavailable

    public var requiresInputMonitoring: Bool {
        if case .inputMonitoringRequired = self { return true }
        return false
    }

    public func message(language: MouseLanguage) -> String {
        let localizer = MouseLocalizer(language: language)
        return switch self {
        case .inputMonitoringRequired:
            localizer.string("device.permission.denied")
        case .openFailed(let code):
            localizer.string("device.hid.openFailed", arguments: [String(format: "0x%08X", code)])
        case .unavailable:
            localizer.string("device.hid.unavailable")
        }
    }
}

/// Finds the two supported Logitech mice and keeps their HID++ interfaces open.
///
/// The manager itself is never opened — only the interfaces of the target
/// devices are opened, one by one, so no unrelated Logitech device is touched
/// and no system wide permission prompt is raised.
public final class LogitechHIDService: @unchecked Sendable {
    public static let logitechVendorID = 0x046D

    private let manager: IOHIDManager
    private let lock = NSLock()
    private var transports: [String: IOKitHIDTransport] = [:]
    private var changeHandler: (@Sendable ([IOKitHIDTransport]) -> Void)?
    private var errorHandler: (@Sendable (HIDInterfaceDescriptor, HIDAccessFailure) -> Void)?
    private var isRunning = false

    public init() {
        manager = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
    }

    deinit { stop() }

    /// Called whenever the set of open interfaces changes.
    public func onDevicesChanged(_ handler: @escaping @Sendable ([IOKitHIDTransport]) -> Void) {
        lock.withLock { changeHandler = handler }
    }

    /// Called when an interface could not be opened.
    public func onError(_ handler: @escaping @Sendable (HIDInterfaceDescriptor, HIDAccessFailure) -> Void) {
        lock.withLock { errorHandler = handler }
    }

    public var devices: [IOKitHIDTransport] {
        lock.withLock { Array(transports.values) }
    }

    public func start() {
        lock.withLock {
            guard !isRunning else { return }
            isRunning = true
        }
        // The HID system only enumerates devices when the manager is scheduled on
        // the main run loop; the requests themselves wait off the main actor.
        // Only the two supported mice and their receiver are matched, and only
        // the collections that carry HID++:
        //  - the vendor collection (usage page 0xFF00 / 0xFF43) of the Superstrike
        //    and of the LIGHTSPEED receiver,
        //  - the mouse collection of the Bluetooth mouse, which carries HID++
        //    inside it.
        // The matching uses the *primary* usage page: this macOS does not publish
        // a device level usage page, so a device level criterion matches nothing.
        let criteria: [[String: Any]] = [
            [kIOHIDVendorIDKey: Self.logitechVendorID, kIOHIDProductIDKey: TargetProducts.superstrikeDirect, kIOHIDPrimaryUsagePageKey: 0xFF00],
            [kIOHIDVendorIDKey: Self.logitechVendorID, kIOHIDProductIDKey: TargetProducts.superstrikeDirect, kIOHIDPrimaryUsagePageKey: 0xFF43],
            [kIOHIDVendorIDKey: Self.logitechVendorID, kIOHIDProductIDKey: TargetProducts.receiver, kIOHIDPrimaryUsagePageKey: 0xFF00],
            [kIOHIDVendorIDKey: Self.logitechVendorID, kIOHIDProductIDKey: TargetProducts.mxMaster4, kIOHIDPrimaryUsagePageKey: 0xFF43],
            [kIOHIDVendorIDKey: Self.logitechVendorID, kIOHIDProductIDKey: TargetProducts.mxMaster4, kIOHIDPrimaryUsagePageKey: 0x01, kIOHIDPrimaryUsageKey: 0x02],
        ]
        IOHIDManagerSetDeviceMatchingMultiple(manager, criteria as CFArray)

        let context = Unmanaged.passUnretained(self).toOpaque()
        IOHIDManagerRegisterDeviceMatchingCallback(manager, { context, _, _, device in
            guard let context else { return }
            Unmanaged<LogitechHIDService>.fromOpaque(context).takeUnretainedValue().handleMatch(device)
        }, context)
        IOHIDManagerRegisterDeviceRemovalCallback(manager, { context, _, _, device in
            guard let context else { return }
            Unmanaged<LogitechHIDService>.fromOpaque(context).takeUnretainedValue().handleRemoval(device)
        }, context)

        // The HID system only enumerates devices when the manager is scheduled on
        // the main run loop; the requests themselves wait off the main actor.
        IOHIDManagerScheduleWithRunLoop(manager, CFRunLoopGetMain(), CFRunLoopMode.commonModes.rawValue)
    }

    public func stop() {
        lock.withLock {
            guard isRunning else { return }
            isRunning = false
        }
        IOHIDManagerUnscheduleFromRunLoop(manager, CFRunLoopGetMain(), CFRunLoopMode.commonModes.rawValue)
        for transport in lock.withLock({ Array(transports.values) }) {
            transport.close()
        }
        lock.withLock { transports.removeAll() }
    }

    private func handleMatch(_ device: IOHIDDevice) {
        let descriptor = HIDInterfaceDescriptor(device: device)
        guard descriptor.vendorID == Self.logitechVendorID else { return }
        guard TargetProducts.allowed.contains(descriptor.productID) else { return }
        // Only the vendor collection of the target devices, and the generic mouse
        // collection of the Bluetooth mouse.
        let isAccepted = descriptor.isVendorCollection
            || (descriptor.isMouseCollection && descriptor.productID == TargetProducts.mxMaster4)
        guard isAccepted else { return }

        let key = descriptor.physicalKey
        let existing = lock.withLock { transports[key] }
        if let existing {
            // One physical device may publish several interfaces; prefer the
            // vendor collection and never open the same device twice.
            let preferNew = descriptor.isVendorCollection && !existing.descriptor.isVendorCollection
            guard preferNew else { return }
            existing.close()
        }

        let transport = IOKitHIDTransport(device: device)
        do {
            try transport.open()
        } catch {
            let handler = lock.withLock { errorHandler }
            let failure = (error as? IOKitHIDError)?.accessFailure ?? .unavailable
            handler?(descriptor, failure)
            return
        }
        lock.withLock { transports[key] = transport }
        publishChange()
    }

    private func handleRemoval(_ device: IOHIDDevice) {
        let descriptor = HIDInterfaceDescriptor(device: device)
        let removed = lock.withLock { transports.removeValue(forKey: descriptor.physicalKey) }
        guard removed != nil else { return }
        publishChange()
    }

    private func publishChange() {
        let handler = lock.withLock { changeHandler }
        let current = lock.withLock { Array(transports.values) }
        handler?(current)
    }
}
