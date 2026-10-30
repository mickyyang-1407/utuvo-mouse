import Foundation
import UTUVOMouseLocalization

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
    public var activeDPIIndex: Int?

    public init(
        info: OnboardInfo,
        mode: Int,
        runningSector: Int?,
        storedSector: Int,
        isRunning: Bool,
        enabledSectors: [Int],
        controlBytes: [UInt8],
        activeDPIIndex: Int? = nil
    ) {
        self.info = info
        self.mode = mode
        self.runningSector = runningSector
        self.storedSector = storedSector
        self.isRunning = isRunning
        self.enabledSectors = enabledSectors
        self.controlBytes = controlBytes
        self.activeDPIIndex = activeDPIIndex
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
    public var hits: [HIDPPClient.HitsDraft]

    public init(dpiX: Int? = nil, dpiY: Int? = nil, reportRateHz: Int? = nil, buttons: [ButtonChange] = [], hits: [HIDPPClient.HitsDraft] = []) {
        self.dpiX = dpiX
        self.dpiY = dpiY
        self.reportRateHz = reportRateHz
        self.buttons = buttons
        self.hits = hits
    }

    public var isEmpty: Bool {
        dpiX == nil && dpiY == nil && reportRateHz == nil && buttons.isEmpty && hits.isEmpty
    }
}

/// The outcome of an apply. A device acknowledgement is never treated as proof
/// that a setting changed — only a byte exact read back is.
public indirect enum SuperstrikeFailure: Sendable, Equatable {
    case localized(key: String, arguments: [String])
    case causedBy(key: String, arguments: [String], cause: SuperstrikeFailure)
    case hidpp(HIDPPError)
    case backup(BackupError)
    case external(String)

    public static func capture(_ error: Error) -> SuperstrikeFailure {
        if let error = error as? HIDPPError { return .hidpp(error) }
        if let error = error as? BackupError { return .backup(error) }
        return .external(error.localizedDescription)
    }

    public func message(language: MouseLanguage) -> String {
        let text = MouseLocalizer(language: language)
        return switch self {
        case .localized(let key, let arguments): text.string(key, arguments: arguments)
        case .causedBy(let key, let arguments, let cause):
            text.string(key, arguments: arguments + [cause.message(language: language)])
        case .hidpp(let error): error.localizedMessage(language: language)
        case .backup(let error): error.message(language: language)
        case .external(let detail): detail
        }
    }
}

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
    case backupFailedReason(SuperstrikeFailure)
    case uncertainReason(SuperstrikeFailure)
    case failedReason(SuperstrikeFailure)
    /// A profile was selected and verified in onboard mode; no file backup applies.
    case onboardActivated

    public var isApplied: Bool {
        if case .applied = self { return true }
        if case .onboardActivated = self { return true }
        return false
    }

    /// True when the device state has to be read again before anything else happens.
    public var isUncertain: Bool {
        if case .uncertain = self { return true }
        if case .uncertainReason = self { return true }
        return false
    }

    public var summary: String {
        switch self {
        case .applied(let backup): "已寫入並讀回驗證（備份：\(backup.lastPathComponent)）"
        case .onboardActivated: "已切換並確認板載設定檔。"
        case .needsOnboardSelection: "請先按「使用板載設定」選擇要使用的設定檔，再套用變更"
        case .rejectedStale: "裝置狀態已變更，已拒絕套用，請重新整理"
        case .backupFailed(let detail): "備份失敗，未寫入裝置：\(detail)"
        case .uncertain(let detail): "寫入結果不確定，請重新整理後再確認：\(detail)"
        case .failed(let detail): "套用失敗：\(detail)"
        case .backupFailedReason(let issue): "備份失敗，未寫入裝置：\(issue.message(language: .traditionalChinese))"
        case .uncertainReason(let issue): "寫入結果不確定，請重新整理後再確認：\(issue.message(language: .traditionalChinese))"
        case .failedReason(let issue): "套用失敗：\(issue.message(language: .traditionalChinese))"
        }
    }

    public func localizedSummary(language: MouseLanguage) -> String {
        let text = MouseLocalizer(language: language)
        return switch self {
        case .applied(let backup): text.string("app.apply.applied", arguments: [backup.lastPathComponent])
        case .onboardActivated: text.string("app.apply.onboardActivated")
        case .needsOnboardSelection(let sector): text.string("app.apply.needsOnboard", arguments: [sector])
        case .rejectedStale: text.string("app.apply.rejectedStale")
        case .backupFailed(let detail): text.string("app.apply.backupFailed", arguments: [detail])
        case .uncertain(let detail): text.string("app.apply.uncertain", arguments: [detail])
        case .failed(let detail): text.string("app.apply.failed", arguments: [detail])
        case .backupFailedReason(let issue): text.string("app.apply.backupFailed", arguments: [issue.message(language: language)])
        case .uncertainReason(let issue): text.string("app.apply.uncertain", arguments: [issue.message(language: language)])
        case .failedReason(let issue): text.string("app.apply.failed", arguments: [issue.message(language: language)])
        }
    }
}

