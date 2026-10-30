import Foundation
import IOKit
import IOKit.hid
import UTUVOMouseCore

/// The inspection accepts only the generic mouse collection of this Bluetooth
/// model. Exact transport strings avoid inferring Bluetooth from a PID or prefix.
public enum MXAnywhere3InspectionInterfacePolicy {
    public static func identity(
        vendorID: Int, productID: Int, registryTransport: String, usagePage: Int, usage: Int
    ) throws -> CapabilityInspectionIdentity {
        guard registryTransport == "Bluetooth" || registryTransport == "Bluetooth Low Energy",
              usagePage == 1, usage == 2 else { throw CapabilityInspectionError.identityMismatch }
        let identity = CapabilityInspectionIdentity(vendorID: vendorID, productID: productID, transport: .bluetooth)
        try MXAnywhere3CapabilityInspection.validate(identity: identity, consent: true)
        return identity
    }
}

/// A one-shot, explicit CLI operation. Never constructed by passive inventory,
/// DeviceReader, settings, --probe, or the GUI. No IOHIDManagerOpen, seizure,
/// receiver announcement, input diversion, permission request or persistent state.
@MainActor
public enum MXAnywhere3InspectionService {
    public static func inspect(consent: Bool) async throws -> CapabilityInspectionReport {
        let target = CapabilityInspectionIdentity(
            vendorID: MXAnywhere3CapabilityInspection.vendorID,
            productID: MXAnywhere3CapabilityInspection.productID,
            transport: .bluetooth
        )
        // Even registry enumeration requires the explicit opt-in for this mode.
        try MXAnywhere3CapabilityInspection.validate(identity: target, consent: consent)
        let discovery = InspectionDiscovery()
        discovery.start()
        defer { discovery.stop() }
        do {
            // Fixed discovery window. Async suspension leaves the main run loop
            // available for IOKit callbacks, as in the existing --probe service.
            try await Task.sleep(for: .milliseconds(750))
        } catch {
            throw CapabilityInspectionError.cancelled
        }
        let device = try discovery.singleDevice()
        let identity = try InspectionDiscovery.identity(of: device)
        // Validate the actual handle immediately before opening, on the main
        // actor. Pass only the Sendable channel to the pure async collector.
        try MXAnywhere3CapabilityInspection.validate(identity: identity, consent: consent)
        guard !Task.isCancelled else { throw CapabilityInspectionError.cancelled }
        let channel = try InspectionChannel(device: device)
        defer { channel.close() }
        return try await MXAnywhere3CapabilityInspection.collect(identity: identity, consent: consent) { channel }
    }
}

/// Reuses the production non-seizing transport and its HID++-only report filter,
/// but exposes it only to the bounded collector, never to configuration services.
private final class InspectionChannel: CapabilityInspectionChannel, @unchecked Sendable {
    private let transport: IOKitHIDTransport

    init(device: IOHIDDevice) throws {
        transport = IOKitHIDTransport(device: device)
        do {
            try transport.open()
        } catch let error as IOKitHIDError {
            if error.accessFailure.requiresInputMonitoring { throw CapabilityInspectionError.accessDenied }
            throw CapabilityInspectionError.transportFailure
        } catch {
            throw CapabilityInspectionError.transportFailure
        }
    }

    func send(_ bytes: [UInt8]) throws { try transport.send(bytes) }
    func setReportHandler(_ handler: @escaping @Sendable ([UInt8]) -> Void) { transport.setReportHandler(handler) }
    func close() { transport.close() }
}

/// Registry matching only: constructing/scheduling the manager does not open it
/// or any device. Store handles only; never read serials, names or unit addresses.
private final class InspectionDiscovery: @unchecked Sendable {
    private let manager = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
    private let lock = NSLock()
    private var devices: [UInt64: IOHIDDevice] = [:]

    static func identity(of device: IOHIDDevice) throws -> CapabilityInspectionIdentity {
        func int(_ key: String) -> Int {
            (IOHIDDeviceGetProperty(device, key as CFString) as? NSNumber)?.intValue ?? 0
        }
        return try MXAnywhere3InspectionInterfacePolicy.identity(
            vendorID: int(kIOHIDVendorIDKey), productID: int(kIOHIDProductIDKey),
            registryTransport: IOHIDDeviceGetProperty(device, kIOHIDTransportKey as CFString) as? String ?? "",
            usagePage: int(kIOHIDPrimaryUsagePageKey), usage: int(kIOHIDPrimaryUsageKey)
        )
    }

    func start() {
        let criteria: [String: Any] = [
            kIOHIDVendorIDKey: MXAnywhere3CapabilityInspection.vendorID,
            kIOHIDProductIDKey: MXAnywhere3CapabilityInspection.productID,
            kIOHIDPrimaryUsagePageKey: 1,
            kIOHIDPrimaryUsageKey: 2,
        ]
        IOHIDManagerSetDeviceMatching(manager, criteria as CFDictionary)
        let context = Unmanaged.passUnretained(self).toOpaque()
        IOHIDManagerRegisterDeviceMatchingCallback(manager, { context, result, _, device in
            guard let context, result == kIOReturnSuccess else { return }
            let discovery = Unmanaged<InspectionDiscovery>.fromOpaque(context).takeUnretainedValue()
            guard (try? InspectionDiscovery.identity(of: device)) != nil else { return }
            let key = HIDInterfaceDescriptor.registryEntryID(of: device)
            guard key != 0 else { return }
            discovery.lock.withLock { discovery.devices[key] = device }
        }, context)
        IOHIDManagerRegisterDeviceRemovalCallback(manager, { context, _, _, device in
            guard let context else { return }
            let discovery = Unmanaged<InspectionDiscovery>.fromOpaque(context).takeUnretainedValue()
            let key = HIDInterfaceDescriptor.registryEntryID(of: device)
            discovery.lock.withLock { _ = discovery.devices.removeValue(forKey: key) }
        }, context)
        IOHIDManagerScheduleWithRunLoop(manager, CFRunLoopGetMain(), CFRunLoopMode.commonModes.rawValue)
    }

    func singleDevice() throws -> IOHIDDevice {
        try lock.withLock {
            guard !devices.isEmpty else { throw CapabilityInspectionError.unavailable }
            // Do not guess a physical identity or open several mice on ambiguity.
            guard devices.count == 1, let device = devices.values.first else {
                throw CapabilityInspectionError.ambiguousDevice
            }
            return device
        }
    }

    func stop() {
        IOHIDManagerUnscheduleFromRunLoop(manager, CFRunLoopGetMain(), CFRunLoopMode.commonModes.rawValue)
        IOHIDManagerRegisterDeviceMatchingCallback(manager, nil, nil)
        IOHIDManagerRegisterDeviceRemovalCallback(manager, nil, nil)
        lock.withLock { devices.removeAll() }
    }
}
