import Foundation

/// What the app knows about the onboard memory of a Superstrike.
public struct SuperstrikePlan: Sendable, Equatable {
    public var info: OnboardInfo
    /// 1 = onboard (the hardware profile owns the settings), 2 = host.
    public var mode: Int
    /// The sector the device names as the running one, if any.
    public var runningSector: Int?
    /// The sector whose content the app shows.
    public var storedSector: Int
    /// True when the shown sector is the one the device is running.
    public var isRunning: Bool
    /// The profile slots the control sector marks as enabled.
    public var enabledSectors: [Int]
    /// The complete control sector, used for the backup.
    public var controlBytes: [UInt8]

    public init(
        info: OnboardInfo,
        mode: Int,
        runningSector: Int?,
        storedSector: Int,
        isRunning: Bool,
        enabledSectors: [Int],
        controlBytes: [UInt8]
    ) {
        self.info = info
        self.mode = mode
        self.runningSector = runningSector
        self.storedSector = storedSector
        self.isRunning = isRunning
        self.enabledSectors = enabledSectors
        self.controlBytes = controlBytes
    }

    public var isOnboardMode: Bool { mode == 1 }
}

/// One button slot of a compound change.
public struct ButtonChange: Sendable, Equatable {
    public var slot: Int
    public var action: ButtonAction

    public init(slot: Int, action: ButtonAction) {
        self.slot = slot
        self.action = action
    }
}

/// Everything one click changes to the profile — applied as one patch.
public struct CompoundChanges: Sendable {
    public var dpiX: Int?
    public var dpiY: Int?
    public var reportRateHz: Int?
    public var buttons: [ButtonChange]

    public init(dpiX: Int? = nil, dpiY: Int? = nil, reportRateHz: Int? = nil, buttons: [ButtonChange] = []) {
        self.dpiX = dpiX
        self.dpiY = dpiY
        self.reportRateHz = reportRateHz
        self.buttons = buttons
    }

    public var isEmpty: Bool {
        dpiX == nil && dpiY == nil && reportRateHz == nil && buttons.isEmpty
    }
}

/// The outcome of an apply. A device acknowledgement is never treated as proof
/// that a setting changed — only a byte exact read back is.
public enum ApplyOutcome: Sendable, Equatable {
    /// The sector was written and read back byte for byte.
    case applied(backup: URL)
    /// The device is not running the profile the change is meant for; the user has
    /// to pick it explicitly first.
    case needsOnboardSelection(sector: Int)
    /// The device content changed since the interface was filled in.
    case rejectedStale
    /// The backup could not be written, so nothing was sent to the device.
    case backupFailed(String)
    /// The write could not be confirmed; the device state is unknown.
    case uncertain(String)
    /// The write failed with a definite error before the device was touched.
    case failed(String)

    public var isApplied: Bool {
        if case .applied = self { return true }
        return false
    }

    /// True when the device state has to be read again before anything else happens.
    public var isUncertain: Bool {
        if case .uncertain = self { return true }
        return false
    }

    public var summary: String {
        switch self {
        case .applied(let backup): "已寫入並讀回驗證（備份：\(backup.lastPathComponent)）"
        case .needsOnboardSelection: "請先按「使用板載設定」選擇要使用的設定檔，再套用變更"
        case .rejectedStale: "裝置狀態已變更，已拒絕套用，請重新整理"
        case .backupFailed(let detail): "備份失敗，未寫入裝置：\(detail)"
        case .uncertain(let detail): "寫入結果不確定，請重新整理後再確認：\(detail)"
        case .failed(let detail): "套用失敗：\(detail)"
        }
    }
}

/// The Superstrike specific operations.
///
/// The live setters of this mouse are firmware no-ops, so DPI, report rate and
/// the button assignments live in the onboard profile sector and are written
/// through it — always as one compound patch, always with a backup first.
public struct SuperstrikeService: Sendable {
    /// The memory model this build supports.
    public static let supportedMemoryModel: UInt8 = 0x01
    /// The profile format this build understands — read from the real device
    /// (`01 08 01 05 01 05 10 00 FF 0A …`, so byte 1 is 0x08).
    public static let supportedProfileFormat: UInt8 = 0x08
    /// The sector size of the Superstrike.
    public static let supportedSectorSize = 255

    public let client: HIDPPClient
    public let onboard: OnboardProfilesClient
    public let backupStore: BackupStoring
    /// The stable identifier written into the backup file.
    public let deviceID: String

