import Foundation
import UTUVOMouseCore
import UTUVOMouseIO

/// The read only `--probe` mode.
///
/// It uses the same production transport as the app and only reads.
enum ProbeCommand {

    static func run() async -> Int32 {
        let service = LogitechHIDService()
        let collector = DeviceCollector()
        let language = AppLocalization.localizer.language
        service.onDevicesChanged { transports in
            collector.update(transports)
        }
        service.onError { descriptor, failure in
            let message = failure.message(language: language)
            FileHandle.standardError.write(Data(("utuvo-mouse: \(descriptor.productName): " + message + "\n").utf8))
        }
        service.start()

        // Give the manager a moment to enumerate the attached devices.
        let deadline = Date().addingTimeInterval(2.0)
        while Date() < deadline, collector.transports.isEmpty {
            try? await Task.sleep(for: .milliseconds(100))
        }
        let transports = collector.transports
        // A short settle time so hot plugged devices are seen as well.
        try? await Task.sleep(for: .milliseconds(600))

        var devices: [[String: Any]] = []
        for transport in transports {
            guard let client = try? HIDPPClient(
                transport: transport,
                deviceIndex: DeviceReader.deviceIndex(for: transport),
                timeout: .milliseconds(600)
            ) else { continue }
            let snapshot = await DeviceReader.snapshot(for: transport, client: client, language: AppLocalization.localizer.language)
            devices.append(dictionary(for: snapshot))
        }

        let payload: [String: Any] = [
            "tool": "utuvo-mouse",
            "mode": "probe",
            "readOnly": true,
            "generatedAt": ISO8601DateFormatter().string(from: Date()),
            "deviceCount": devices.count,
            "devices": devices,
            "notes": [
                AppLocalization.text("cli.probe.note.readOnly"),
                AppLocalization.text("cli.probe.note.stableID"),
            ],
        ]
        service.stop()

        guard let data = try? JSONSerialization.data(withJSONObject: payload, options: [.prettyPrinted, .sortedKeys]) else {
            FileHandle.standardError.write(Data(("utuvo-mouse: " + AppLocalization.text("cli.probe.serializeFailed") + "\n").utf8))
            return 1
        }
        FileHandle.standardOutput.write(data)
        FileHandle.standardOutput.write(Data("\n".utf8))
        return 0
    }

    /// Builds the JSON representation of one device.
    static func dictionary(for snapshot: DeviceSnapshot) -> [String: Any] {
        var features: [[String: Any]] = []
        for (id, index) in snapshot.features.sorted(by: { $0.key < $1.key }) {
            features.append([
                "id": String(format: "0x%04X", id),
                "index": Int(index),
            ])
        }
        var battery: [String: Any] = ["percent": snapshot.battery.percentage as Any]
        battery["charging"] = snapshot.battery.charging as Any
        if let note = snapshot.battery.message(language: AppLocalization.localizer.language) { battery["note"] = note }

        var device: [String: Any] = [
            "stableID": snapshot.identity.stableID,
            "model": snapshot.identity.model.rawValue,
            "modelDisplayName": snapshot.identity.model.displayTitle(language: AppLocalization.localizer.language),
            "vendorID": String(format: "0x%04X", snapshot.identity.vendorID),
            "productID": String(format: "0x%04X", snapshot.identity.productID),
            "transport": snapshot.identity.transport.rawValue,
            "transportDisplayName": snapshot.identity.transport.displayTitle(language: AppLocalization.localizer.language),
            "deviceIndex": String(format: "0x%02X", snapshot.identity.deviceIndex),
            "productName": snapshot.identity.productName,
            "features": features,
            "battery": battery,
            "issues": snapshot.issues,
        ]
        if let dpi = snapshot.dpi {
            device["dpi"] = [
                "current": dpi.current as Any,
                "available": dpi.available,
            ]
        }
        if let smartShift = snapshot.smartShift {
            device["smartShift"] = [
                "mode": smartShift.mode as Any,
                "threshold": smartShift.threshold as Any,
                "torquePercent": smartShift.torque as Any,
                "capabilities": smartShift.capabilities as Any,
                "defaultThreshold": smartShift.defaultThreshold as Any,
                "defaultTorquePercent": smartShift.defaultTorque as Any,
                "maxForceGram": smartShift.maxForce as Any,
            ]
        }
        if let wheel = snapshot.wheel {
            device["wheel"] = [
                "inverted": wheel.inverted as Any,
                "highResolution": wheel.highResolution as Any,
                "diverted": wheel.diverted as Any,
                "modeByte": wheel.modeByte.map { String(format: "0x%02X", $0) } as Any,
                "capabilities": wheel.capabilities.map { String(format: "0x%02X", $0) } as Any,
            ]
        }
        if let hits = snapshot.hitsCapabilities {
            device["hitsCapabilities"] = [
                "buttonCount": hits.buttonCount,
                "maxActuation": hits.maxActuation,
                "maxRapidTrigger": hits.maxRapidTrigger,
                "maxHaptics": hits.maxHaptics,
            ]
            var buttons: [[String: Any]] = []
            for button in snapshot.hitsButtons {
                buttons.append([
                    "button": button.button,
                    "actuation": button.actuation,
                    "rapidTriggerSensitivity": button.rapidTrigger,
                    "rapidTriggerEnabled": button.rapidTriggerEnabled,
                    "haptics": button.haptics,
                ])
            }
            device["hitsButtons"] = buttons
        }
        if let profile = snapshot.profile {
            device["onboard"] = [
                "sector": profile.sector,
                "dpiX": profile.dpiX,
                "dpiY": profile.dpiY,
                "reportRateHz": profile.reportRateHz,
                "crcValid": profile.hasValidCRC,
                "profileName": profile.name,
                "buttons": profile.buttonSlots.enumerated().map { index, action in
                    ["slot": index, "kind": String(describing: action.kind), "summary": action.localizedSummary(language: AppLocalization.localizer.language)]
                },
            ]
            device["onboardMode"] = snapshot.onboardMode as Any
        }
        if !snapshot.onboardInfoRaw.isEmpty {
            device["onboardInfoRaw"] = snapshot.onboardInfoRaw.map { String(format: "%02X", $0) }.joined(separator: " ")
        }
        if let plan = snapshot.plan {
            device["onboardPlan"] = [
                "mode": plan.mode,
                "runningSector": plan.runningSector as Any,
                "storedSector": plan.storedSector,
                "isRunning": plan.isRunning,
                "enabledSectors": plan.enabledSectors,
                "profileFormat": Int(plan.info.profileFormat),
                "sectorSize": plan.info.sectorSize,
            ]
        }
        if !snapshot.reprogControls.isEmpty {
            device["reprogramControls"] = snapshot.reprogControls.map { control in
                [
                    "index": control.index,
                    "cid": String(format: "0x%04X", control.cid),
                    "flags": String(format: "0x%04X", control.flags),
                    "divertable": control.isDivertable,
                    "virtual": control.isVirtual,
                    "mainButton": control.isMainButton,
                ]
            }
        }
        return device
    }
}

/// Collects the transports the scanner reports.
private nonisolated final class DeviceCollector: @unchecked Sendable {
    private let lock = NSLock()
    private var list: [IOKitHIDTransport] = []

    func update(_ transports: [IOKitHIDTransport]) {
        lock.withLock { list = transports }
    }

    var transports: [IOKitHIDTransport] { lock.withLock { list } }
}
