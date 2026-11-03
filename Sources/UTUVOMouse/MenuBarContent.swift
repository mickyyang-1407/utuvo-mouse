import SwiftUI
import AppKit
import UTUVOMouseCore
import UTUVOMouseSupport
import UTUVOMouseLocalization

enum MainWindow {
    static let id = "main"

    /// The main scene is a single `Window`: opening it brings the one window forward.
    @MainActor
    static func show(_ openWindow: OpenWindowAction) {
        openWindow(id: id)
        NSApp.activate()
    }
}

enum MenuBarPreferences {
    static let showIconKey = "showMenuBarIcon"
}

/// The menu bar menu: each mouse, its battery and its profiles.
struct MenuBarContent: View {
    @Environment(AppModel.self) private var model
    @Environment(\.openWindow) private var openWindow

    private var language: MouseLanguage { AppLocalization.localizer.language }

    var body: some View {
        if model.mice.isEmpty {
            Text(AppLocalization.text(model.isScanning ? "app.scanning" : "app.noDevices"))
        }
        ForEach(model.mice) { snapshot in
            Section(header(snapshot)) { profileItems(snapshot) }
            Divider()
        }
        if model.isDemo { Text(AppLocalization.text("app.demo")) }
        if let message = model.errorMessage { Text(message) }
        Button(AppLocalization.text("menu.open")) { MainWindow.show(openWindow) }
        SettingsLink { Text(AppLocalization.text("settings.openSettings")) }
        Button(AppLocalization.text("app.refresh")) { Task { await model.refresh() } }
            .disabled(model.isBusy)
        Divider()
        Button(AppLocalization.text("menu.quit")) { NSApp.terminate(nil) }
    }

    private func header(_ snapshot: DeviceSnapshot) -> String {
        let name = snapshot.identity.displayName(language: language)
        guard let percentage = snapshot.battery.percentage else { return name }
        return "\(name) — \(percentage)%"
    }

    @ViewBuilder
    private func profileItems(_ snapshot: DeviceSnapshot) -> some View {
        let writable = !model.isDemo && !model.isBusy && !snapshot.needsInputMonitoring
        switch snapshot.identity.model {
        case .superstrike:
            if let plan = snapshot.plan, !plan.enabledSectors.isEmpty {
                let active = model.activeOnboardSector(for: snapshot)
                ForEach(plan.enabledSectors, id: \.self) { sector in
                    Toggle(AppLocalization.text("profile.onboardName", sector), isOn: Binding(
                        get: { active == sector },
                        set: { _ in Task { await model.activateOnboard(device: snapshot, sector: sector) } }
                    ))
                    .disabled(!writable || active == sector)
                }
            } else {
                Text(AppLocalization.text("profile.none"))
            }
        case .mxMaster4:
            let active = model.activeMXProfile(for: snapshot)
            ForEach(model.mxProfiles.profiles) { profile in
                Toggle(profile.name, isOn: Binding(
                    get: { active?.id == profile.id },
                    set: { _ in Task { await model.applyMXProfile(device: snapshot, profile: profile) } }
                ))
                .disabled(!writable || active?.id == profile.id)
            }
            Button(AppLocalization.text("profile.saveCurrent")) { model.saveMXProfile(from: snapshot) }
                .disabled(model.isDemo || !snapshot.isStateAuthoritative)
        default:
            Text(AppLocalization.text("device.readOnly"))
        }
    }
}

/// Profiles inside the main window, next to the controls they change.
struct ProfilesSection: View {
    @Environment(AppModel.self) private var model
    let snapshot: DeviceSnapshot
    @State private var renaming: UUID?
    @State private var draftName = ""

    var body: some View {
        GroupBox(AppLocalization.text("profile.title")) {
            switch snapshot.identity.model {
            case .superstrike: onboard
            default: appSide
            }
        }
    }

    private var writable: Bool { !model.isDemo && !model.isBusy && !snapshot.needsInputMonitoring }

    @ViewBuilder
    private var onboard: some View {
        if let plan = snapshot.plan, !plan.enabledSectors.isEmpty {
            let active = model.activeOnboardSector(for: snapshot)
            HStack(spacing: 8) {
                ForEach(plan.enabledSectors, id: \.self) { sector in
                    ProfileChip(title: AppLocalization.text("profile.onboardName", sector), active: active == sector) {
                        Task { await model.activateOnboard(device: snapshot, sector: sector) }
                    }
                    .disabled(!writable || active == sector)
                }
                Spacer(minLength: 0)
            }
            Text(AppLocalization.text("profile.onboardHelp")).font(.caption).foregroundStyle(.secondary)
        } else {
            Text(AppLocalization.text("profile.none")).foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private var appSide: some View {
        let active = model.activeMXProfile(for: snapshot)
        if model.mxProfiles.profiles.isEmpty {
            Text(AppLocalization.text("profile.empty")).font(.callout).foregroundStyle(.secondary)
        }
        ForEach(model.mxProfiles.profiles) { profile in
            HStack(spacing: 10) {
                if renaming == profile.id {
                    TextField(AppLocalization.text("profile.name"), text: $draftName)
                        .textFieldStyle(.roundedBorder).frame(maxWidth: 200)
                        .onSubmit { model.mxProfiles.rename(profile.id, to: draftName); renaming = nil }
                } else {
                    ProfileChip(title: profile.name, active: active?.id == profile.id) {
                        Task { await model.applyMXProfile(device: snapshot, profile: profile) }
                    }
                    .disabled(!writable || active?.id == profile.id)
                }
                Text(summary(profile)).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                Spacer(minLength: 0)
                Button(AppLocalization.text("profile.rename")) {
                    draftName = profile.name; renaming = renaming == profile.id ? nil : profile.id
                }.buttonStyle(.borderless).disabled(model.isDemo)
                Button(role: .destructive) { model.mxProfiles.remove(profile.id) } label: {
                    Image(systemName: "trash")
                }
                .buttonStyle(.borderless)
                .disabled(model.isDemo)
                .help(AppLocalization.text("profile.delete"))
                .accessibilityLabel(AppLocalization.text("profile.delete"))
            }
        }
        HStack {
            Button(AppLocalization.text("profile.saveCurrent")) { model.saveMXProfile(from: snapshot) }
                .disabled(model.isDemo || !snapshot.isStateAuthoritative)
            Spacer(minLength: 0)
        }
        Text(AppLocalization.text("profile.appHelp")).font(.caption).foregroundStyle(.secondary)
    }

    private func summary(_ profile: MXProfile) -> String {
        var parts: [String] = []
        if let dpi = profile.dpi { parts.append("\(dpi.formatted()) DPI") }
        if let mode = profile.smartShiftMode {
            parts.append(AppLocalization.text(mode == 2 ? "profile.summary.ratchet" : "profile.summary.free"))
        }
        if profile.wheelInverted == true { parts.append(AppLocalization.text("profile.summary.inverted")) }
        return parts.joined(separator: " · ")
    }
}

/// A profile pill: filled when the mouse reports it is the active one.
struct ProfileChip: View {
    let title: String
    let active: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                if active { Image(systemName: "checkmark").font(.system(size: 10, weight: .bold)) }
                Text(title).font(.system(size: 12, weight: active ? .semibold : .medium))
            }
            .foregroundStyle(active ? Color.white : .primary)
            .padding(.horizontal, 12).padding(.vertical, 5)
            .background(active ? MouseTheme.accent : Color.primary.opacity(0.06), in: Capsule())
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(active ? [.isSelected] : [])
    }
}
