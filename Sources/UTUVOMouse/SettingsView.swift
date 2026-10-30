import SwiftUI
import AppKit
import ServiceManagement
import UTUVOMouseSupport
import UTUVOMouseLocalization

/// The settings window: the login item and the updater.
struct SettingsView: View {
    @Environment(SettingsModel.self) private var settings
    @Environment(AppModel.self) private var model

    var body: some View {
        Form {
            languageSection
            launchSection
            mappingRestoreSection
            modelSupportSection
            updateSection
        }
        .formStyle(.grouped)
        .tint(MouseTheme.accent)
        .scrollContentBackground(.hidden)
        .background(MouseTheme.canvas)
        .frame(width: 560, height: 560)
        .task { await settings.load() }
    }

    private var modelSupportSection: some View {
        Section(AppLocalization.text("support.title")) {
            Toggle(AppLocalization.text("support.queueToggle"), isOn: Binding(
                get: { settings.modelSupport.enabled },
                set: { settings.modelSupport.setEnabled($0, snapshots: model.snapshots) }
            ))
            .disabled(settings.isDemo)
            Text(AppLocalization.text("support.privacy"))
                .font(.caption).foregroundStyle(.secondary)
        }
    }

    private var languageSection: some View {
        Section(SettingsStrings.language.sectionTitle) {
            Picker(SettingsStrings.language.sectionTitle, selection: Binding(
                get: { settings.selectedLanguage },
                set: { settings.selectLanguage($0) }
            )) {
                Text(SettingsStrings.language.system).tag(MouseLanguage.system)
                Text(SettingsStrings.language.english).tag(MouseLanguage.english)
                Text(SettingsStrings.language.traditionalChinese).tag(MouseLanguage.traditionalChinese)
            }
            .disabled(settings.isDemo)
            Text(SettingsStrings.language.appliesAfterRelaunch)
                .font(.caption)
                .foregroundStyle(.secondary)
            if settings.isDemo {
                Text(SettingsStrings.language.demoNote)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else if settings.languageChangePending {
                Button(SettingsStrings.language.quitToApply) { NSApp.terminate(nil) }
                Text(SettingsStrings.language.quitRequested)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if settings.languagePreferenceFailed {
                Text(SettingsStrings.language.selectionFailed)
                    .font(.caption)
                    .foregroundStyle(.red)
            }
        }
    }

    // MARK: - MX button mapping restore

    private var mappingRestoreSection: some View {
        Section(SettingsStrings.mapping.sectionTitle) {
            Toggle(
                SettingsStrings.mapping.restoreAtLaunch,
                isOn: Binding(
                    get: { settings.mappingPreferences.restoreEnabledAtLaunch },
                    set: { settings.mappingPreferences.setRestoreEnabledAtLaunch($0) }
                )
            )
            .disabled(settings.isDemo || !settings.mappingPreferences.storageReady)

            Text(SettingsStrings.mapping.help)
                .font(.caption)
                .foregroundStyle(.secondary)

            if settings.isDemo {
                Text(SettingsStrings.mapping.demoNote)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else if let error = settings.mappingPreferences.lastErrorReason {
                Text(SettingsStrings.mapping.failure(AppLocalization.errorMessage(error)))
                    .font(.caption)
                    .foregroundStyle(.red)
            }
        }
    }

    // MARK: - Launch at login

    private var launchSection: some View {
        Section(SettingsStrings.launch.sectionTitle) {
            Toggle(
                SettingsStrings.launch.toggle,
                isOn: Binding(
                    get: { settings.launchItems.isEnabled },
                    set: { requested in Task { await settings.launchItems.setEnabled(requested) } }
                )
            )
            .disabled(settings.launchItems.isWorking || settings.isDemo)

            Text(SettingsStrings.launch.help)
                .font(.caption)
                .foregroundStyle(.secondary)

            if settings.isDemo {
                Text(SettingsStrings.launch.demoNote)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else if settings.launchItems.needsApproval {
                Button(SettingsStrings.launch.openSystemSettings) {
                    SMAppService.openSystemSettingsLoginItems()
                }
            }

            Text(launchStatusText)
                .font(.caption)
                .foregroundStyle(.secondary)

            if let error = settings.launchItems.lastError {
                Text(SettingsStrings.launch.failure(error))
                    .font(.caption)
                    .foregroundStyle(.red)
            }
        }
    }

    /// The state the system reports, not the request that was sent.
    private var launchStatusText: String {
        switch settings.launchItems.status {
        case .none: return SettingsStrings.launch.statusUnknown
        case .some(.enabled): return SettingsStrings.launch.statusEnabled
        case .some(.notRegistered): return SettingsStrings.launch.statusNotRegistered
        case .some(.requiresApproval): return SettingsStrings.launch.statusRequiresApproval
        case .some(.notFound): return SettingsStrings.launch.statusNotFound
        }
    }

    // MARK: - Updates

    @ViewBuilder
    private var updateSection: some View {
        Section(SettingsStrings.update.sectionTitle) {
            if let updates = settings.updates {
                HStack {
                    Text(SettingsStrings.update.currentVersion)
                    Spacer()
                    Text(updates.currentVersion).foregroundStyle(.secondary)
                }
                if let feed = updates.feedURL {
                    HStack {
                        Text(SettingsStrings.update.feed)
                        Spacer()
                        Text(feed.absoluteString)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                }
                HStack {
                    Text(SettingsStrings.update.lastCheck)
                    Spacer()
                    Text(updates.lastCheckDate.map { $0.formatted(date: .abbreviated, time: .shortened) }
                        ?? SettingsStrings.update.never)
                        .foregroundStyle(.secondary)
                }

                Toggle(
                    SettingsStrings.update.automaticChecks,
                    isOn: Binding(
                        get: { updates.automaticChecksEnabled },
                        set: { updates.automaticChecksEnabled = $0 }
                    )
                )
                Text(SettingsStrings.update.automaticChecksHelp)
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Toggle(
                    SettingsStrings.update.automaticDownloads,
                    isOn: Binding(
                        get: { updates.automaticDownloadsEnabled },
                        set: { updates.automaticDownloadsEnabled = $0 }
                    )
                )
                .disabled(!updates.automaticChecksEnabled)
                Text(SettingsStrings.update.automaticDownloadsHelp)
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Button(SettingsStrings.update.checkNow) {
                    updates.checkForUpdates()
                }
                .disabled(!updates.canCheckForUpdates)

                if updates.hasPendingInstall {
                    Text(SettingsStrings.update.pendingInstall)
                        .font(.caption)
                        .foregroundStyle(.orange)
                    Button(SettingsStrings.update.retryInstall) {
                        updates.retryPendingInstall()
                    }
                }

                if let message = updates.statusMessage {
                    Text(message)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } else {
                Text(SettingsStrings.update.demoNote)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if let problem = settings.updates?.configurationProblem {
                Text(configurationProblemText(problem))
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
        }
    }

    /// An honest reason, never a silent "nothing happened".
    private func configurationProblemText(_ problem: UpdateConfiguration.Problem) -> String {
        switch problem {
        case .missingFeedURL: return SettingsStrings.update.notConfiguredMissingFeed
        case .insecureFeedURL: return SettingsStrings.update.notConfiguredInsecure
        case .invalidFeedURL: return SettingsStrings.update.notConfiguredInvalidFeed
        case .missingPublicKey: return SettingsStrings.update.notConfiguredMissingKey
        case .invalidPublicKey: return SettingsStrings.update.notConfiguredInvalidKey
        }
    }
}
