import Foundation
import Observation
import UTUVOMouseLocalization

/// The only actions that may be restored for an MX button.
public enum MXMappingAction: String, Codable, CaseIterable, Sendable {
    case native
    case copy
    case paste
    case actionsRing
}

/// A saved choice and the user's explicit request to keep it enabled.
public struct MXSavedMapping: Codable, Equatable, Sendable {
    public var deviceID: String
    public var choices: [UInt16: MXMappingAction]
    public var enabledIntent: Bool

    public init(deviceID: String, choices: [UInt16: MXMappingAction], enabledIntent: Bool) {
        self.deviceID = deviceID
        self.choices = choices
        self.enabledIntent = enabledIntent
    }
}

/// The complete, versioned app-only mapping preference file.
public struct MXMappingPreferenceDocument: Codable, Equatable, Sendable {
    public static let currentVersion = 1
    public static let allowedCIDs: Set<UInt16> = [0x0052, 0x0053, 0x0056, 0x01A0]

    public var version: Int
    public var restoreEnabledAtLaunch: Bool
    public var mappingsByDeviceID: [String: MXSavedMapping]

    public init(
        version: Int = currentVersion,
        restoreEnabledAtLaunch: Bool = false,
        mappingsByDeviceID: [String: MXSavedMapping] = [:]
    ) {
        self.version = version
        self.restoreEnabledAtLaunch = restoreEnabledAtLaunch
        self.mappingsByDeviceID = mappingsByDeviceID
    }

    /// Validates all persisted values before the caller can use them.
    public func validate() throws {
        guard version == Self.currentVersion else {
            throw MXMappingPreferenceError.unsupportedVersion(version)
        }
        for (key, mapping) in mappingsByDeviceID {
            guard Self.isStableDeviceID(key), mapping.deviceID == key else {
                throw MXMappingPreferenceError.invalidDeviceID
            }
            guard mapping.choices.keys.allSatisfy(Self.allowedCIDs.contains) else {
                throw MXMappingPreferenceError.invalidControl
            }
            guard mapping.choices.allSatisfy({ cid, action in
                action == .native || ((cid == 0x01A0) == (action == .actionsRing))
            }) else { throw MXMappingPreferenceError.invalidControl }
            if mapping.enabledIntent && !mapping.choices.values.contains(where: { $0 != .native }) {
                throw MXMappingPreferenceError.emptyEnabledMapping
            }
        }
    }

    public static func isStableDeviceID(_ value: String) -> Bool {
        guard value.hasPrefix("sha256:") else { return false }
        let digest = value.dropFirst("sha256:".count)
        return digest.count == 16 && digest.allSatisfy { $0.isHexDigit }
    }
}

public enum MXMappingPreferenceError: Error, LocalizedError, Equatable {
    case unsupportedVersion(Int)
    case invalidDeviceID
    case invalidControl
    case emptyEnabledMapping
    case unavailable(String)
    case storageUnavailable

    public func message(language: MouseLanguage) -> String {
        let text = MouseLocalizer(language: language)
        return switch self {
        case .unsupportedVersion(let version): text.string("error.mapping.unsupportedVersion", arguments: [version])
        case .invalidDeviceID: text.string("error.mapping.invalidDeviceID")
        case .invalidControl: text.string("error.mapping.invalidControl")
        case .emptyEnabledMapping: text.string("error.mapping.empty")
        case .unavailable(let message): text.string("error.mapping.unavailable", arguments: [message])
        case .storageUnavailable: text.string("error.mapping.storageUnavailable")
        }
    }

    public var errorDescription: String? {
        switch self {
        case .unsupportedVersion(let version): "不支援側鍵設定檔版本：\(version)"
        case .invalidDeviceID: "側鍵設定檔的裝置識別資料不正確。"
        case .invalidControl: "側鍵設定檔含有不支援的按鍵。"
        case .emptyEnabledMapping: "沒有可還原的複製或貼上設定。"
        case .unavailable(let message): "無法儲存側鍵設定：\(message)"
        case .storageUnavailable: "側鍵設定儲存位置無法使用。"
        }
    }
}

/// Injected file boundary so preference policy tests never touch real app data.
@MainActor
public protocol MXMappingPreferenceStoring {
    func load() throws -> MXMappingPreferenceDocument
    func save(_ document: MXMappingPreferenceDocument) throws
}

/// JSON storage used by the app. Tests pass a URL inside a temporary directory.
@MainActor
public final class FileMXMappingPreferenceStore: MXMappingPreferenceStoring {
    private let fileURL: URL

    public init(fileURL: URL) {
        self.fileURL = fileURL
    }

