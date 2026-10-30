import SwiftUI
import UTUVOMouseCore
import UTUVOMouseIO

/// The detail pane of one device.
struct DeviceDetailView: View {
    @Environment(AppModel.self) private var model
    let snapshot: DeviceSnapshot

    @State private var tab = 0

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            header
            if snapshot.needsInputMonitoring && !model.isDemo {
                GroupBox(AppLocalization.text("device.inputMonitoring")) {
                    Text(snapshot.accessError ?? AppLocalization.text("device.permission.deniedDefault")).foregroundStyle(.secondary)
                    Button(AppLocalization.text("device.openSystemSettings")) { model.openInputMonitoringSettings() }
                }
            }
            if snapshot.identity.model.supportsConfiguration {
            HStack(spacing: 20) {
                if snapshot.identity.model == .superstrike {
                    DetailTabButton(title: AppLocalization.text("ui.hits"), selected: tab == 0) { tab = 0 }
                    DetailTabButton(title: AppLocalization.text("ui.pointerButtons"), selected: tab == 1) { tab = 1 }
                } else {
                    DetailTabButton(title: AppLocalization.text("ui.pointerScroll"), selected: tab == 0) { tab = 0 }
                    DetailTabButton(title: AppLocalization.text("ui.buttons"), selected: tab == 1) { tab = 1 }
                    DetailTabButton(title: AppLocalization.text("ring.title"), selected: tab == 2) { tab = 2 }
                }
                Spacer(minLength: 0)
            }
            .overlay(alignment: .bottom) { Rectangle().fill(.primary.opacity(0.07)).frame(height: 1).offset(y: 2) }
            }
            switch snapshot.identity.model {
            case .superstrike:
                if tab == 0 { HITSControlSection(snapshot: snapshot) }
                else { ProfileControlSection(snapshot: snapshot) }
            case .mxMaster4:
                if tab == 2 { ActionRingSection(snapshot: snapshot) }
                else if tab == 1 { SideButtonSection(snapshot: snapshot) }
                else {
                    ClassicDPISection(snapshot: snapshot)
                    HStack(alignment: .top, spacing: 12) {
                        SmartShiftSection(snapshot: snapshot).frame(maxWidth: .infinity)
                        WheelSection(snapshot: snapshot).frame(maxWidth: .infinity)
                    }
                }
            default:
                UnavailableSection(title: AppLocalization.text("device.unsupported.title"), detail: AppLocalization.text("device.unsupported.detail"))
            }
            DiagnosticsView(snapshot: snapshot).padding(.top, 4)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .onChange(of: snapshot.id) { _, _ in tab = 0 }
    }

    private var header: some View {
        HStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 8) {
                Text(snapshot.identity.displayName(language: AppLocalization.localizer.language))
                    .font(.system(size: 22, weight: .semibold)).tracking(-0.4)
                    .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 12) {
                    Label(snapshot.identity.transport.displayTitle(language: AppLocalization.localizer.language), systemImage: "link")
                    if let percentage = snapshot.battery.percentage {
                        Label("\(percentage)%", systemImage: "battery.100")
                    } else if snapshot.identity.model.supportsConfiguration {
                        Text(AppLocalization.text("app.unknownBattery"))
                    }
                    if !snapshot.identity.model.supportsConfiguration {
                        Text(AppLocalization.text("device.readOnly"))
                    }
                }
                .font(.system(size: 11, weight: .medium)).foregroundStyle(.secondary)
                if snapshot.isDemo { Text(AppLocalization.text("device.demoData")).font(.caption).foregroundStyle(.orange) }
            }
            Spacer(minLength: 0)
            MouseIllustration(model: snapshot.identity.model).frame(width: 52, height: 60)
                .rotationEffect(.degrees(8))
        }
        .frame(minHeight: 60)

    }
}

/// The raw numbers, hidden behind a disclosure.
struct DiagnosticsView: View {
    let snapshot: DeviceSnapshot

