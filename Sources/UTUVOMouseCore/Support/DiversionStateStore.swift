import Foundation

/// The state a device had before this app diverted a control.
///
/// It is written before the first change, so the original reporting can be put
/// back. A lease never overwrites the state another program set afterwards: it
/// only describes what this app changed.
public struct DiversionLease: Codable, Sendable, Equatable {
    /// The stable device identifier.
    public var deviceID: String
    /// When the lease was taken.
    public var createdAt: Date
    /// The reporting flags byte each diverted control had before.
    public var originals: [UInt16: UInt8]
    /// The action the user picked for each control.
    public var actions: [UInt16: String]

    public init(deviceID: String, createdAt: Date, originals: [UInt16: UInt8], actions: [UInt16: String]) {
        self.deviceID = deviceID
        self.createdAt = createdAt
        self.originals = originals
        self.actions = actions
    }
}

/// Stores the diversion lease of a device, atomically.
public struct DiversionStateStore: Sendable {
    public let root: URL

    public init(root: URL) {
        self.root = root
    }

    /// The lease directory inside this application's own Application Support folder.
    public static func applicationSupportRoot(fileManager: FileManager = .default) throws -> URL {
        let base = try fileManager.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        let root = base
            .appendingPathComponent("UTUVO Mouse", isDirectory: true)
            .appendingPathComponent("Diversions", isDirectory: true)
        try fileManager.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }

    private func url(for deviceID: String) -> URL {
        let safe = deviceID.replacingOccurrences(of: ":", with: "-")
        return root.appendingPathComponent("\(safe).json")
    }

    /// Reads the lease of a device, if there is one.
    public func load(deviceID: String) -> DiversionLease? {
        let file = url(for: deviceID)
        guard let data = try? Data(contentsOf: file) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(DiversionLease.self, from: data)
    }

    /// Writes the lease atomically.
    public func save(_ lease: DiversionLease) throws {
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(lease)
        // The decoder has to use the same date strategy, otherwise the lease
        // cannot be read back.
        try data.write(to: url(for: lease.deviceID), options: [.atomic])
    }

    /// Removes the lease of a device.
    public func clear(deviceID: String) throws {
        let file = url(for: deviceID)
        if FileManager.default.fileExists(atPath: file.path) {
            try FileManager.default.removeItem(at: file)
        }
    }
}

/// Errors of the diversion service.
public enum DiversionError: Error, Equatable, Sendable, LocalizedError {
    /// The control is already diverted by somebody else — this app does not steal it.
    case ownershipConflict(cid: UInt16)
    /// The device did not accept the change.
    case notAccepted(cid: UInt16)
    /// The control cannot be diverted at all.
    case notDivertable(cid: UInt16)
    /// The control is one of the two main buttons.
    case mainButton(cid: UInt16)
    /// The control is not one of the buttons this app may divert.
    case notAllowed(cid: UInt16)
    /// The device does not know this control.
    case unknownControl(cid: UInt16)
    /// The controls could not be put back — the device state is unknown.
    case rollbackUnconfirmed(cids: [UInt16])
    /// A control could not be put back — the device state is unknown.
    case restoreUnconfirmed(cid: UInt16)
    /// A diversion of this session is still active.
    case disableFirstRequired
    /// A lease of an earlier run is still active on the device.
    case reconnectRequired
    /// macOS has not granted the accessibility permission.
    case accessibilityRequired

    public var errorDescription: String? {
        switch self {
        case .ownershipConflict(let cid):
            "控制 \(String(cid, radix: 16, uppercase: true)) 已經被其他程式改道，本 App 不會接手"
        case .notAccepted(let cid):
            "裝置沒有接受控制 \(String(cid, radix: 16, uppercase: true)) 的改道，已回復原狀"
        case .notDivertable(let cid):
            "控制 \(String(cid, radix: 16, uppercase: true)) 不能改道"
        case .mainButton(let cid):
            "控制 \(String(cid, radix: 16, uppercase: true)) 是主鍵，不會改道"
        case .notAllowed(let cid):
            "控制 \(String(cid, radix: 16, uppercase: true)) 不是可以改道的側鍵，本 App 只處理中鍵、上一頁與下一頁鍵"
        case .unknownControl(let cid):
            "裝置沒有回報控制 \(String(cid, radix: 16, uppercase: true))，不會改道未知按鍵"
        case .rollbackUnconfirmed(let cids):
            "改道後的回復沒有得到裝置確認（\(cids.map { String($0, radix: 16, uppercase: true) }.joined(separator: ", "))），請重新連接滑鼠後確認"
        case .restoreUnconfirmed(let cid):
            "控制 \(String(cid, radix: 16, uppercase: true)) 沒有回復成功，請重新連接滑鼠後再試"
        case .disableFirstRequired:
            "還有按鍵處於改道狀態，請先按「停用並還原」再重新設定"
        case .reconnectRequired:
            "這個裝置還留著較早一次執行的改道設定，本 App 不會覆蓋它。請重新連接滑鼠後再試"
        case .accessibilityRequired:
            "需要「輔助使用」權限才能送出按鍵事件，請在「系統設定 → 隱私權與安全性 → 輔助使用」允許本 App 後再啟用"
        }
    }
}