    public init(client: HIDPPClient, onboard: OnboardProfilesClient, backupStore: BackupStoring, deviceID: String) {
        self.client = client
        self.onboard = onboard
        self.backupStore = backupStore
        self.deviceID = deviceID
    }

    /// Reads the onboard memory and checks that this build understands it.
    public func readPlan() async throws -> SuperstrikePlan {
        let info = try await onboard.readInfo()
        guard info.isSupportedModel else {
            throw HIDPPError.unsupported("不支援的內存模式 \(info.memoryModel)")
        }
        guard info.profileFormat == Self.supportedProfileFormat else {
            throw HIDPPError.unsupported("不支援的設定檔格式 \(info.profileFormat)")
        }
        guard info.sectorSize == Self.supportedSectorSize else {
            throw HIDPPError.unsupported("不支援的 sector 大小 \(info.sectorSize)")
        }
        let mode = (try? await onboard.readMode()) ?? 0
        let running = try? await onboard.readCurrentSector()
        let headers = (try? await onboard.readProfileHeaders()) ?? []
        let active = try await onboard.activeProfileSector()
        let control = try await onboard.readSector(0x0000, size: info.sectorSize)
        let isRunning = mode == 1 && running == active.sector && active.isRunningSlot
        return SuperstrikePlan(
            info: info,
            mode: mode,
            runningSector: running,
            storedSector: active.sector,
            isRunning: isRunning,
            enabledSectors: headers.filter(\.enabled).map(\.sector),
            controlBytes: control
        )
    }

    /// Switches the device into onboard mode and selects a profile.
    ///
    /// This is a device configuration change and is only ever called from an
    /// explicit user action. The result is verified by reading the mode and the
    /// running sector back.
    public func activateOnboard(profileSector: Int) async -> ApplyOutcome {
        let plan: SuperstrikePlan
        do {
            plan = try await readPlan()
        } catch {
            return .failed("讀取板載資訊失敗：\(error.localizedDescription)")
        }
        guard Self.isValidProfileSector(profileSector, count: plan.info.profileCount) else {
            return .failed("設定檔 \(profileSector) 不在 1...\(plan.info.profileCount) 的範圍內")
        }
        do {
            try await onboard.setMode(1)
            try await onboard.setCurrentProfile(profileSector)
        } catch {
            return .uncertain("切換板載模式失敗：\(error.localizedDescription)")
        }
        // Verify with a read back — an acknowledgement alone proves nothing.
        let mode = (try? await onboard.readMode()) ?? 0
        let running = (try? await onboard.readCurrentSector()) ?? 0
        guard mode == 1, running == profileSector else {
            return .uncertain("板載模式讀回不一致（模式 \(mode)、設定檔 \(running)）")
        }
        return .applied(backup: URL(fileURLWithPath: "（模式切換不需備份）"))
    }

