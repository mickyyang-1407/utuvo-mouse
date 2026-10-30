import Foundation
import SwiftUI
import UTUVOMouseCore
import UTUVOMouseIO
import UTUVOMouseLocalization

/// Options fixed when the process starts.
@MainActor
enum LaunchOptions {
    static var demoMode = false
    static var languageOverride: MouseLanguage?
    /// Developer only: `dark` or `light`, used to check the layout without
    /// changing the system appearance.
    static var appearance: ColorScheme?
}

/// Reads the state of an open HID++ interface.
///
/// Reads settings; a receiver announcement requests arrival notifications only.
/// No pairing, profile, mode or user configuration is changed.
/// The type is `nonisolated` so the reads run off the main actor.
nonisolated enum DeviceReader {

    /// The identity of a device, without exposing its serial number or address.
    static func identity(for transport: IOKitHIDTransport) -> DeviceIdentity {
        let descriptor = transport.descriptor
        // A device behind a LIGHTSPEED receiver answers on slot 1; a directly
        // attached device answers on 0xFF.
        let deviceIndex: UInt8 = descriptor.productID == TargetProducts.receiver ? 0x01 : 0xFF
        return DeviceIdentity(
            stableID: StableIdentifier.make(
                vendorID: descriptor.vendorID,
                productID: descriptor.productID,
                seed: descriptor.physicalKey
            ),
            model: .unknown,
            vendorID: descriptor.vendorID,
            productID: descriptor.productID,
            transport: descriptor.transportKind,
            deviceIndex: deviceIndex,
            productName: descriptor.productName
        )
    }

    /// The HID++ device index a device answers on.
    static func deviceIndex(for transport: IOKitHIDTransport) -> UInt8 {
        transport.descriptor.productID == TargetProducts.receiver ? 0x01 : 0xFF
    }

    /// Reads one device. Values that cannot be read stay unknown.
    static func snapshot(for transport: IOKitHIDTransport, client: HIDPPClient, language: MouseLanguage) async -> DeviceSnapshot {
        let text = MouseLocalizer(language: language)
        var snapshot = DeviceSnapshot(identity: identity(for: transport))
        snapshot.connectionEpoch = transport.connectionToken
        snapshot.identity.model = detectModel(features: [:], productID: transport.descriptor.productID)

        var protocolVersion: String?
        do {
            try await transport.announceReceiverIfNeeded()
            let ping: [UInt8]
            do {
                ping = try await client.request(featureIndex: 0, function: 1, shortFallback: true)
            } catch HIDPPError.localized(key: "error.hidpp.receiverUnavailable", arguments: []) where transport.descriptor.productID == TargetProducts.receiver {
                // One retry of this read only, following Nanostrike's wake path.
                // Writes and flash commits are never retried by this mechanism.
                try await transport.announceReceiverIfNeeded(force: true)
                ping = try await client.request(featureIndex: 0, function: 1, shortFallback: true)
            }
            if ping.count >= 2 {
                protocolVersion = "\(ping[0]).\(ping[1])"
            }
        } catch {
            let message = (error as? HIDPPError)?.localizedMessage(language: language) ?? error.localizedDescription
            snapshot.issues.append(text.string("device.issue.ping", arguments: [message]))
            return snapshot
        }
        snapshot.protocolVersion = protocolVersion

        do {
            let features = try await client.enumerateFeatures()
            for feature in features {
                snapshot.features[feature.id] = feature.index
            }
        } catch {
            let message = (error as? HIDPPError)?.localizedMessage(language: language) ?? error.localizedDescription
            snapshot.issues.append(text.string("device.issue.features", arguments: [message]))
            return snapshot
        }

        snapshot.identity.model = detectModel(features: snapshot.features, productID: transport.descriptor.productID)
        // The state is only authoritative when every read of this device worked.
        var authoritative = true

        if let battery = try? await client.readBattery() {
            snapshot.battery = battery
        } else {
            snapshot.issues.append(text.string("device.issue.battery"))
            authoritative = false
        }

        if snapshot.features[HIDPPFeatureID.adjustableDPI] != nil {
            if let dpi = try? await client.readDPI() {
                snapshot.dpi = dpi
                if dpi.current == nil { authoritative = false }
            } else {
                authoritative = false
            }
        }
        if snapshot.features[HIDPPFeatureID.smartShiftEnhanced] != nil || snapshot.features[HIDPPFeatureID.smartShift] != nil {
            snapshot.smartShift = try? await client.readSmartShift()
            if snapshot.smartShift == nil { authoritative = false }
        }
        if snapshot.features[HIDPPFeatureID.wheelControl] != nil {
            snapshot.wheel = try? await client.readWheel()
            if snapshot.wheel == nil { authoritative = false }
        }
        if snapshot.features[HIDPPFeatureID.specialKeysAndMSEButtons] != nil {
            if let reprogram = try? await ReprogramControlsClient.resolve(for: client),
               let controls = try? await reprogram.readControls() {
                snapshot.reprogControls = controls
            } else {
                authoritative = false
            }
        }
        if snapshot.features[HIDPPFeatureID.analogButtons] != nil {
            snapshot.hitsCapabilities = try? await client.readHitsCapabilities()
            if let capabilities = snapshot.hitsCapabilities {
                for button in 0..<max(1, capabilities.buttonCount) {
                    if let config = try? await client.readHitsButton(button) {
                        snapshot.hitsButtons.append(config)
                    }
                }
            }
        }
        if snapshot.identity.model == .superstrike {
            do {
                let x = try await client.readDPIGrid(axis: 0)
                let y = try await client.readDPIGrid(axis: 1)
                snapshot.supportedProfileDPI = x.values.filter { value in y.contains(UInt16(value)) }
            } catch {
                snapshot.issues.append(text.string("error.profile.dpiGridUnavailable"))
            }
        }
        if snapshot.features[HIDPPFeatureID.onboardProfiles] != nil,
           let onboard = try? await OnboardProfilesClient.resolve(for: client) {
            if let info = try? await onboard.readInfo() {
                snapshot.onboardInfoRaw = info.raw
            }
            let service = SuperstrikeService(
                client: client,
                onboard: onboard,
                backupStore: FileBackupStore(root: URL(fileURLWithPath: NSTemporaryDirectory())),
                deviceID: snapshot.identity.stableID
            )
            if let plan = try? await service.readPlan() {
                snapshot.plan = plan
                snapshot.onboardMode = plan.mode
                if let bytes = try? await onboard.readSector(plan.storedSector, size: plan.info.sectorSize) {
                    let profile = ProfileSector(bytes: bytes, sector: plan.storedSector, activeDPIIndex: plan.activeDPIIndex)
                    snapshot.profile = profile
                    if plan.isRunning {
                        if let actual = try? await client.readSensorDPI(), actual.x == profile.dpiX, actual.y == profile.dpiY {
                            // Both the selected profile stage and the sensor agree.
                        } else {
                            authoritative = false
                            snapshot.issues.append(text.string("error.profile.dpiVerify"))
                        }
                    }
                    if !profile.hasValidCRC {
                        snapshot.issues.append(text.string("device.issue.profileCRC"))
                    }
                }
                if !plan.isRunning {
                    snapshot.issues.append(text.string(
                        plan.isOnboardMode ? "device.issue.profileNotRunningOnboard" : "device.issue.profileNotRunningHost",
                        arguments: [plan.storedSector]
                    ))
                }
            } else {
                snapshot.issues.append(text.string("device.issue.onboard"))
            }
        }
        snapshot.isStateAuthoritative = authoritative && snapshot.hasCompleteState
        return snapshot
    }

    /// Picks the model from the features the device implements.
    static func detectModel(features: [UInt16: UInt8], productID: Int) -> MouseModel {
        if features[HIDPPFeatureID.onboardProfiles] != nil { return .superstrike }
        if features[HIDPPFeatureID.analogButtons] != nil { return .superstrike }
        if features[HIDPPFeatureID.adjustableDPI] != nil
            || features[HIDPPFeatureID.smartShiftEnhanced] != nil
            || features[HIDPPFeatureID.wheelControl] != nil {
            return .mxMaster4
        }
        switch productID {
        case TargetProducts.mxMaster4: return .mxMaster4
        case TargetProducts.superstrikeDirect: return .superstrike
        case TargetProducts.receiver: return .receiver
        default: return .unknown
        }
    }
}

