import Foundation
import UTUVOMouseLocalization
import UTUVOMouseCore
import UTUVOMouseIO
import UTUVOMouseSupport

@MainActor
enum AppLocalization {
    static private(set) var localizer = MouseLocalizer(language: .english)
    static private(set) var selectedLanguage: MouseLanguage = .system
    static private(set) var preferenceStore: MouseLanguagePreferenceStoring = MemoryMouseLanguagePreferenceStore()

    static func configure(demoMode: Bool) {
        let store: MouseLanguagePreferenceStoring
        if demoMode {
            store = MemoryMouseLanguagePreferenceStore()
        } else {
            store = AppMouseLanguagePreferenceStore()
        }
        let persistedID = demoMode ? nil : store.selectedLanguageID()
        let selectedID = LaunchOptions.languageOverride?.rawValue ?? persistedID
        selectedLanguage = selectedID.flatMap(MouseLanguage.init(rawValue:)) ?? .system
        localizer = MouseLocalizer(
            selectionID: selectedID,
            preferredLocalizations: Bundle.main.preferredLocalizations
        )
        preferenceStore = store
    }

    @discardableResult
    static func select(_ language: MouseLanguage) -> Bool {
        guard preferenceStore.saveLanguageID(language.rawValue) else { return false }
        selectedLanguage = language
        return true
    }

    static func text(_ key: String, _ arguments: CVarArg...) -> String {
        localizer.string(key, arguments: arguments)
    }

    static func errorMessage(_ error: Error) -> String {
        switch error {
        case let error as HIDPPError:
            error.localizedMessage(language: localizer.language)
        case let error as DiversionError:
            error.message(language: localizer.language)
        case let error as BackupError:
            switch error {
            case .unreadable(let url): text("error.backup.unreadable", url.lastPathComponent)
            }
        case let error as MXMappingPreferenceError:
            error.message(language: localizer.language)
        case let error as IOKitHIDError:
            error.accessFailure.message(language: localizer.language)
        default:
            // Keep external NSError descriptions supplied by Apple frameworks intact.
            error.localizedDescription
        }
    }

    static func applyOutcomeSummary(_ outcome: ApplyOutcome) -> String {
        outcome.localizedSummary(language: localizer.language)
    }

}
