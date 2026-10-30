enum SettingsStrings {
    enum language {
        static let sectionTitle = AppLocalization.text("language.section")
        static let system = AppLocalization.text("language.system")
        static let english = AppLocalization.text("language.english")
        static let traditionalChinese = AppLocalization.text("language.traditionalChinese")
        static let appliesAfterRelaunch = AppLocalization.text("language.appliesAfterRelaunch")
        static let quitToApply = AppLocalization.text("language.quitToApply")
        static let quitRequested = AppLocalization.text("language.quitRequested")
        static let selectionFailed = AppLocalization.text("language.selectionFailed")
        static let demoNote = AppLocalization.text("language.demoNote")
    }

    enum launch {
        static let sectionTitle = AppLocalization.text("settings.login")
        static let toggle = AppLocalization.text("settings.login.toggle")
        static let help = AppLocalization.text("settings.login.help")
        static let statusNotRegistered = AppLocalization.text("settings.login.statusNotRegistered")
        static let statusEnabled = AppLocalization.text("settings.login.statusEnabled")
        static let statusRequiresApproval = AppLocalization.text("settings.login.statusApproval")
        static let statusNotFound = AppLocalization.text("settings.login.statusNotFound")
        static let statusUnknown = AppLocalization.text("settings.login.statusUnknown")
        static let openSystemSettings = AppLocalization.text("settings.login.openSystemSettings")
        static let demoNote = AppLocalization.text("settings.login.disabled")
        static func failure(_ error: String) -> String { AppLocalization.text("settings.login.failure", error) }
    }
    enum exit {
        static let writeRejected = AppLocalization.text("settings.exit.writeRejected")
        static let settingsHelp = AppLocalization.text("app.settings")
    }

    enum mapping {
        static let sectionTitle = AppLocalization.text("settings.mapping")
        static let restoreAtLaunch = AppLocalization.text("settings.mapping.restore")
        static let help = AppLocalization.text("settings.mapping.help")
        static let demoNote = AppLocalization.text("settings.mapping.demo")
        static func failure(_ error: String) -> String { AppLocalization.text("settings.mapping.failure", error) }
    }

    enum update {
        static let sectionTitle = AppLocalization.text("settings.update")
        static let checkNow = AppLocalization.text("settings.update.check")
        static let automaticChecks = AppLocalization.text("settings.update.automaticChecks")
        static let automaticDownloads = AppLocalization.text("settings.update.automaticDownloads")
        static let automaticChecksHelp = AppLocalization.text("settings.update.automaticChecksHelp")
        static let automaticDownloadsHelp = AppLocalization.text("settings.update.automaticDownloadsHelp")
        static let currentVersion = AppLocalization.text("settings.update.currentVersion")
        static let feed = AppLocalization.text("settings.update.feed")
        static let lastCheck = AppLocalization.text("settings.update.lastCheck")
        static let never = AppLocalization.text("settings.update.never")
        static let notConfiguredMissingFeed = AppLocalization.text("settings.update.missingFeed")
        static let notConfiguredInsecure = AppLocalization.text("settings.update.insecureFeed")
        static let notConfiguredInvalidFeed = AppLocalization.text("settings.update.invalidFeed")
        static let notConfiguredMissingKey = AppLocalization.text("settings.update.missingKey")
        static let notConfiguredInvalidKey = AppLocalization.text("settings.update.invalidKey")
        static let demoNote = AppLocalization.text("settings.update.demo")
        static let checking = AppLocalization.text("settings.update.checking")
        static let upToDate = AppLocalization.text("settings.update.upToDate")
        static func found(_ version: String) -> String { AppLocalization.text("settings.update.found", version) }
        static func aborted(_ message: String) -> String { AppLocalization.text("settings.update.aborted", message) }
        static let cleanupFailed = AppLocalization.text("settings.update.cleanupFailed")
        static let installing = AppLocalization.text("settings.update.installing")
        static let installDiscarded = AppLocalization.text("settings.update.discarded")
        static let pendingInstall = AppLocalization.text("settings.update.pending")
        static let retryInstall = AppLocalization.text("settings.update.retry")
    }
}
