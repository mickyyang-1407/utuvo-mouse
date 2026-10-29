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
            if snapshot.needsInputMonitoring {
                GroupBox("需要輸入監控") {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(snapshot.accessError ?? "macOS 尚未允許本 App 讀取這個裝置。")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                        Button("開啟系統設定") { model.openInputMonitoringSettings() }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            switch snapshot.identity.model {
            case .superstrike:
                HITSControlSection(snapshot: snapshot)
                ProfileControlSection(snapshot: snapshot)
            case .mxMaster4:
                ClassicDPISection(snapshot: snapshot)
                SmartShiftSection(snapshot: snapshot)
                WheelSection(snapshot: snapshot)
                SideButtonSection(snapshot: snapshot)
            case .unknown:
                UnavailableSection(
                    title: "無法辨識",
                    detail: "這個介面沒有回報可辨識的功能表。請確認滑鼠已配對。"
                )
            case .receiver:
                UnavailableSection(
                    title: "LIGHTSPEED 接收器",
                    detail: "接收器本身沒有設定可調。插槽上有已配對的 Superstrike 時才會讀取它的設定。"
                )
            }
            DiagnosticsView(snapshot: snapshot)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var header: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .firstTextBaseline, spacing: 14) {
                titleBlock
                Spacer(minLength: 8)
                statusBlock
            }
            VStack(alignment: .leading, spacing: 6) {
                titleBlock
                statusBlock
            }
        }
    }

    private var titleBlock: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(snapshot.identity.model.rawValue)
                .font(.title3)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            if snapshot.isDemo {
                Text("示範資料")
                    .font(.caption)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(.orange.opacity(0.25), in: Capsule())
            }
        }
    }

    private var statusBlock: some View {
        HStack(spacing: 12) {
            Label(snapshot.identity.transport.rawValue, systemImage: "link")
                .font(.callout)
                .foregroundStyle(.secondary)
            if let percentage = snapshot.battery.percentage {
                Label("\(percentage)%", systemImage: batterySymbol(percentage))
                    .font(.callout)
                    .foregroundStyle(.secondary)
            } else {
                Label("電量未知", systemImage: "battery.0")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
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
        DisclosureGroup("診斷資訊") {
            VStack(alignment: .leading, spacing: 3) {
                Text("穩定識別碼：\(snapshot.identity.stableID)")
                Text("HID++ 版本：\(snapshot.protocolVersion ?? "未知")")
                Text("HID++ 位址：\(String(format: "0x%02X", snapshot.identity.deviceIndex))")
                if let plan = snapshot.plan {
                    Text("板載模式：\(plan.isOnboardMode ? "板載" : "主控")")
                    Text("設定檔：\(plan.storedSector)（正在執行：\(plan.isRunning ? "是" : "否")）")
                    Text("設定檔格式：\(plan.info.profileFormat)、sector \(plan.info.sectorSize) bytes")
                }
                if let profile = snapshot.profile {
                    Text("板載 CRC：\(profile.hasValidCRC ? "通過" : "失敗")")
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
        GroupBox("DPI") {
            VStack(alignment: .leading, spacing: 8) {
                if let dpi = snapshot.dpi, let current = dpi.current {
                    LabeledContent("目前值", value: "\(current)")
                    if dpi.available.isEmpty {
                        Text("裝置沒有回報可用的 DPI 清單，因此無法選擇要套用的值。")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    } else {
                        Picker("要套用的值", selection: $draft) {
                            Text("請選擇").tag(Int?.none)
                            ForEach(dpi.available, id: \.self) { value in
                                Text("\(value)").tag(Int?.some(value))
                            }
                        }
                        .frame(width: 200)
                        .disabled(model.isBusy || model.isDemo)
                        HStack {
                            Button("套用") {
                                guard let draft else { return }
                                Task { await model.applyClassicDPI(device: snapshot, value: draft) }
                            }
                            .disabled(draft == nil || model.isBusy || model.isDemo)
                            Button("取消變更") { draft = nil }
                                .disabled(draft == nil)
                        }
                    }
                } else {
                    Text("此裝置沒有回報 DPI（未知）。")
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
        GroupBox("SmartShift 智慧滾輪") {
            VStack(alignment: .leading, spacing: 8) {
                if let state = snapshot.smartShift, let currentMode = state.mode, let currentThreshold = state.threshold {
                    LabeledContent("目前模式", value: currentMode == 2 ? "棘輪" : "自由捲動")
                    LabeledContent("目前切換點", value: "\(currentThreshold)")
                    if let torque = state.torque {
                        LabeledContent("目前扭力", value: "\(torque)%")
                    }
                    Picker("模式", selection: $mode) {
                        Text("請選擇").tag(Int?.none)
                        Text("自由捲動").tag(Int?.some(1))
                        Text("棘輪").tag(Int?.some(2))
                    }
                    .frame(width: 200)
                    .disabled(model.isBusy || model.isDemo)
                    Stepper("切換點：\(threshold ?? currentThreshold)", value: Binding(
                        get: { threshold ?? currentThreshold },
                        set: { threshold = $0 }
                    ), in: 1...254)
                        .disabled(model.isBusy || model.isDemo)
                    HStack {
                        Button("套用") {
                            Task { await model.applySmartShift(device: snapshot, mode: mode, threshold: threshold) }
                        }
                        .disabled((mode == nil && threshold == nil) || model.isBusy || model.isDemo)
                        Button("取消變更") { mode = nil; threshold = nil }
                            .disabled(mode == nil && threshold == nil)
                    }
                } else {
                    Text("此裝置沒有回報 SmartShift 狀態（未知）。")
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
        GroupBox("滾輪") {
            VStack(alignment: .leading, spacing: 8) {
                if let state = snapshot.wheel {
                    Toggle("反向捲動", isOn: Binding(
                        get: { inverted ?? state.inverted ?? false },
                        set: { inverted = $0 }
                    ))
                    .disabled(model.isBusy || model.isDemo)
                    Toggle("高解析度模式", isOn: Binding(
                        get: { highResolution ?? state.highResolution ?? false },
                        set: { highResolution = $0 }
                    ))
                    .disabled(model.isBusy || model.isDemo)
                    HStack {
                        Button("套用") {
                            Task {
                                await model.applyWheel(
                                    device: snapshot,
                                    inverted: inverted,
                                    highResolution: highResolution
                                )
                            }
                        }
                        .disabled((inverted == nil && highResolution == nil) || model.isBusy || model.isDemo)
                        Button("取消變更") { inverted = nil; highResolution = nil }
                            .disabled(inverted == nil && highResolution == nil)
                    }
                } else {
                    Text("此裝置沒有回報滾輪狀態（未知）。")
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

    /// The button name; the raw control ID stays in the diagnostics.
    private func buttonTitle(for control: ReprogramControl) -> String {
        switch control.cid {
        case 0x0052: "中鍵"
        case 0x0053: "上一頁鍵"
        case 0x0056: "下一頁鍵"
        default: "其他按鍵"
        }
    }

    var body: some View {
        GroupBox("使用按鍵自訂") {
            VStack(alignment: .leading, spacing: 10) {
                if candidates.isEmpty {
                    Text("此裝置沒有回報可以改道的側鍵，或需要先讀取功能表。")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(candidates) { control in
                        HStack {
                            Text(buttonTitle(for: control))
                                .font(.callout)
                            Spacer()
                            Picker("", selection: Binding(
                                get: { actions[control.cid] ?? .native },
                                set: { actions[control.cid] = $0 }
                            )) {
                                ForEach(MappedAction.allCases, id: \.self) { action in
                                    Text(action.title).tag(action)
                                }
                            }
                            .labelsHidden()
                            .frame(width: 170)
                            .disabled(model.isBusy || model.isDemo)
                        }
                    }
                    HStack {
                        Button("啟用") {
                            Task { await model.enableButtonMapping(device: snapshot, mappings: actions) }
                        }
                        .disabled(model.isBusy || model.isDemo || !MXButtonRemapper.hasAccessibilityPermission)
                        Button("停用並還原") {
                            Task { await model.disableButtonMapping(device: snapshot) }
                        }
                        .disabled(model.isBusy || model.isDemo)
                    }
                    if !MXButtonRemapper.hasAccessibilityPermission {
                        Text("需要「輔助使用」權限才能把改道按鍵變成 ⌘C／⌘V。")
                            .font(.caption)
                            .foregroundStyle(.orange)
                        Button("開啟輔助使用設定") { model.openAccessibilitySettings() }
                    }
                    Text("只會改道中鍵、上一頁與下一頁鍵的按鍵事件；停用時會把原本的狀態寫回去，主鍵不會被改道。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .onChange(of: snapshot.connectionEpoch) { _, _ in actions = [:] }
    }
}

/// HITS: actuation point, rapid trigger and click haptics (0x1B0C) — Superstrike.
struct HITSControlSection: View {
    @Environment(AppModel.self) private var model
    let snapshot: DeviceSnapshot

    var body: some View {
        GroupBox("HITS 按鍵觸發") {
            VStack(alignment: .leading, spacing: 10) {
                if let capabilities = snapshot.hitsCapabilities {
                    HStack(alignment: .top, spacing: 16) {
                        ForEach(snapshot.hitsButtons, id: \.button) { config in
                            HITSButtonColumn(snapshot: snapshot, config: config, capabilities: capabilities)
                                .frame(minWidth: 0, maxWidth: .infinity)
                        }
                    }
                    Text("快速觸發關閉時，裝置仍會回報舊的數值，所以必須明確選擇「關閉」或一個數值才會送出。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    Text("此裝置沒有回報 HITS 狀態（未知）。")
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
    @State private var rapidTrigger: Double?
    @State private var haptics: Double?
    @State private var rapidTriggerChoice: Int?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(config.button == 0 ? "左鍵" : "右鍵")
                .font(.headline)
            LabeledContent("觸發點", value: "\(config.actuation)")
            Slider(
                value: Binding(get: { actuation ?? Double(config.actuation) }, set: { actuation = $0 }),
                in: 1...Double(min(capabilities.maxActuation, 10)),
                step: 1
            )
            .disabled(model.isBusy || model.isDemo)
            LabeledContent(
                "快速觸發",
                value: config.rapidTrigger == 0 ? "關閉（回報等級 0）" : "開關未確認（回報等級 \(config.rapidTrigger)）"
            )
            Picker("快速觸發", selection: $rapidTriggerChoice) {
                Text("請選擇").tag(Int?.none)
                Text("關閉").tag(Int?.some(0))
                ForEach(1...max(1, min(capabilities.maxRapidTrigger, 5)), id: \.self) { value in
                    Text("\(value)").tag(Int?.some(value))
                }
            }
            .frame(width: 150)
            .disabled(model.isBusy || model.isDemo)
            LabeledContent("回饋強度", value: "\(config.haptics)")
            Slider(
                value: Binding(get: { haptics ?? Double(config.haptics) }, set: { haptics = $0 }),
                in: 0...Double(min(capabilities.maxHaptics, 5)),
                step: 1
            )
            .disabled(model.isBusy || model.isDemo)
            Button("套用") {
                let draft = HIDPPClient.HitsDraft(
                    button: config.button,
                    actuation: actuation.map { Int($0) },
                    rapidTrigger: rapidTriggerChoice,
                    haptics: haptics.map { Int($0) }
                )
                Task { await model.applyHITS(device: snapshot, draft: draft, capabilities: capabilities) }
            }
            .disabled(rapidTriggerChoice == nil || model.isBusy || model.isDemo)
        }
        .frame(minWidth: 0, maxWidth: .infinity, alignment: .leading)
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
        GroupBox("板載設定檔") {
            VStack(alignment: .leading, spacing: 10) {
                if let plan = snapshot.plan, let profile = snapshot.profile {
                    LabeledContent("模式", value: plan.isOnboardMode ? "板載" : "主控")
                    LabeledContent("設定檔", value: "\(plan.storedSector)")
                    if !plan.isRunning {
                        Text("裝置現在不是在跑這個設定檔。要變更它，先按下面的按鈕把裝置切到板載模式並選這個設定檔。")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                        Button("使用板載設定（設定檔 \(plan.storedSector)）") {
                            Task { await model.activateOnboard(device: snapshot, sector: plan.storedSector) }
                        }
                        .disabled(model.isBusy || model.isDemo)
                    }
                    LabeledContent("板載儲存 DPI（X / Y）", value: "\(profile.dpiX) / \(profile.dpiY)")
                    LabeledContent("目前回報率", value: "\(profile.reportRateHz) Hz")

                    Stepper("DPI：\(dpi ?? profile.dpiX)", value: Binding(
                        get: { dpi ?? profile.dpiX },
                        set: { dpi = $0 }
                    ), in: 100...ProfileLayout.maximumDPI, step: 50)
                        .disabled(model.isBusy || model.isDemo)
                    Picker("回報率", selection: $rateHz) {
                        Text("不變更").tag(Int?.none)
                        ForEach(ProfileLayout.reportRates, id: \.self) { hz in
                            Text("\(hz) Hz").tag(Int?.some(hz))
                        }
                    }
                    .frame(width: 200)
                    .disabled(model.isBusy || model.isDemo)

                    Text("按鍵")
                        .font(.headline)
                    Picker("中鍵", selection: $middle) {
                        ForEach(SideButtonChoice.allCases) { choice in
                            Text(choice.rawValue).tag(choice)
                        }
                    }
                    .frame(width: 220)
                    .disabled(model.isBusy || model.isDemo)
                    Picker("上一頁鍵", selection: $back) {
                        ForEach(SideButtonChoice.allCases) { choice in
                            Text(choice.rawValue).tag(choice)
                        }
                    }
                    .frame(width: 220)
                    .disabled(model.isBusy || model.isDemo)
                    Picker("下一頁鍵", selection: $forward) {
                        ForEach(SideButtonChoice.allCases) { choice in
                            Text(choice.rawValue).tag(choice)
                        }
                    }
                    .frame(width: 220)
                    .disabled(model.isBusy || model.isDemo)

                    Button("一次套用以上變更") {
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
                    Button("取消變更") {
                        dpi = nil; rateHz = nil
                        middle = .unchanged; back = .unchanged; forward = .unchanged
                    }
                    .disabled(dpi == nil && rateHz == nil && middle == .unchanged && back == .unchanged && forward == .unchanged)
                    Text("回報率要重新載入設定檔才會生效；套用後畫面會標示為「已儲存，待重新載入」。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    Text("此裝置沒有回報板載設定檔（未知）。")
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
    case back = "上一頁"
    case forward = "下一頁"
    case copy = "複製"
    case paste = "貼上"
    case media = "媒體播放／暫停"

    var id: String { rawValue }

    /// The four byte button record, or nil when nothing should be written.
    var action: ButtonAction? {
        switch self {
        case .unchanged: nil
        case .disabled: ButtonAction(kind: .disabled)
        case .back: ButtonAction(kind: .mouse, code: 0x0008)
        case .forward: ButtonAction(kind: .mouse, code: 0x0010)
        // ⌘ is the modifier byte 0x08, C is 0x06 and V is 0x19.
        case .copy: ButtonAction(kind: .key, code: 0x06, modifiers: 0x08)
        case .paste: ButtonAction(kind: .key, code: 0x19, modifiers: 0x08)
        case .media: ButtonAction(kind: .consumer, code: 0x00CD)
        }
    }
}
