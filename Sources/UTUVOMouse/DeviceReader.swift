import Foundation
import SwiftUI
import UTUVOMouseCore
import UTUVOMouseIO

/// Options fixed when the process starts.
@MainActor
enum LaunchOptions {
    static var demoMode = false
    /// Developer only: `dark` or `light`, used to check the layout without
    /// changing the system appearance.
    static var appearance: ColorScheme?
}

/// Reads the state of an open HID++ interface.
///
/// Everything here is read only: no function that writes to the device is called.
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
    static func snapshot(for transport: IOKitHIDTransport, client: HIDPPClient) async -> DeviceSnapshot {
        var snapshot = DeviceSnapshot(identity: identity(for: transport))
        snapshot.connectionEpoch = transport.connectionToken
        snapshot.identity.model = detectModel(features: [:], productID: transport.descriptor.productID)

        var protocolVersion: String?
        do {
            let ping = try await client.request(featureIndex: 0, function: 1, shortFallback: true)
            if ping.count >= 2 {
                protocolVersion = "\(ping[0]).\(ping[1])"
            }
        } catch {
            snapshot.issues.append("連線測試失敗：\(error.localizedDescription)")
            return snapshot
        }
        snapshot.protocolVersion = protocolVersion

        do {
            let features = try await client.enumerateFeatures()
            for feature in features {
                snapshot.features[feature.id] = feature.index
            }
        } catch {
            snapshot.issues.append("無法列出功能表：\(error.localizedDescription)")
            return snapshot
        }

        snapshot.identity.model = detectModel(features: snapshot.features, productID: transport.descriptor.productID)
        // The state is only authoritative when every read of this device worked.
        var authoritative = true

        if let battery = try? await client.readBattery() {
            snapshot.battery = battery
        } else {
            snapshot.issues.append("無法讀取電池狀態")
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
                    let profile = ProfileSector(bytes: bytes, sector: plan.storedSector)
                    snapshot.profile = profile
                    if !profile.hasValidCRC {
                        snapshot.issues.append("板載 sector 的 CRC 驗證失敗")
                    }
                }
                if !plan.isRunning {
                    snapshot.issues.append(
                        plan.isOnboardMode
                        ? "板載模式，但設定檔 \(plan.storedSector) 不是裝置正在執行的設定檔"
                        : "裝置目前在主控模式，畫面上是儲存的設定檔，不是正在套用的設定檔"
                    )
                }
            } else {
                snapshot.issues.append("無法讀取板載資訊")
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
    static func snapshots() -> [DeviceSnapshot] {
        [demoMX(), demoSuperstrike()]
    }

    static func demoMX() -> DeviceSnapshot {
        let identity = DeviceIdentity(
            stableID: "sha256:demo00000000000a",
            model: .mxMaster4,
            vendorID: 0x046D,
            productID: TargetProducts.mxMaster4,
            transport: .bluetooth,
            deviceIndex: 0xFF,
            productName: "MX Master 4 M（示範）"
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
        snapshot.battery = BatteryStatus(percentage: 90, charging: false, note: "示範資料")
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
        ]
        snapshot.issues = ["示範模式：所有數值都是合成資料，未連接任何裝置。"]
        return snapshot
    }

    static func demoSuperstrike() -> DeviceSnapshot {
        let identity = DeviceIdentity(
            stableID: "sha256:demo00000000000b",
            model: .superstrike,
            vendorID: 0x046D,
            productID: TargetProducts.superstrikeDirect,
            transport: .usb,
            deviceIndex: 0xFF,
            productName: "PRO X2 SUPERSTRIKE（示範）"
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
        snapshot.battery = BatteryStatus(percentage: 100, charging: false, note: "示範資料")
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
            controlBytes: []
        )
        snapshot.profile = demoProfile()
        snapshot.issues = ["示範模式：所有數值都是合成資料，未連接任何裝置。"]
        return snapshot
    }

    /// A synthetic profile sector with a correct CRC.
    private static func demoProfile() -> ProfileSector {
        var bytes = [UInt8](repeating: 0, count: 255)
        bytes[0] = 3  // 1000 Hz
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
