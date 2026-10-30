import Foundation
import Observation
import UTUVOMouseSupport
import UTUVOMouseLocalization

/// The state behind the settings window.
@MainActor
@Observable
final class SettingsModel {

    /// The login item.
    let launchItems: LaunchItemController

    /// The updater. `nil` in the demo mode: no updater is created at all.
    let updates: UpdateService?

    /// True in the demo mode.
    let isDemo: Bool

    /// What this process is allowed to do.
    let policy: RuntimePolicy

    /// The mapping preferences shared with the device window.
    let mappingPreferences: MXMappingPreferences
    let modelSupport: ModelSupportController
    let languagePreferenceStore: MouseLanguagePreferenceStoring
    var selectedLanguage: MouseLanguage
    var languageChangePending = false
    var languagePreferenceFailed = false
    private let languageAtLaunch: MouseLanguage

    init(
        exitCoordinator: AppExitCoordinator,
        isDemo: Bool,
        mappingPreferences: MXMappingPreferences,
        modelSupport: ModelSupportController,
        languagePreferenceStore: MouseLanguagePreferenceStoring
    ) {
        self.isDemo = isDemo
        self.policy = RuntimePolicy(isDemo: isDemo)
        self.mappingPreferences = mappingPreferences
        self.modelSupport = modelSupport
        self.languagePreferenceStore = languagePreferenceStore
        self.selectedLanguage = AppLocalization.selectedLanguage
        self.languageAtLaunch = AppLocalization.selectedLanguage
        if policy.isDemo {
            // The demo never registers a login item and never creates an
            // updater, so it cannot touch the system or the network.
            self.launchItems = LaunchItemController(registrar: DemoLaunchItemRegistrar(), policy: policy)
            self.updates = nil
        } else {
            self.launchItems = LaunchItemController(registrar: SystemLaunchItemRegistrar(), policy: policy)
            self.updates = UpdateService(
                configuration: UpdateConfiguration(bundle: .main),
                coordinator: exitCoordinator
            )
        }
    }

    func selectLanguage(_ language: MouseLanguage) {
        guard languagePreferenceStore.saveLanguageID(language.rawValue) else {
            languagePreferenceFailed = true
            return
        }
        selectedLanguage = language
        languageChangePending = MouseLanguageSelectionPolicy.requiresRelaunch(current: languageAtLaunch, requested: language)
        languagePreferenceFailed = false
    }

    /// Reads the real state. Called when the settings window appears.
    func load() async {
        await launchItems.refreshStatus()
    }
}
