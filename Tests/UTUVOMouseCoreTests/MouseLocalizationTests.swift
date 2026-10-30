import Foundation
import Testing
import UTUVOMouseLocalization
import UTUVOMouseSupport
import UTUVOMouseCore
import UTUVOMouseIO

@Suite("Mouse localization and language preference")
struct MouseLocalizationTests {
    @Test("language IDs stay stable and System uses the preferred app localization")
    func stableIDsAndSystemResolution() {
        #expect(MouseLanguage.system.rawValue == "system")
        #expect(MouseLanguage.english.rawValue == "en")
        #expect(MouseLanguage.traditionalChinese.rawValue == "zh-Hant")
        #expect(MouseLanguage.system.resolvedIdentifier(preferredLocalizations: ["zh-Hant-TW"]) == "zh-Hant")
        #expect(MouseLanguage.system.resolvedIdentifier(preferredLocalizations: ["en-US"]) == "en")
        #expect(MouseLocalizer(selectionID: nil, preferredLocalizations: ["zh-Hant"]).language == .traditionalChinese)
        #expect(MouseLocalizer(selectionID: "en", preferredLocalizations: ["zh-Hant"]).language == .english)
    }

    @Test("English and Traditional Chinese catalogs have matching stable keys and resolve samples")
    func catalogParity() {
        let english = MouseLocalizer(language: .english)
        let chinese = MouseLocalizer(language: .traditionalChinese)
        #expect(!english.catalogKeys().isEmpty)
        #expect(english.catalogKeys() == chinese.catalogKeys())
        #expect(english.string("app.title") == "UTUVO Mouse")
        #expect(chinese.string("language.section") == "語言")
        #expect(!english.string("device.mapping.restoreOptIn").hasPrefix("⟦"))
        #expect(english.resourceBundleURL.lastPathComponent == "UTUVOMouse_UTUVOMouseLocalization.bundle")
        #expect(english.string("missing.catalog.key").contains("missing.catalog.key"))
    }

    @Test("format arguments are localized by the selected catalog")
    func formattedArguments() {
        #expect(MouseLocalizer(language: .english).string("app.detectedMice", arguments: [1]) == "Connected mice: 1")
        #expect(MouseLocalizer(language: .english).string("app.detectedMice", arguments: [2]) == "Connected mice: 2")
        #expect(MouseLocalizer(language: .traditionalChinese).string("app.detectedMice", arguments: [2]) == "偵測到 2 支滑鼠")
    }

    @Test("English and Chinese selections write only app-domain language keys; System clears the override")
    func appDomainPreference() {
        let domain = FakeDefaultsDomain()
        let store = AppMouseLanguagePreferenceStore(domain: domain)
        #expect(store.selectedLanguageID() == nil)
        #expect(store.saveLanguageID(MouseLanguage.english.rawValue))
        #expect(domain.values["utuvo.mouse.language"] as? String == "en")
        #expect(domain.values["AppleLanguages"] as? [String] == ["en"])
        #expect(domain.values.count == 2)

        #expect(store.saveLanguageID(MouseLanguage.traditionalChinese.rawValue))
        #expect(domain.values["AppleLanguages"] as? [String] == ["zh-Hant"])
        #expect(store.saveLanguageID(MouseLanguage.system.rawValue))
        #expect(store.selectedLanguageID() == nil)
        #expect(domain.values.isEmpty)
    }

    @Test("the app-domain UserDefaults adapter round-trips in an isolated suite")
    func userDefaultsAdapterUsesAnInjectedIsolatedDomain() throws {
        let suiteName = "com.utuvo.mouse.tests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let store = AppMouseLanguagePreferenceStore(defaults: defaults)
        #expect(store.saveLanguageID(MouseLanguage.english.rawValue))
        #expect(store.selectedLanguageID() == "en")
        #expect(defaults.string(forKey: "utuvo.mouse.language") == "en")
        #expect(defaults.array(forKey: "AppleLanguages") as? [String] == ["en"])
        #expect(store.saveLanguageID(MouseLanguage.system.rawValue))
        #expect(defaults.persistentDomain(forName: suiteName)?["AppleLanguages"] == nil)
    }

    @Test("the production diagnostics formatter safely formats the UInt8 profile format")
    func diagnosticsFormatUsesTheUInt8Value() {
        let english = MouseLocalizer(language: .english)
        let chinese = MouseLocalizer(language: .traditionalChinese)
        #expect(english.profileFormatDiagnostic(profileFormat: UInt8(8), sectorSize: 255).contains("8"))
        #expect(english.profileFormatDiagnostic(profileFormat: UInt8(8), sectorSize: 255).contains("255"))
        #expect(chinese.profileFormatDiagnostic(profileFormat: UInt8(8), sectorSize: 255).contains("8"))
        #expect(chinese.profileFormatDiagnostic(profileFormat: UInt8(8), sectorSize: 255).contains("255"))
    }