/// Synthetic data for the demo mode. It is labelled as demo everywhere it shows.
///
/// The demo never touches IOKit: no manager, no service, no device.
nonisolated enum DemoData {
    static func snapshots(language: MouseLanguage) -> [DeviceSnapshot] {
        [demoMX(language: language), demoSuperstrike(language: language)]
    }

    static func demoMX(language: MouseLanguage) -> DeviceSnapshot {
        let text = MouseLocalizer(language: language)
        let identity = DeviceIdentity(
            stableID: "sha256:demo00000000000a",
            model: .mxMaster4,
            vendorID: 0x046D,
            productID: TargetProducts.mxMaster4,
            transport: .bluetooth,
            deviceIndex: 0xFF,
            productName: "MX Master 4 M"
        )
        var snapshot = DeviceSnapshot(identity: identity)
        snapshot.isDemo = true
        snapshot.protocolVersion = "4.5"
        snapshot.features = [
            HIDPPFeatureID.root: 0,
            HIDPPFeatureID.unifiedBattery: 9,
            HIDPPFeatureID.adjustableDPI: 20,
            HIDPPFeatureID.smartShiftEnhanced: 17,
            HIDPPFeatureID.wheelControl: 18,
            HIDPPFeatureID.specialKeysAndMSEButtons: 13,
        ]
        snapshot.battery = BatteryStatus(percentage: 90, charging: false, note: text.string("app.demoData"))
        snapshot.dpi = DPIState(current: 3200, available: [200, 400, 800, 1600, 3200, 8000])
        snapshot.smartShift = SmartShiftState(
            mode: 1,
            threshold: 12,
            torque: 75,
            capabilities: 0x01,
            defaultThreshold: 10,
            defaultTorque: 75,
            maxForce: 14
        )
        snapshot.wheel = WheelState(inverted: false, highResolution: false, diverted: false, modeByte: 0x01, capabilities: 0x1F)
        // The three divertable side buttons of the MX Master 4 M.
        snapshot.reprogControls = [
            ReprogramControl(index: 0, cid: 0x0050, taskID: 0x0001, flags: 0x0401, position: 1, group: 1, groupMask: 0x02),
            ReprogramControl(index: 1, cid: 0x0051, taskID: 0x0002, flags: 0x0401, position: 2, group: 1, groupMask: 0x02),
            ReprogramControl(index: 2, cid: 0x0052, taskID: 0x0003, flags: 0x0531, position: 3, group: 2, groupMask: 0x04),
            ReprogramControl(index: 3, cid: 0x0053, taskID: 0x0004, flags: 0x0531, position: 4, group: 2, groupMask: 0x04),
            ReprogramControl(index: 4, cid: 0x0056, taskID: 0x0005, flags: 0x0531, position: 5, group: 2, groupMask: 0x04),
            ReprogramControl(index: 5, cid: 0x01A0, taskID: 0x01A0, flags: 0x0531, position: 6, group: 2, groupMask: 0x04),
        ]
        snapshot.issues = [text.string("device.demo.issue")]
        return snapshot
    }

    static func demoSuperstrike(language: MouseLanguage) -> DeviceSnapshot {
        let text = MouseLocalizer(language: language)
        let identity = DeviceIdentity(
            stableID: "sha256:demo00000000000b",
            model: .superstrike,
            vendorID: 0x046D,
            productID: TargetProducts.superstrikeDirect,
            transport: .usb,
            deviceIndex: 0xFF,
            productName: "PRO X2 SUPERSTRIKE"
        )
        var snapshot = DeviceSnapshot(identity: identity)
        snapshot.isDemo = true
        snapshot.protocolVersion = "4.2"
        snapshot.features = [
            HIDPPFeatureID.root: 0,
            HIDPPFeatureID.unifiedBattery: 6,
            HIDPPFeatureID.analogButtons: 2,
            HIDPPFeatureID.onboardProfiles: 4,
        ]
        snapshot.battery = BatteryStatus(percentage: 100, charging: false, note: text.string("app.demoData"))
        snapshot.hitsCapabilities = HitsCapabilities(buttonCount: 2, maxActuation: 10, maxRapidTrigger: 5, maxHaptics: 5)
        snapshot.hitsButtons = [
            HitsButtonConfig(button: 0, actuation: 5, rapidTrigger: 2, haptics: 3, rapidTriggerFlag: 0),
            HitsButtonConfig(button: 1, actuation: 5, rapidTrigger: 2, haptics: 3, rapidTriggerFlag: 0),
        ]
        snapshot.onboardMode = 1
        snapshot.plan = SuperstrikePlan(
            info: OnboardInfo(
                memoryModel: 1,
                profileFormat: 1,
                macroEnabled: 0,
                profileCount: 5,
                outOfBounds: 0,
                buttonCount: 5,
                sectorCount: 5,
                sectorSize: 255,
                shift: 0,
                raw: []
            ),
            mode: 1,
            runningSector: 1,
            storedSector: 1,
            isRunning: true,
            enabledSectors: [1],
            controlBytes: [], activeDPIIndex: 1
        )
        snapshot.profile = demoProfile()
        snapshot.issues = [text.string("device.demo.issue")]
        return snapshot
    }

    /// A synthetic profile sector with a correct CRC.
    private static func demoProfile() -> ProfileSector {
        var bytes = [UInt8](repeating: 0, count: 255)
        bytes[0] = 3  // 1000 Hz
        bytes[2] = 1
        bytes.replaceSubrange(38..<44, with: [20,8,12,20,8,12])
        bytes[9] = 0x80; bytes[10] = 0x0C   // X = 3200
        bytes[11] = 0x80; bytes[12] = 0x0C  // Y = 3200
        // Factory button order: left, right, middle, back, forward.
        bytes[48] = 0x80; bytes[49] = 0x01; bytes[50] = 0x00; bytes[51] = 0x01
        bytes[52] = 0x80; bytes[53] = 0x01; bytes[54] = 0x00; bytes[55] = 0x02
        bytes[56] = 0x80; bytes[57] = 0x01; bytes[58] = 0x00; bytes[59] = 0x04
        bytes[60] = 0x80; bytes[61] = 0x01; bytes[62] = 0x00; bytes[63] = 0x08
        bytes[64] = 0x80; bytes[65] = 0x01; bytes[66] = 0x00; bytes[67] = 0x10
        return ProfileSector(bytes: bytes, sector: 1).withRecomputedCRC()
    }
}
