import Foundation
import UTUVOMouseLocalization

/// An immutable copy of everything that is about to be changed on the device.
public struct SectorBackup: Codable, Sendable, Equatable {
    public var createdAt: Date
    /// The stable (non reversible) device identifier.
    public var deviceID: String
    /// The profile sector that was read.
    public var sector: Int
    public var sectorSize: Int
    /// The complete original sector, including its CRC.
    public var sectorBytes: [UInt8]
    /// The original control sector, when it could be read.
    public var controlBytes: [UInt8]
    /// Free form information about the device state at backup time.
    public var meta: [String: String]

    public init(
        createdAt: Date,
        deviceID: String,
        sector: Int,
        sectorSize: Int,
        sectorBytes: [UInt8],
        controlBytes: [UInt8],
        meta: [String: String]
    ) {
        self.createdAt = createdAt
        self.deviceID = deviceID
        self.sector = sector
        self.sectorSize = sectorSize
        self.sectorBytes = sectorBytes
        self.controlBytes = controlBytes
        self.meta = meta
    }
}

/// Stores backups before anything is written to a device.
public protocol BackupStoring: Sendable {
    /// Stores the backup and returns the file it was written to.
    /// Throwing means the write to the device must not happen.
    func store(_ backup: SectorBackup) throws -> URL
}

/// Writes backups as JSON files, one per change, under a directory of the app's own.
public struct FileBackupStore: BackupStoring {
    public let root: URL

    public init(root: URL) {
        self.root = root
    }

    /// The backup directory inside this application's own Application Support folder.
    public static func applicationSupportRoot(fileManager: FileManager = .default) throws -> URL {
        let base = try fileManager.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        let root = base
            .appendingPathComponent("UTUVO Mouse", isDirectory: true)
            .appendingPathComponent("Backups", isDirectory: true)
        try fileManager.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }

    public func store(_ backup: SectorBackup) throws -> URL {
        let fileManager = FileManager.default
        try fileManager.createDirectory(at: root, withIntermediateDirectories: true)
        let formatter = ISO8601DateFormatter()
        let stamp = formatter.string(from: backup.createdAt)
            .replacingOccurrences(of: ":", with: "-")
        let name = "sector-\(backup.sector)-\(stamp)-\(UUID().uuidString.prefix(8)).json"
        let url = root.appendingPathComponent(name)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(backup)
        // `.atomic` writes to a temporary file first and renames it, so a reader
        // never sees a half written backup.
        try data.write(to: url, options: [.atomic])
        // The backup must be readable again before it counts as a backup.
        let readBack = try Data(contentsOf: url)
        guard readBack == data else {
            throw BackupError.unreadable(url)
        }
        return url
    }
}

/// Errors of the backup store.
public enum BackupError: Error, Equatable, Sendable, LocalizedError {
    case unreadable(URL)

    public func message(language: MouseLanguage) -> String {
        let text = MouseLocalizer(language: language)
        return switch self {
        case .unreadable(let url): text.string("error.backup.unreadable", arguments: [url.lastPathComponent])
        }
    }

    public var errorDescription: String? {
        switch self {
        case .unreadable(let url): "備份寫入後無法讀回：\(url.lastPathComponent)"
        }
    }
}
