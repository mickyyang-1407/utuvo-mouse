import Foundation

public enum MouseLanguage: String, CaseIterable, Codable, Sendable {
    case system
    case english = "en"
    case traditionalChinese = "zh-Hant"

    public var title: String {
        switch self {
        case .system: "System"
        case .english: "English"
        case .traditionalChinese: "繁體中文"
        }
    }

    public func resolvedIdentifier(preferredLocalizations: [String]) -> String {
        switch self {
        case .system:
            let preferred = preferredLocalizations.first ?? "en"
            return preferred.hasPrefix("zh") ? "zh-Hant" : "en"
        case .english: return "en"
        case .traditionalChinese: return "zh-Hant"
        }
    }
}

public enum MouseLanguageSelectionPolicy {
    public static func requiresRelaunch(current: MouseLanguage, requested: MouseLanguage) -> Bool {
        current != requested
    }
}

public protocol MouseLanguagePreferenceStoring {
    func selectedLanguageID() -> String?
    func saveLanguageID(_ identifier: String?) -> Bool
}

public protocol MouseLanguageDefaultsDomain {
    func string(forKey key: String) -> String?
    func set(_ value: Any, forKey key: String)
    func removeObject(forKey key: String)
}

private struct UserDefaultsLanguageDomain: MouseLanguageDefaultsDomain {
    let defaults: UserDefaults
    func string(forKey key: String) -> String? { defaults.string(forKey: key) }
    func set(_ value: Any, forKey key: String) { defaults.set(value, forKey: key) }
    func removeObject(forKey key: String) { defaults.removeObject(forKey: key) }
}

public final class MemoryMouseLanguagePreferenceStore: MouseLanguagePreferenceStoring {
    public private(set) var identifier: String?

    public init(identifier: String? = nil) { self.identifier = identifier }
    public func selectedLanguageID() -> String? { identifier }
    public func saveLanguageID(_ identifier: String?) -> Bool { self.identifier = identifier; return true }
}

/// App-owned settings-domain adapter. Call only from the app; tests use the
/// in-memory store and never touch the user's defaults domain.
public final class AppMouseLanguagePreferenceStore: MouseLanguagePreferenceStoring {
    private let domain: MouseLanguageDefaultsDomain
    private let key = "utuvo.mouse.language"

    public init(defaults: UserDefaults = .standard) {
        domain = UserDefaultsLanguageDomain(defaults: defaults)
    }

    public init(domain: MouseLanguageDefaultsDomain) {
        self.domain = domain
    }

    public func selectedLanguageID() -> String? {
        domain.string(forKey: key)
    }

    public func saveLanguageID(_ identifier: String?) -> Bool {
        guard let identifier, identifier != MouseLanguage.system.rawValue else {
            domain.removeObject(forKey: key)
            domain.removeObject(forKey: "AppleLanguages")
            return true
        }
        domain.set(identifier, forKey: key)
        domain.set([identifier], forKey: "AppleLanguages")
        return true
    }
}

public struct MouseLocalizer {
    public let language: MouseLanguage
    private let bundle: Bundle

    public init(language: MouseLanguage) {
        self.init(language: language, bundle: Self.resources)
    }

    public init(language: MouseLanguage, bundle: Bundle) {
        self.language = language
        self.bundle = bundle
    }

    public init(selectionID: String?, preferredLocalizations: [String]) {
        self.init(selectionID: selectionID, preferredLocalizations: preferredLocalizations, bundle: Self.resources)
    }

    public init(selectionID: String?, preferredLocalizations: [String], bundle: Bundle) {
        let selection = selectionID.flatMap(MouseLanguage.init(rawValue:)) ?? .system
        self.language = selection == .system
            ? (selection.resolvedIdentifier(preferredLocalizations: preferredLocalizations) == "zh-Hant" ? .traditionalChinese : .english)
            : selection
        self.bundle = bundle
    }

    public func string(_ key: String, arguments: [CVarArg] = []) -> String {
        let value = catalogBundle.localizedString(forKey: key, value: "⟦\(key)⟧", table: "Localizable")
        guard !arguments.isEmpty else { return value }
        return String(format: value, locale: Locale(identifier: language == .traditionalChinese ? "zh-Hant" : "en"), arguments: arguments)
    }

    public func catalogKeys() -> Set<String> {
        guard let path = catalogBundle.path(forResource: "Localizable", ofType: "strings"),
              let values = NSDictionary(contentsOfFile: path) as? [String: String] else { return [] }
        return Set(values.keys)
    }

    public var resourceBundleURL: URL { bundle.bundleURL }

    public func profileFormatDiagnostic(profileFormat: UInt8, sectorSize: Int) -> String {
        string("device.diagnostics.format", arguments: [Int(profileFormat), sectorSize])
    }

    public func connectionStatusLabel(transport: String, battery: String) -> String {
        string("app.connectionStatus", arguments: [transport, battery])
    }

    private static var resources: Bundle { .module }

    private var catalogBundle: Bundle {
        let identifier = language == .traditionalChinese ? "zh-Hant" : "en"
        // SwiftPM's native builder emits lowercase zh-hant.lproj. Keep the
        // normal Xcode/Swift Build lookup first, then accept that packaged form.
        guard let url = bundle.url(forResource: identifier, withExtension: "lproj")
                ?? bundle.url(forResource: identifier.lowercased(), withExtension: "lproj"),
              let localized = Bundle(url: url) else { return bundle }
        return localized
    }
}
