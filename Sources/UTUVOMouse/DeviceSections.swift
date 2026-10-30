import SwiftUI
import UTUVOMouseCore
import UTUVOMouseIO

/// The detail pane of one device.
struct DeviceDetailView: View {
    @Environment(AppModel.self) private var model
    let snapshot: DeviceSnapshot

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header
            if snapshot.needsInputMonitoring && !model.isDemo {
                GroupBox(AppLocalization.text("device.inputMonitoring")) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(snapshot.accessError ?? AppLocalization.text("device.permission.deniedDefault"))
                            .font(.callout)
                            .foregroundStyle(.secondary)
                        Button(AppLocalization.text("device.openSystemSettings")) { model.openInputMonitoringSettings() }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            switch snapshot.identity.model {
            case .superstrike:
                HITSControlSection(snapshot: snapshot)
                ProfileControlSection(snapshot: snapshot)
            case .mxMaster4:
                Grid(alignment: .topLeading, horizontalSpacing: 12, verticalSpacing: 12) {
                    GridRow {
                        ClassicDPISection(snapshot: snapshot)
                        SmartShiftSection(snapshot: snapshot)
                    }
                    GridRow {
                        WheelSection(snapshot: snapshot)
                        SideButtonSection(snapshot: snapshot)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            case .unknown:
                UnavailableSection(
                    title: AppLocalization.text("device.unknown.title"),
                    detail: AppLocalization.text("device.unknown.detail")
                )
            case .receiver:
                UnavailableSection(
                    title: AppLocalization.text("device.receiver.title"),
                    detail: AppLocalization.text("device.receiver.detail")
                )
            }
            DiagnosticsView(snapshot: snapshot)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var header: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .firstTextBaseline, spacing: 14) {
                Image(systemName: "computermouse")
                    .font(.title2)
                    .foregroundStyle(.secondary)
                titleBlock
                Spacer(minLength: 8)
                statusBlock
            }
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 8) {
                    Image(systemName: "computermouse")
                        .font(.title2)
                        .foregroundStyle(.secondary)
                    titleBlock
                }
                statusBlock
            }
        }
    }

    private var titleBlock: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(snapshot.identity.model.displayTitle(language: AppLocalization.localizer.language))
                .font(.title3)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            if snapshot.isDemo {
                Text(AppLocalization.text("device.demoData"))
                    .font(.caption)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(.orange.opacity(0.25), in: Capsule())
            }
        }
    }

    private var statusBlock: some View {
        let language = AppLocalization.localizer.language
        let transport = snapshot.identity.transport.displayTitle(language: language)
        let battery = snapshot.battery.percentage.map { "\($0)%" } ?? AppLocalization.text("app.unknownBattery")
        return HStack(spacing: 12) {
            Label(transport, systemImage: "link")
                .font(.callout)
                .foregroundStyle(.secondary)
            if let percentage = snapshot.battery.percentage {
                Label("\(percentage)%", systemImage: batterySymbol(percentage))
                    .font(.callout)
                    .foregroundStyle(.secondary)
            } else {
                Label(AppLocalization.text("app.unknownBattery"), systemImage: "battery.0")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(AppLocalization.localizer.connectionStatusLabel(transport: transport, battery: battery))
        .fixedSize()
    }

    private func batterySymbol(_ percentage: Int) -> String {
        switch percentage {
        case 75...: "battery.100"
        case 40...: "battery.50"
        case 15...: "battery.25"
        default: "battery.0"
        }
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
            VStack(alignment: .leading, spacing: 8) {
                if let dpi = snapshot.dpi, let current = dpi.current {
                    LabeledContent(AppLocalization.text("device.dpi.value"), value: "\(current)")
                    if dpi.available.isEmpty {
                        Text(AppLocalization.text("device.dpi.unavailable"))
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    } else {
                        Picker(AppLocalization.text("device.dpi.picker"), selection: $draft) {
                            Text(AppLocalization.text("common.select")).tag(Int?.none)
                            ForEach(dpi.available, id: \.self) { value in
                                Text("\(value)").tag(Int?.some(value))
                            }
                        }
                        .frame(width: 200)
                        .disabled(model.isBusy || model.isDemo)
                        HStack {
                            Button(AppLocalization.text("common.apply")) {
                                guard let draft else { return }
                                Task { await model.applyClassicDPI(device: snapshot, value: draft) }
                            }
                            .disabled(draft == nil || model.isBusy || model.isDemo)
                            Button(AppLocalization.text("common.cancel")) { draft = nil }
                                .disabled(draft == nil)
                        }
                    }
                } else {
                    Text(AppLocalization.text("device.dpi.unknown"))
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .onChange(of: snapshot.connectionEpoch) { _, _ in draft = nil }
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
                    LabeledContent(AppLocalization.text("device.smartShift.mode"), value: AppLocalization.text(currentMode == 2 ? "device.smartShift.ratchet" : "device.smartShift.free"))
                    LabeledContent(AppLocalization.text("device.smartShift.threshold"), value: "\(currentThreshold)")
                    if let torque = state.torque {
                        LabeledContent(AppLocalization.text("device.smartShift.torque"), value: "\(torque)%")
                    }
                    Picker(AppLocalization.text("device.smartShift.picker"), selection: $mode) {
                        Text(AppLocalization.text("common.select")).tag(Int?.none)
                        Text(AppLocalization.text("device.smartShift.free")).tag(Int?.some(1))
                        Text(AppLocalization.text("device.smartShift.ratchet")).tag(Int?.some(2))
                    }
                    .frame(width: 200)
                    .disabled(model.isBusy || model.isDemo)
                    Stepper(AppLocalization.text("device.smartShift.stepper", threshold ?? currentThreshold), value: Binding(
                        get: { threshold ?? currentThreshold },
                        set: { threshold = $0 }
                    ), in: 1...254)
                        .disabled(model.isBusy || model.isDemo)
                    HStack {
                        Button(AppLocalization.text("common.apply")) {
                            Task { await model.applySmartShift(device: snapshot, mode: mode, threshold: threshold) }
                        }
                        .disabled((mode == nil && threshold == nil) || model.isBusy || model.isDemo)
                        Button(AppLocalization.text("common.cancel")) { mode = nil; threshold = nil }
                            .disabled(mode == nil && threshold == nil)
                    }
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
                    .disabled(model.isBusy || model.isDemo)
                    Toggle(AppLocalization.text("device.wheel.highResolution"), isOn: Binding(
                        get: { highResolution ?? state.highResolution ?? false },
                        set: { highResolution = $0 }
                    ))
                    .disabled(model.isBusy || model.isDemo)
                    HStack {
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
        snapshot.reprogControls.filter { $0.isDivertCandidate && MXButtonRemapper.allowedCIDs.contains($0.cid) }
    }

    private func selectedAction(for cid: UInt16) -> MappedAction {
        if let draft = actions[cid] { return draft }
        guard let rawValue = model.mappingPreferences.savedMapping(for: snapshot.id)?.choices[cid]?.rawValue else {
            return .native
        }
        return MappedAction(rawValue: rawValue) ?? .native
    }

    private var effectiveActions: [UInt16: MappedAction] {
        Dictionary(uniqueKeysWithValues: candidates.map { ($0.cid, selectedAction(for: $0.cid)) })
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
                                ForEach(MappedAction.allCases, id: \.self) { action in
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
            LabeledContent(AppLocalization.text("device.hits.actuation"), value: "\(config.actuation)")
            Slider(
                value: Binding(get: { actuation ?? Double(config.actuation) }, set: { actuation = $0 }),
                in: 1...Double(min(capabilities.maxActuation, 10)),
                step: 1
            )
            .disabled(model.isBusy || model.isDemo)
            LabeledContent(
                AppLocalization.text("device.hits.rapidTrigger"),
                value: config.rapidTriggerEnabled ? String(config.rapidTrigger) : AppLocalization.text("device.hits.off")
            )
            Picker(AppLocalization.text("device.hits.rapidTrigger"), selection: Binding(get: { rapidTriggerChoice ?? (config.rapidTriggerEnabled ? config.rapidTrigger : 0) }, set: { rapidTriggerChoice = $0 })) {
                Text(AppLocalization.text("device.hits.off")).tag(0)
                ForEach(1...max(1, min(capabilities.maxRapidTrigger, 5)), id: \.self) { value in
                    Text("\(value)").tag(value)
                }
            }
            .labelsHidden()
            .frame(width: 150)
            .disabled(model.isBusy || model.isDemo)
            LabeledContent(AppLocalization.text("device.hits.feedback"), value: "\(config.haptics)")
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
                    LabeledContent(AppLocalization.text("device.profile.mode"), value: AppLocalization.text(plan.isOnboardMode ? "device.profile.modeOnboard" : "device.profile.modeHost"))
                    LabeledContent(AppLocalization.text("device.profile.sector"), value: "\(plan.storedSector)")
                    if !plan.isRunning {
                        Text(AppLocalization.text("device.profile.notRunning"))
                            .font(.callout)
                            .foregroundStyle(.secondary)
                        Button(AppLocalization.text("device.profile.activate", plan.storedSector)) {
                            Task { await model.activateOnboard(device: snapshot, sector: plan.storedSector) }
                        }
                        .disabled(model.isBusy || model.isDemo)
                    }
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
                    .frame(width: 200)
                    .disabled(model.isBusy || model.isDemo)

                    Text(AppLocalization.text("device.profile.buttons"))
                        .font(.headline)
                    Picker(AppLocalization.text("device.profile.middle"), selection: $middle) {
                        ForEach(SideButtonChoice.allCases) { choice in
                            Text(choice.title).tag(choice)
                        }
                    }
                    .frame(width: 220)
                    .disabled(model.isBusy || model.isDemo)
                    Picker(AppLocalization.text("device.profile.back"), selection: $back) {
                        ForEach(SideButtonChoice.allCases) { choice in
                            Text(choice.title).tag(choice)
                        }
                    }
                    .frame(width: 220)
                    .disabled(model.isBusy || model.isDemo)
                    Picker(AppLocalization.text("device.profile.forward"), selection: $forward) {
                        ForEach(SideButtonChoice.allCases) { choice in
                            Text(choice.title).tag(choice)
                        }
                    }
                    .frame(width: 220)
                    .disabled(model.isBusy || model.isDemo)

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
                    Button(AppLocalization.text("common.cancel")) {
                        dpi = nil; rateHz = nil
                        middle = .unchanged; back = .unchanged; forward = .unchanged
                    }
                    .disabled(dpi == nil && rateHz == nil && middle == .unchanged && back == .unchanged && forward == .unchanged)
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