    public static func applicationSupportFileURL() throws -> URL {
        let root = try FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: false
        )
        return root
            .appendingPathComponent("UTUVO Mouse", isDirectory: true)
            .appendingPathComponent("mx-mappings-v1.json", isDirectory: false)
    }

    public func load() throws -> MXMappingPreferenceDocument {
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            return MXMappingPreferenceDocument()
        }
        let data = try Data(contentsOf: fileURL)
        let document = try JSONDecoder().decode(MXMappingPreferenceDocument.self, from: data)
        try document.validate()
        return document
    }

    public func save(_ document: MXMappingPreferenceDocument) throws {
        try document.validate()
        let directory = fileURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        try encoder.encode(document).write(to: fileURL, options: .atomic)
    }
}

/// In-memory storage for demo mode; it never reads or changes live preferences.
@MainActor
public final class MemoryMXMappingPreferenceStore: MXMappingPreferenceStoring {
    private var document = MXMappingPreferenceDocument()

    public init() {}

    public func load() throws -> MXMappingPreferenceDocument { document }

    public func save(_ document: MXMappingPreferenceDocument) throws {
        try document.validate()
        self.document = document
    }
}

/// Main-actor state shared by the app and Settings. A read or write error makes
/// persistence unavailable, so no automatic restore or successful-enable claim
/// can be based on defaults substituted for corrupt data.
@MainActor
@Observable
public final class MXMappingPreferences {
    public private(set) var document = MXMappingPreferenceDocument()
    public private(set) var lastError: String?
    public private(set) var lastErrorReason: MXMappingPreferenceError?
    public private(set) var storageReady = false

    @ObservationIgnored private let store: (any MXMappingPreferenceStoring)?

    public init(store: (any MXMappingPreferenceStoring)?, unavailableReason: String? = nil) {
        self.store = store
        if let store {
            do {
                let loaded = try store.load()
                try loaded.validate()
                document = loaded
                storageReady = true
            } catch {
                lastError = error.localizedDescription
                lastErrorReason = Self.preferenceError(for: error)
            }
        } else {
            lastError = unavailableReason ?? "設定儲存位置無法使用。"
            lastErrorReason = unavailableReason.map(MXMappingPreferenceError.unavailable) ?? .storageUnavailable
        }
    }

    public var restoreEnabledAtLaunch: Bool { document.restoreEnabledAtLaunch }

    public func savedMapping(for deviceID: String) -> MXSavedMapping? {
        guard storageReady, MXMappingPreferenceDocument.isStableDeviceID(deviceID) else { return nil }
        return document.mappingsByDeviceID[deviceID]
    }

    /// Checks identity, allowed controls, and the file boundary before any device action.
    public func validateEnable(deviceID: String, choices: [UInt16: MXMappingAction]) throws {
        guard storageReady else {
            throw lastErrorReason ?? .storageUnavailable
        }
        var updated = document
        updated.mappingsByDeviceID[deviceID] = MXSavedMapping(
            deviceID: deviceID,
            choices: choices,
            enabledIntent: true
        )
        try updated.validate()
    }

    /// Persists only after the remapper has verified a user's explicit enable.
    public func recordVerifiedEnable(deviceID: String, choices: [UInt16: MXMappingAction]) throws {
        guard storageReady, let store else {
            throw lastErrorReason ?? .storageUnavailable
        }
        try validateEnable(deviceID: deviceID, choices: choices)
        var updated = document
        updated.mappingsByDeviceID[deviceID] = MXSavedMapping(
            deviceID: deviceID,
            choices: choices,
            enabledIntent: true
        )
        try updated.validate()
        do {
            try store.save(updated)
            document = updated
            lastError = nil
            lastErrorReason = nil
        } catch {
            lastError = error.localizedDescription
            lastErrorReason = Self.preferenceError(for: error)
            storageReady = false
            throw error
        }
    }

    /// Explicit Disable clears intent while keeping the last chosen actions.
    public func clearEnabledIntent(deviceID: String) throws {
        guard storageReady, let store else {
            throw lastErrorReason ?? .storageUnavailable
        }
        guard var mapping = document.mappingsByDeviceID[deviceID] else { return }
        mapping.enabledIntent = false
        var updated = document
        updated.mappingsByDeviceID[deviceID] = mapping
        do {
            try store.save(updated)
            document = updated
            lastError = nil
            lastErrorReason = nil
        } catch {
            lastError = error.localizedDescription
            lastErrorReason = Self.preferenceError(for: error)
            storageReady = false
            throw error
        }
    }

    public func setRestoreEnabledAtLaunch(_ enabled: Bool) {
        guard storageReady, let store else {
            lastError = lastError ?? "設定資料尚未驗證，無法變更自動還原選項。"
            lastErrorReason = lastErrorReason ?? .storageUnavailable
            return
        }
        var updated = document
        updated.restoreEnabledAtLaunch = enabled
        do {
            try store.save(updated)
            document = updated
            lastError = nil
            lastErrorReason = nil
        } catch {
            lastError = error.localizedDescription
            lastErrorReason = Self.preferenceError(for: error)
            storageReady = false
        }
    }

    private static func preferenceError(for error: Error) -> MXMappingPreferenceError {
        (error as? MXMappingPreferenceError) ?? .unavailable(error.localizedDescription)
    }
}