    /// Applies a compound change to the running profile sector.
    ///
    /// The device is re-read first, the original sector and the complete control
    /// sector are backed up, the requested bytes are patched, the CRC is
    /// recomputed and the sector is written and read back.
    public func applyCompound(plan: SuperstrikePlan, baseline: ProfileSector, changes: CompoundChanges) async -> ApplyOutcome {
        guard !changes.isEmpty else {
            return .failed("沒有任何變更")
        }
        guard plan.info.isSupportedModel, plan.info.profileFormat == Self.supportedProfileFormat else {
            return .failed("裝置的板載格式不是這個版本支援的")
        }
        guard plan.info.sectorSize == Self.supportedSectorSize else {
            return .failed("不支援的 sector 大小 \(plan.info.sectorSize)")
        }
        guard Self.isValidProfileSector(plan.storedSector, count: plan.info.profileCount) else {
            return .failed("設定檔 \(plan.storedSector) 不在有效範圍內")
        }
        // Writing only makes sense for the profile the device is actually running.
        guard plan.isRunning else {
            return .needsOnboardSelection(sector: plan.storedSector)
        }

        // Fresh read of everything that decides whether a write is allowed: the
        // memory model, the profile format, the sector size, the layout, the
        // mode, the running profile and the control entry of the target sector.
        let freshInfo: OnboardInfo
        let freshMode: Int
        let freshSlot: Int
        let headers: [(sector: Int, enabled: Bool)]
        do {
            freshInfo = try await onboard.readInfo()
            freshMode = try await onboard.readMode()
            freshSlot = try await onboard.readCurrentSector()
            headers = try await onboard.readProfileHeaders()
        } catch {
            return .failed("讀取板載狀態失敗：\(error.localizedDescription)")
        }
        guard freshInfo.memoryModel == Self.supportedMemoryModel,
              freshInfo.profileFormat == Self.supportedProfileFormat,
              freshInfo.sectorSize == Self.supportedSectorSize else {
            return .failed("裝置的板載格式不是這個版本支援的")
        }
        guard freshInfo.profileCount == plan.info.profileCount,
              freshInfo.buttonCount == plan.info.buttonCount else {
            return .rejectedStale
        }
        guard freshMode == 1 else {
            // Host mode: the profile is not the running one.
            return .needsOnboardSelection(sector: plan.storedSector)
        }
        guard freshSlot == plan.storedSector else {
            return .rejectedStale
        }
        guard let entry = headers.first(where: { $0.sector == plan.storedSector }), entry.enabled else {
            return .rejectedStale
        }
        let currentBytes: [UInt8]
        do {
            currentBytes = try await onboard.readSector(plan.storedSector, size: freshInfo.sectorSize)
        } catch {
            return .failed("重新讀取 sector 失敗：\(error.localizedDescription)")
        }
        guard currentBytes == baseline.bytes else {
            return .rejectedStale
        }
        let current = ProfileSector(bytes: currentBytes, sector: plan.storedSector)
        guard current.hasValidCRC else {
            return .failed("目前 sector CRC 驗證失敗")
        }

        let patched: ProfileSector
        do {
            patched = try Self.patch(current, changes: changes)
        } catch {
            return .failed(error.localizedDescription)
        }
        guard patched.bytes != current.bytes else {
            return .failed("內容沒有變更，未寫入")
        }

        // The backup has to exist before anything is sent to the device. The
        // control sector is part of it — a partial backup is no backup.
        let control = try? await onboard.readSector(0x0000, size: plan.info.sectorSize)
        guard let controlBytes = control, controlBytes.count == plan.info.sectorSize else {
            return .backupFailed("無法讀取完整的控制區，未寫入裝置")
        }
        let backup = SectorBackup(
            createdAt: Date(),
            deviceID: deviceID,
            sector: plan.storedSector,
            sectorSize: currentBytes.count,
            sectorBytes: currentBytes,
            controlBytes: controlBytes,
            meta: [
                "mode": "\(plan.mode)",
                "runningSector": "\(plan.storedSector)",
                "changes": describe(changes),
            ]
        )
        let backupURL: URL
        do {
            backupURL = try backupStore.store(backup)
        } catch {
            return .backupFailed(error.localizedDescription)
        }
        // As close to the write as possible: the mode and the running profile
        // are read again, so a change in between stops the write.
        do {
            let modeNow = try await onboard.readMode()
            let slotNow = try await onboard.readCurrentSector()
            guard modeNow == 1, slotNow == plan.storedSector else {
                return .rejectedStale
            }
        } catch {
            return .failed("寫入前的最後確認失敗：\(error.localizedDescription)")
        }
        do {
            let outcome = try await onboard.writeSector(plan.storedSector, bytes: patched.bytes)
            switch outcome {
            case .verified:
                return .applied(backup: backupURL)
            case .uncertain(let detail):
                return .uncertain(detail)
            case .failedBeforeBegin(let detail):
                return .failed(detail)
            }
        } catch {
            return .uncertain(error.localizedDescription)
        }
    }

    /// A profile slot is valid when it is one of the user profiles 1...count.
    static func isValidProfileSector(_ sector: Int, count: Int) -> Bool {
        sector >= 1 && sector <= count && sector != 0x0100
    }

    /// Applies the allowlisted changes to a copy of the sector.
    static func patch(_ sector: ProfileSector, changes: CompoundChanges) throws -> ProfileSector {
        var patched = sector
        if changes.dpiX != nil || changes.dpiY != nil {
            let x = changes.dpiX ?? sector.dpiX
            let y = changes.dpiY ?? sector.dpiY
            patched = try patched.settingDPI(x: x, y: y)
        }
        if let hz = changes.reportRateHz {
            patched = try patched.settingReportRate(hz: hz)
        }
        for change in changes.buttons {
            patched = try patched.settingButton(slot: change.slot, action: change.action)
        }
        return patched.withRecomputedCRC()
    }

    private func describe(_ changes: CompoundChanges) -> String {
        var parts: [String] = []
        if let x = changes.dpiX, let y = changes.dpiY { parts.append("DPI \(x)×\(y)") }
        if let hz = changes.reportRateHz { parts.append("回報率 \(hz) Hz") }
        for change in changes.buttons { parts.append("按鍵槽位 \(change.slot)") }
        return parts.joined(separator: ", ")
    }
}