    var body: some View {
        DisclosureGroup(AppLocalization.text("device.diagnostics")) {
            VStack(alignment: .leading, spacing: 3) {
                Text(AppLocalization.text("device.diagnostics.stableID", snapshot.identity.stableID))
                Text(AppLocalization.text("device.diagnostics.protocol", snapshot.protocolVersion ?? AppLocalization.text("common.unknown")))
                Text(AppLocalization.text("device.diagnostics.address", String(format: "0x%02X", snapshot.identity.deviceIndex)))
                if let plan = snapshot.plan {
                    Text(AppLocalization.text("device.diagnostics.mode", plan.isOnboardMode ? AppLocalization.text("device.profile.modeOnboard") : AppLocalization.text("device.profile.modeHost")))
                    Text(AppLocalization.text("device.diagnostics.sector", plan.storedSector, plan.isRunning ? AppLocalization.text("device.diagnostics.yes") : AppLocalization.text("device.diagnostics.no")))
                    Text(AppLocalization.localizer.profileFormatDiagnostic(profileFormat: plan.info.profileFormat, sectorSize: plan.info.sectorSize))
                }
                if let profile = snapshot.profile {
                    Text(AppLocalization.text("device.diagnostics.crc", profile.hasValidCRC ? AppLocalization.text("device.diagnostics.pass") : AppLocalization.text("device.diagnostics.fail")))
                }
                ForEach(snapshot.issues, id: \.self) { issue in
                    Text("・\(issue)")
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .font(.callout)
    }
}

/// A control that this build does not implement.
struct UnavailableSection: View {
    let title: String
    let detail: String

    var body: some View {
        GroupBox(title) {
            Text(detail)
                .font(.callout)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

/// DPI through the classic feature (0x2201) — MX Master 4 M.
struct ClassicDPISection: View {
    @Environment(AppModel.self) private var model
    let snapshot: DeviceSnapshot
    @State private var draft: Int?

    var body: some View {
        GroupBox(AppLocalization.text("device.dpi.title")) {
            if let dpi = snapshot.dpi, let current = dpi.current {
                HStack(spacing: 12) {
                    dpiValue(current)
                    Spacer(minLength: 8)
                    dpiControls(dpi.available)
                }
            } else { Text(AppLocalization.text("device.dpi.unknown")).foregroundStyle(.secondary) }
        }
        .onChange(of: snapshot.connectionEpoch) { _, _ in draft = nil }
    }
    private func dpiValue(_ current: Int) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 7) {
            Text(current.formatted()).font(.system(size: 28, weight: .medium)).monospacedDigit().tracking(-0.8)
            Text("DPI").font(.system(size: 11, weight: .medium)).foregroundStyle(.secondary)
        }
    }

    private func dpiControls(_ available: [Int]) -> some View {
        HStack(spacing: 8) {
            if available.isEmpty {
                Text(AppLocalization.text("device.dpi.unavailable")).font(.callout).foregroundStyle(.secondary)
            } else {
                Picker(AppLocalization.text("device.dpi.picker"), selection: $draft) {
                    Text(AppLocalization.text("common.select")).tag(Int?.none)
                    ForEach(available, id: \.self) { Text("\($0)").tag(Int?.some($0)) }
                }.labelsHidden().frame(width: 130).disabled(model.isBusy || model.isDemo)
                    .accessibilityLabel(AppLocalization.text("device.dpi.picker"))
                HStack(spacing: 8) {
                    Button(AppLocalization.text("common.cancel")) { draft = nil }.disabled(draft == nil)
                    Button(AppLocalization.text("common.apply")) {
                        guard let draft else { return }; Task { await model.applyClassicDPI(device: snapshot, value: draft) }
                    }.buttonStyle(.borderedProminent).disabled(draft == nil || model.isBusy || model.isDemo)
                }
            }
        }
    }

}

/// SmartShift (0x2111) — MX Master 4 M.
struct SmartShiftSection: View {
    @Environment(AppModel.self) private var model
    let snapshot: DeviceSnapshot
    @State private var mode: Int?
    @State private var threshold: Int?

    var body: some View {
        GroupBox(AppLocalization.text("device.smartShift.title")) {
            VStack(alignment: .leading, spacing: 8) {
                if let state = snapshot.smartShift, let currentMode = state.mode, let currentThreshold = state.threshold {
                    Picker(AppLocalization.text("device.smartShift.picker"), selection: Binding(
                        get: { mode ?? currentMode },
                        set: { mode = $0 == currentMode ? nil : $0 }
                    )) {
                        Text(AppLocalization.text("device.smartShift.free")).tag(1)
                        Text(AppLocalization.text("device.smartShift.ratchet")).tag(2)
                    }
                    .disabled(model.isBusy || model.isDemo)
                    Stepper(AppLocalization.text("device.smartShift.stepper", threshold ?? currentThreshold), value: Binding(
                        get: { threshold ?? currentThreshold },
                        set: { threshold = $0 == currentThreshold ? nil : $0 }
                    ), in: 1...254)
                        .disabled(model.isBusy || model.isDemo)
                    if let torque = state.torque {
                        Text(AppLocalization.text("device.smartShift.torque") + " \(torque)%")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    HStack(spacing: 8) {
                        Spacer(minLength: 0)
                        Button(AppLocalization.text("common.cancel")) { mode = nil; threshold = nil }
                            .disabled(mode == nil && threshold == nil)
                        Button(AppLocalization.text("common.apply")) {
                            Task { await model.applySmartShift(device: snapshot, mode: mode, threshold: threshold) }
                        }
                        .disabled((mode == nil && threshold == nil) || model.isBusy || model.isDemo)
                    }.controlSize(.small)
                } else {
                    Text(AppLocalization.text("device.smartShift.unknown"))
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .onChange(of: snapshot.connectionEpoch) { _, _ in mode = nil; threshold = nil }
    }
}

/// Wheel control (0x2121) — MX Master 4 M. The event target bit is not exposed.
struct WheelSection: View {
    @Environment(AppModel.self) private var model
    let snapshot: DeviceSnapshot
    @State private var inverted: Bool?
    @State private var highResolution: Bool?

    var body: some View {
        GroupBox(AppLocalization.text("device.wheel.title")) {
            VStack(alignment: .leading, spacing: 8) {
                if let state = snapshot.wheel {
                    Toggle(AppLocalization.text("device.wheel.inverted"), isOn: Binding(
                        get: { inverted ?? state.inverted ?? false },
                        set: { inverted = $0 }
                    ))
                    .toggleStyle(.switch)
                    .disabled(model.isBusy || model.isDemo)
                    Toggle(AppLocalization.text("device.wheel.highResolution"), isOn: Binding(
                        get: { highResolution ?? state.highResolution ?? false },
                        set: { highResolution = $0 }
                    ))
                    .toggleStyle(.switch)
                    .disabled(model.isBusy || model.isDemo)
                    HStack {
                        Spacer()
                        Button(AppLocalization.text("common.apply")) {
                            Task {
                                await model.applyWheel(
                                    device: snapshot,
                                    inverted: inverted,
                                    highResolution: highResolution
                                )
                            }
                        }
                        .disabled((inverted == nil && highResolution == nil) || model.isBusy || model.isDemo)
                        Button(AppLocalization.text("common.cancel")) { inverted = nil; highResolution = nil }
                            .disabled(inverted == nil && highResolution == nil)
                    }
                } else {
                    Text(AppLocalization.text("device.wheel.unknown"))
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .onChange(of: snapshot.connectionEpoch) { _, _ in inverted = nil; highResolution = nil }
    }
}

/// The side buttons of the MX Master 4 M (0x1B04).
struct SideButtonSection: View {
    @Environment(AppModel.self) private var model
    let snapshot: DeviceSnapshot
    @State private var actions: [UInt16: MappedAction] = [:]

    private var candidates: [ReprogramControl] {
        snapshot.reprogControls.filter { $0.isDivertCandidate && MXButtonRemapper.allowedCIDs.contains($0.cid) && $0.cid != MXButtonRemapper.ringCID }
    }

    private func selectedAction(for cid: UInt16) -> MappedAction {
        if let draft = actions[cid] { return draft }
        guard let rawValue = model.mappingPreferences.savedMapping(for: snapshot.id)?.choices[cid]?.rawValue else {
            return .native
        }
        return MappedAction(rawValue: rawValue) ?? .native
    }

    private var effectiveActions: [UInt16: MappedAction] {
        var values = Dictionary(uniqueKeysWithValues: candidates.map { ($0.cid, selectedAction(for: $0.cid)) })
        if let saved = model.mappingPreferences.savedMapping(for: snapshot.id), saved.enabledIntent,
           saved.choices[MXButtonRemapper.ringCID] == .actionsRing {
            values[MXButtonRemapper.ringCID] = .actionsRing
        }
        return values
    }

    /// The button name; the raw control ID stays in the diagnostics.
    private func buttonTitle(for control: ReprogramControl) -> String {
        switch control.cid {
        case 0x0052: AppLocalization.text("device.profile.middle")
        case 0x0053: AppLocalization.text("device.profile.back")
        case 0x0056: AppLocalization.text("device.profile.forward")
        default: AppLocalization.text("device.sideButtons.other")
        }
    }

    var body: some View {
        GroupBox(AppLocalization.text("device.sideButtons.title")) {
            VStack(alignment: .leading, spacing: 10) {
                if candidates.isEmpty {
                    Text(AppLocalization.text("device.sideButtons.none"))
                        .font(.callout)
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(candidates) { control in
                        HStack {
                            Text(buttonTitle(for: control))
                                .font(.callout)
                            Spacer()
                            Picker("", selection: Binding(
                                get: { selectedAction(for: control.cid) },
                                set: { actions[control.cid] = $0 }
                            )) {
                                ForEach(MappedAction.allCases.filter { $0 != .actionsRing }, id: \.self) { action in
                                    Text(action.title(language: AppLocalization.localizer.language)).tag(action)
                                }
                            }
                            .labelsHidden()
                            .frame(width: 170)
                            .disabled(model.isBusy || model.isDemo)
                        }
                    }
                    HStack {
                        Button(AppLocalization.text("device.mapping.enable")) {
                            Task { await model.enableButtonMapping(device: snapshot, mappings: effectiveActions) }
                        }
                        .disabled(model.isBusy || model.isDemo || !MXButtonRemapper.hasAccessibilityPermission)
                        Button(AppLocalization.text("device.mapping.disable")) {
                            Task { await model.disableButtonMapping(device: snapshot) }
                        }
                        .disabled(model.isBusy || model.isDemo)
                    }
                    Label(AppLocalization.text(model.mappingPresentationKey(for: snapshot)), systemImage: "info.circle")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    if !model.mappingPreferences.restoreEnabledAtLaunch {
                        Text(AppLocalization.text("device.mapping.restoreOptIn"))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    if !model.isDemo && !MXButtonRemapper.hasAccessibilityPermission {
                        Text(AppLocalization.text("device.sideButtons.accessibility"))
                            .font(.caption)
                            .foregroundStyle(.orange)
                        Button(AppLocalization.text("device.sideButtons.openAccessibility")) { model.openAccessibilitySettings() }
                    }
                    Text(AppLocalization.text("device.sideButtons.help"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .onChange(of: snapshot.id) { _, _ in actions = [:] }
        .onChange(of: snapshot.connectionEpoch) { _, _ in actions = [:] }
    }
}

/// HITS: actuation point, rapid trigger and click haptics (0x1B0C) — Superstrike.
struct HITSControlSection: View {
    @Environment(AppModel.self) private var model
    let snapshot: DeviceSnapshot

    var body: some View {
        GroupBox(AppLocalization.text("device.hits.title")) {
            VStack(alignment: .leading, spacing: 10) {
                if let capabilities = snapshot.hitsCapabilities {
                    HStack(alignment: .top, spacing: 16) {
                        ForEach(snapshot.hitsButtons, id: \.button) { config in
                            HITSButtonColumn(snapshot: snapshot, config: config, capabilities: capabilities)
                                .frame(minWidth: 0, maxWidth: .infinity)
                        }
                    }
                    Text(AppLocalization.text("device.hits.rapidHelp"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    Text(AppLocalization.text("device.hits.unknown"))
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

/// One analog button column.
struct HITSButtonColumn: View {
    @Environment(AppModel.self) private var model
    let snapshot: DeviceSnapshot
    let config: HitsButtonConfig
    let capabilities: HitsCapabilities

    @State private var actuation: Double?
    @State private var haptics: Double?
    @State private var rapidTriggerChoice: Int?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(AppLocalization.text(config.button == 0 ? "device.hits.left" : "device.hits.right"))
                .font(.headline)
            LabeledContent(AppLocalization.text("device.hits.actuation"), value: "\(Int(actuation ?? Double(config.actuation)))")
            Slider(
                value: Binding(get: { actuation ?? Double(config.actuation) }, set: { actuation = $0 }),
                in: 1...Double(min(capabilities.maxActuation, 10)),
                step: 1
            )
            .disabled(model.isBusy || model.isDemo)
            HStack(spacing: 8) {
                Text(AppLocalization.text("device.hits.rapidTrigger"))
                Spacer(minLength: 0)
                Picker(AppLocalization.text("device.hits.rapidTrigger"), selection: Binding(get: { rapidTriggerChoice ?? (config.rapidTriggerEnabled ? config.rapidTrigger : 0) }, set: { rapidTriggerChoice = $0 })) {
                    Text(AppLocalization.text("device.hits.off")).tag(0)
                    ForEach(1...max(1, min(capabilities.maxRapidTrigger, 5)), id: \.self) { value in
                        Text("\(value)").tag(value)
                    }
                }
                .labelsHidden().frame(width: 94)
                .accessibilityLabel(AppLocalization.text("device.hits.rapidTrigger"))
                .disabled(model.isBusy || model.isDemo)
            }
            LabeledContent(AppLocalization.text("device.hits.feedback"), value: "\(Int(haptics ?? Double(config.haptics)))")
            Slider(
                value: Binding(get: { haptics ?? Double(config.haptics) }, set: { haptics = $0 }),
                in: 0...Double(min(capabilities.maxHaptics, 5)),
                step: 1
            )
            .disabled(model.isBusy || model.isDemo)
            Button(AppLocalization.text("common.apply")) {
                let draft = HIDPPClient.HitsDraft(
                    button: config.button,
                    actuation: actuation.map { Int($0) },
                    rapidTrigger: rapidTriggerChoice,
                    haptics: haptics.map { Int($0) }
                )
                Task { await model.applyHITS(device: snapshot, draft: draft, capabilities: capabilities) }
            }
            .disabled((actuation == nil && haptics == nil && rapidTriggerChoice == nil) || model.isBusy || model.isDemo)
        }
        .frame(minWidth: 0, maxWidth: .infinity, alignment: .leading)
        .onChange(of: config) { _, _ in
            actuation = nil; haptics = nil; rapidTriggerChoice = nil
        }
        .onChange(of: snapshot.connectionEpoch) { _, _ in
            actuation = nil; haptics = nil; rapidTriggerChoice = nil
        }
    }
}

/// The onboard profile of the Superstrike: DPI, report rate and the side buttons.
struct ProfileControlSection: View {
    @Environment(AppModel.self) private var model
    let snapshot: DeviceSnapshot
    @State private var dpi: Int?
    @State private var rateHz: Int?
    @State private var middle: SideButtonChoice = .unchanged
    @State private var back: SideButtonChoice = .unchanged
    @State private var forward: SideButtonChoice = .unchanged

    var body: some View {
        GroupBox(AppLocalization.text("device.profile.title")) {
            VStack(alignment: .leading, spacing: 10) {
                if let plan = snapshot.plan, let profile = snapshot.profile {
                    HStack(spacing: 20) {
                        LabeledContent(AppLocalization.text("device.profile.mode"), value: AppLocalization.text(plan.isOnboardMode ? "device.profile.modeOnboard" : "device.profile.modeHost"))
                        LabeledContent(AppLocalization.text("device.profile.sector"), value: "\(plan.storedSector)")
                    }.font(.caption).foregroundStyle(.secondary)
                    if !plan.isRunning {
                        Text(AppLocalization.text("device.profile.notRunning"))
                            .font(.callout)
                            .foregroundStyle(.secondary)
                        Button(AppLocalization.text("device.profile.activate", plan.storedSector)) {
                            Task { await model.activateOnboard(device: snapshot, sector: plan.storedSector) }
                        }
                        .disabled(model.isBusy || model.isDemo)
                    }
                    HStack(alignment: .top, spacing: 20) {
                        VStack(alignment: .leading, spacing: 8) {
                            LabeledContent(AppLocalization.text("device.profile.dpi"), value: "\(profile.dpiX) / \(profile.dpiY)")
                            LabeledContent(AppLocalization.text("device.profile.reportRate"), value: "\(profile.reportRateHz) Hz")

                            Stepper(AppLocalization.text("device.profile.dpiStepper", dpi ?? profile.dpiX), onIncrement: {
                                dpi = snapshot.supportedProfileDPI.first { $0 > (dpi ?? profile.dpiX) } ?? dpi
                            }, onDecrement: {
                                dpi = snapshot.supportedProfileDPI.last { $0 < (dpi ?? profile.dpiX) } ?? dpi
                            })
                            .disabled(model.isBusy || model.isDemo || snapshot.supportedProfileDPI.isEmpty)
                            Picker(AppLocalization.text("device.profile.ratePicker"), selection: $rateHz) {
                                Text(AppLocalization.text("device.profile.noChange")).tag(Int?.none)
                                ForEach(ProfileLayout.reportRates, id: \.self) { hz in
                                    Text("\(hz) Hz").tag(Int?.some(hz))
                                }
                            }
                            .frame(maxWidth: .infinity)
                            .disabled(model.isBusy || model.isDemo)

                        }.frame(maxWidth: .infinity, alignment: .leading)
                        VStack(alignment: .leading, spacing: 8) {
                            Text(AppLocalization.text("device.profile.buttons"))
                                .font(.system(size: 12, weight: .semibold))
                            Picker(AppLocalization.text("device.profile.middle"), selection: $middle) {
                                ForEach(SideButtonChoice.allCases) { choice in
                                    Text(choice.title).tag(choice)
                                }
                            }
                            .frame(maxWidth: .infinity)
                            .disabled(model.isBusy || model.isDemo)
                            Picker(AppLocalization.text("device.profile.back"), selection: $back) {
                                ForEach(SideButtonChoice.allCases) { choice in
                                    Text(choice.title).tag(choice)
                                }
                            }
                            .frame(maxWidth: .infinity)
                            .disabled(model.isBusy || model.isDemo)
                            Picker(AppLocalization.text("device.profile.forward"), selection: $forward) {
                                ForEach(SideButtonChoice.allCases) { choice in
                                    Text(choice.title).tag(choice)
                                }
                            }
                            .frame(maxWidth: .infinity)
                            .disabled(model.isBusy || model.isDemo)

                        }.frame(maxWidth: .infinity, alignment: .leading)
                    }
                    HStack(spacing: 8) {
                        Spacer(minLength: 0)
                        Button(AppLocalization.text("common.cancel")) {
                            dpi = nil; rateHz = nil
                            middle = .unchanged; back = .unchanged; forward = .unchanged
                        }
                        .disabled(dpi == nil && rateHz == nil && middle == .unchanged && back == .unchanged && forward == .unchanged)
                        Button(AppLocalization.text("device.profile.applyAll")) {
                            var changes = CompoundChanges()
                            if let dpi {
                                changes.dpiX = dpi
                                changes.dpiY = dpi
                            }
                            changes.reportRateHz = rateHz
                            var buttons: [ButtonChange] = []
                            if let action = middle.action { buttons.append(ButtonChange(slot: 2, action: action)) }
                            if let action = back.action { buttons.append(ButtonChange(slot: 3, action: action)) }
                            if let action = forward.action { buttons.append(ButtonChange(slot: 4, action: action)) }
                            changes.buttons = buttons
                            Task { await model.applySuperstrike(device: snapshot, changes: changes) }
                        }
                        .disabled((dpi == nil && rateHz == nil && middle == .unchanged && back == .unchanged && forward == .unchanged)
                            || model.isBusy || model.isDemo)
                    }.controlSize(.small)
                    Text(AppLocalization.text("device.profile.savedPending"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    Text(AppLocalization.text("device.profile.unknown"))
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .onChange(of: snapshot.connectionEpoch) { _, _ in
            dpi = nil; rateHz = nil
            middle = .unchanged; back = .unchanged; forward = .unchanged
        }
    }
}

/// The assignments offered for a side button of the onboard profile.
enum SideButtonChoice: String, CaseIterable, Identifiable {
    case unchanged = "（不變更）"
    case disabled = "停用"
    case middle = "中鍵"
    case back = "上一頁"
    case forward = "下一頁"
    case copy = "複製"
    case paste = "貼上"
    case media = "媒體播放／暫停"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .unchanged: AppLocalization.text("device.choice.unchanged")
        case .disabled: AppLocalization.text("device.choice.disabled")
        case .middle: AppLocalization.text("device.choice.middle")
        case .back: AppLocalization.text("device.choice.back")
        case .forward: AppLocalization.text("device.choice.forward")
        case .copy: AppLocalization.text("device.choice.copy")
        case .paste: AppLocalization.text("device.choice.paste")
        case .media: AppLocalization.text("device.choice.media")
        }
    }

    /// The four byte button record, or nil when nothing should be written.
    var action: ButtonAction? {
        switch self {
        case .unchanged: nil
        case .disabled: ButtonAction(kind: .disabled)
        case .middle: ButtonAction(kind: .mouse, code: 0x0004)
        case .back: ButtonAction(kind: .mouse, code: 0x0008)
        case .forward: ButtonAction(kind: .mouse, code: 0x0010)
        // ⌘ is the modifier byte 0x08, C is 0x06 and V is 0x19.
        case .copy: ButtonAction(kind: .key, code: 0x06, modifiers: 0x08)
        case .paste: ButtonAction(kind: .key, code: 0x19, modifiers: 0x08)
        case .media: ButtonAction(kind: .consumer, code: 0x00CD)
        }
    }
}