    @Test("status accessibility names include the visible transport and battery values")
    func statusAccessibilityIncludesValues() {
        let english = MouseLocalizer(language: .english)
        let chinese = MouseLocalizer(language: .traditionalChinese)
        #expect(english.connectionStatusLabel(transport: "Bluetooth", battery: "90%") == "Bluetooth connection, battery 90%")
        #expect(chinese.connectionStatusLabel(transport: "藍牙", battery: "90%") == "藍牙連線，電量 90%")
    }

    @Test("selecting the current language does not require a restart")
    func languageSelectionPendingPolicy() {
        #expect(!MouseLanguageSelectionPolicy.requiresRelaunch(current: .english, requested: .english))
        #expect(MouseLanguageSelectionPolicy.requiresRelaunch(current: .english, requested: .traditionalChinese))
    }

    @Test("app-owned preference errors follow the selected language")
    func mappingPreferenceErrorsAreLocalized() {
        #expect(MXMappingPreferenceError.unsupportedVersion(7).message(language: .english).contains("Unsupported"))
        #expect(MXMappingPreferenceError.unsupportedVersion(7).message(language: .traditionalChinese).contains("不支援"))
    }

    @Test("Superstrike apply issues stay structured until localized presentation")
    func applyOutcomeUsesSelectedLanguageForItsReason() {
        let outcome = ApplyOutcome.failedReason(.localized(key: "error.profile.invalidMode", arguments: []))
        #expect(outcome.localizedSummary(language: .english).contains("Onboard mode"))
        #expect(outcome.localizedSummary(language: .traditionalChinese).contains("板載模式"))
        #expect(outcome.localizedSummary(language: .english).contains("Could not apply"))
    }

    @Test("app-owned HID++ reasons and battery notes use the selected catalog")
    func typedHIDPPAndBatteryNotes() {
        let failure = HIDPPError.localized(key: "error.features.hitsActuationRange", arguments: ["10"])
        #expect(failure.localizedMessage(language: .english) == "Actuation must be between 1 and 10.")
        #expect(failure.localizedMessage(language: .traditionalChinese).contains("觸發點必須介於"))

        let battery = BatteryStatus(noteLocalizationKey: "device.battery.note.noFeature")
        #expect(battery.message(language: .english)?.contains("unified battery") == true)
        #expect(battery.message(language: .traditionalChinese)?.contains("統一電池") == true)
    }

    @Test("saved mapping intent never proves a mapping is active on this connection")
    func configuredAndActualMappingStayDistinct() {
        #expect(MXMappingPresentationPolicy.state(
            savedEnabledIntent: true, hasSavedMapping: true, activeControlCount: 0,
            uncertainControlCount: 0, hasLease: false
        ) == .savedIntentOnly)
        #expect(MXMappingPresentationPolicy.state(
            savedEnabledIntent: true, hasSavedMapping: true, activeControlCount: 2,
            uncertainControlCount: 0, hasLease: true
        ) == .active)
        #expect(MXMappingPresentationPolicy.state(
            savedEnabledIntent: true, hasSavedMapping: true, activeControlCount: 0,
            uncertainControlCount: 1, hasLease: true
        ) == .uncertain)
        #expect(MXMappingPresentationPolicy.state(
            savedEnabledIntent: true, hasSavedMapping: true, activeControlCount: 0,
            uncertainControlCount: 0, hasLease: true
        ) == .previousLease)
    }

    @Test("stable model and action IDs gain localized display titles")
    func stableIDsAndDisplayTitles() {
        #expect(MouseModel.receiver.rawValue == "LIGHTSPEED 接收器")
        #expect(MouseModel.receiver.displayTitle(language: .english) == "LIGHTSPEED Receiver")
        #expect(MouseModel.receiver.displayTitle(language: .traditionalChinese) == "LIGHTSPEED 接收器")
        #expect(MappedAction.copy.rawValue == "copy")
        #expect(MappedAction.copy.title(language: .english) == "Copy")
        #expect(MappedAction.copy.title(language: .traditionalChinese) == "複製")
        let action = ButtonAction(kind: .mouse, code: 0x03)
        #expect(action.localizedSummary(language: .english) == "Mouse button 0x3")
        #expect(action.localizedSummary(language: .traditionalChinese) == "滑鼠鍵 0x3")
    }

    @Test("HID permission state is typed and the visible error follows the selected catalog")
    func typedHIDPermissionFailure() {
        let failure = HIDAccessFailure.inputMonitoringRequired
        #expect(failure.requiresInputMonitoring)
        #expect(failure.message(language: .english).contains("Input Monitoring"))
        #expect(failure.message(language: .traditionalChinese).contains("輸入監控"))
        #expect(!HIDAccessFailure.openFailed(0xE000_0001).requiresInputMonitoring)
    }
}

private final class FakeDefaultsDomain: MouseLanguageDefaultsDomain {
    var values: [String: Any] = [:]
    func string(forKey key: String) -> String? { values[key] as? String }
    func set(_ value: Any, forKey key: String) { values[key] = value }
    func removeObject(forKey key: String) { values[key] = nil }
}