/// The Superstrike specific operations.
///
/// Daily DPI, report rate, HITS and button assignments are persisted in the
/// onboard profile sector and written
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
            throw HIDPPError.localized(key: "error.superstrike.memoryModel", arguments: [String(info.memoryModel)])
        }
        guard info.profileFormat == Self.supportedProfileFormat else {
            throw HIDPPError.localized(key: "error.superstrike.profileFormat", arguments: [String(info.profileFormat)])
        }
        guard info.buttonCount == ProfileLayout.buttonSlotCount else {
            throw HIDPPError.localized(key: "error.superstrike.unsupportedFormat", arguments: [])
        }
        guard info.sectorSize == Self.supportedSectorSize else {
            throw HIDPPError.localized(key: "error.superstrike.sectorSize", arguments: [String(info.sectorSize)])
        }
        let activeDPIIndex = try? await onboard.readActiveResolution()
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
            controlBytes: control,
            activeDPIIndex: activeDPIIndex
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
            return .failedReason(.causedBy(key: "error.superstrike.readOnboardInfo", arguments: [], cause: .capture(error)))
        }
        guard Self.isValidProfileSector(profileSector, count: plan.info.profileCount) else {
            return .failedReason(.localized(key: "error.superstrike.invalidProfile", arguments: [String(profileSector), String(plan.info.profileCount)]))
        }
        do {
            try await onboard.setMode(1)
            try await onboard.setCurrentProfile(profileSector)
        } catch {
            return .uncertainReason(.causedBy(key: "error.superstrike.activateFailed", arguments: [], cause: .capture(error)))
        }
        // Verify with a read back — an acknowledgement alone proves nothing.
        let mode = (try? await onboard.readMode()) ?? 0
        let running = (try? await onboard.readCurrentSector()) ?? 0
        guard mode == 1, running == profileSector else {
            return .uncertainReason(.localized(key: "error.superstrike.activationReadback", arguments: [String(mode), String(running)]))
        }
        return .onboardActivated
    }

    /// Applies a compound change to the running profile sector.
    ///
    /// The device is re-read first, the original sector and the complete control
    /// sector are backed up, the requested bytes are patched, the CRC is
    /// recomputed and the sector is written and read back.
    public func applyCompound(plan: SuperstrikePlan, baseline: ProfileSector, changes: CompoundChanges) async -> ApplyOutcome {
        guard !changes.isEmpty else {
            return .failedReason(.localized(key: "error.superstrike.noChanges", arguments: []))
        }
        guard plan.info.isSupportedModel, plan.info.profileFormat == Self.supportedProfileFormat else {
            return .failedReason(.localized(key: "error.superstrike.unsupportedFormat", arguments: []))
        }
        guard plan.info.sectorSize == Self.supportedSectorSize else {
            return .failedReason(.localized(key: "error.superstrike.sectorSize", arguments: [String(plan.info.sectorSize)]))
        }
        guard Self.isValidProfileSector(plan.storedSector, count: plan.info.profileCount) else {
            return .failedReason(.localized(key: "error.superstrike.invalidProfile", arguments: [String(plan.storedSector), String(plan.info.profileCount)]))
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
            return .failedReason(.causedBy(key: "error.superstrike.readState", arguments: [], cause: .capture(error)))
        }
        guard freshInfo.memoryModel == Self.supportedMemoryModel,
              freshInfo.profileFormat == Self.supportedProfileFormat,
              freshInfo.sectorSize == Self.supportedSectorSize,
              freshInfo.buttonCount == ProfileLayout.buttonSlotCount else {
            return .failedReason(.localized(key: "error.superstrike.unsupportedFormat", arguments: []))
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
            return .failedReason(.causedBy(key: "error.superstrike.readSector", arguments: [], cause: .capture(error)))
        }
        guard currentBytes == baseline.bytes else {
            return .rejectedStale
        }
        let activeIndex: Int?
        if changes.dpiX != nil || changes.dpiY != nil {
            do { activeIndex = try await onboard.readActiveResolution() }
            catch { return .failedReason(.capture(error)) }
            guard activeIndex == baseline.selectedDPIIndex else { return .rejectedStale }
        } else { activeIndex = baseline.activeDPIIndex }
        let current = ProfileSector(bytes: currentBytes, sector: plan.storedSector, activeDPIIndex: activeIndex)
        guard current.hasValidCRC else {
            return .failedReason(.localized(key: "error.superstrike.invalidCurrentCRC", arguments: []))
        }

        let patched: ProfileSector
        do {
            var base = current
            if !changes.hits.isEmpty {
                let caps = try await client.readHitsCapabilities()
                guard caps.buttonCount == 2 else { return .rejectedStale }
                // The wire's live settings may legitimately differ from NVM.
                // Save current values for both keys, preserving each NVM record's
                // own reserved bits, then apply only the requested draft fields.
                for button in 0..<caps.buttonCount {
                    let live = try await client.readHitsButton(button)
                    _ = try live.validatedRecord(maxActuation: caps.maxActuation, maxRapidTrigger: caps.maxRapidTrigger, maxHaptics: caps.maxHaptics)
                    base = try base.settingHITS(live)
                }
                for draft in changes.hits {
                    guard base.hitsButtons.indices.contains(draft.button) else { return .rejectedStale }
                    _ = try draft.applying(to: base.hitsButtons[draft.button], maxActuation: caps.maxActuation, maxRapidTrigger: caps.maxRapidTrigger, maxHaptics: caps.maxHaptics)
                }
            }
            patched = try Self.patch(base, changes: changes)
        } catch {
            return .failedReason(.capture(error))
        }
        guard patched.bytes != current.bytes else {
            return .failedReason(.localized(key: "error.superstrike.noContentChange", arguments: []))
        }

        // The backup has to exist before anything is sent to the device. The
        // control sector is part of it — a partial backup is no backup.
        let control = try? await onboard.readSector(0x0000, size: plan.info.sectorSize)
        guard let controlBytes = control, controlBytes.count == plan.info.sectorSize else {
            return .backupFailedReason(.localized(key: "error.superstrike.controlBackupRead", arguments: []))
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
            return .backupFailedReason(.capture(error))
        }
        // As close to the write as possible: the mode and the running profile
        // are read again, so a change in between stops the write.
        do {
            let modeNow = try await onboard.readMode()
            let slotNow = try await onboard.readCurrentSector()
            if changes.dpiX != nil || changes.dpiY != nil {
                guard try await onboard.readActiveResolution() == current.selectedDPIIndex else { return .rejectedStale }
            }
            guard modeNow == 1, slotNow == plan.storedSector else {
                return .rejectedStale
            }
        } catch {
            return .failedReason(.causedBy(key: "error.superstrike.lastCheck", arguments: [], cause: .capture(error)))
        }
        do {
            let outcome = try await onboard.writeSector(plan.storedSector, bytes: patched.bytes)
            switch outcome {
            case .verified:
                if changes.dpiX != nil || changes.dpiY != nil {
                    do {
                        let selected = try await onboard.readActiveResolution()
                        let actual = try await client.readSensorDPI()
                        guard selected == patched.selectedDPIIndex, actual.x == patched.dpiX, actual.y == patched.dpiY else {
                            return .uncertainReason(.localized(key: "error.profile.dpiVerify", arguments: []))
                        }
                    } catch { return .uncertainReason(.capture(error)) }
                }
                // Persistence alone does not prove that the running settings changed.
                if !changes.hits.isEmpty {
                    do {
                        for expected in patched.hitsButtons {
                            let live = try await client.readHitsButton(expected.button)
                            guard try live.validatedRecord() == expected.validatedRecord() else {
                                return .uncertainReason(.localized(key: "error.features.hitsVerify", arguments: []))
                            }
                        }
                    } catch { return .uncertainReason(.capture(error)) }
                }
                return .applied(backup: backupURL)
            case .uncertain(let detail):
                return .uncertainReason(.external(detail))
            case .uncertainReason(let reason):
                return .uncertainReason(reason)
            case .failedBeforeBegin(let detail):
                return .failedReason(.external(detail))
            case .failedBeforeBeginReason(let reason):
                return .failedReason(reason)
            }
        } catch {
            return .uncertainReason(.capture(error))
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
        for draft in changes.hits { patched = try patched.settingHITS(draft) }
        return patched.withRecomputedCRC()
    }

    private func describe(_ changes: CompoundChanges) -> String {
        var parts: [String] = []
        if let x = changes.dpiX, let y = changes.dpiY { parts.append("DPI \(x)×\(y)") }
        if let hz = changes.reportRateHz { parts.append("回報率 \(hz) Hz") }
        for change in changes.buttons { parts.append("按鍵槽位 \(change.slot)") }
        for draft in changes.hits { parts.append("HITS \(draft.button)") }
        return parts.joined(separator: ", ")
    }
}
