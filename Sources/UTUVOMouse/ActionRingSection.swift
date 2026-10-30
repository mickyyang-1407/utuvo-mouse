import SwiftUI
import UTUVOMouseCore
import UTUVOMouseIO
import UTUVOMouseSupport

struct ActionRingSection: View {
    @Environment(AppModel.self) private var model
    let snapshot: DeviceSnapshot
    @State private var selectedSlot = 0

    private var supported: Bool {
        snapshot.reprogControls.contains { $0.cid == MXButtonRemapper.ringCID && $0.isDivertCandidate }
    }

    var body: some View {
        let ring = model.actionRing
        GroupBox {
            VStack(alignment: .leading, spacing: 15) {
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 24) { editorDiagram; slotPicker }
                    VStack(spacing: 18) { editorDiagram; slotPicker }
                }
                Divider()
                HStack(spacing: 12) {
                    Label(AppLocalization.text(model.isActionRingEnabled(for: snapshot) ? "ring.enabled" : "ring.disabled"),
                          systemImage: model.isActionRingEnabled(for: snapshot) ? "checkmark.circle.fill" : "circle")
                        .font(.system(size: 12, weight: .medium)).foregroundStyle(.secondary)
                    Spacer()
                    Button(AppLocalization.text("ring.preview")) { ring.present(preview: true) }
                    Button(AppLocalization.text(model.isActionRingEnabled(for: snapshot) ? "ring.disable" : "ring.enable")) {
                        Task { await model.setActionRingEnabled(device: snapshot, enabled: !model.isActionRingEnabled(for: snapshot)) }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(model.isBusy || model.isDemo || !supported || !MXButtonRemapper.hasAccessibilityPermission)
                }
                Text(AppLocalization.text("ring.instructions"))
                    .font(.system(size: 11)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                if !supported {
                    Text(AppLocalization.text("ring.unsupported")).font(.caption).foregroundStyle(.secondary)
                } else if !model.isDemo && !MXButtonRemapper.hasAccessibilityPermission {
                    Button(AppLocalization.text("device.sideButtons.openAccessibility")) { model.openAccessibilitySettings() }
                }
                if let error = ring.storageError { Text(error).font(.caption).foregroundStyle(.orange) }
            }
        } label: {
            HStack {
                Text(AppLocalization.text("ring.customize"))
                Spacer()
                Text("8").monospacedDigit().foregroundStyle(.tertiary)
            }
        }
    }

    private var editorDiagram: some View {
        ZStack {
            Circle().stroke(.primary.opacity(0.06), lineWidth: 1).frame(width: 214)
            Circle().fill(MouseTheme.canvas).frame(width: 80)
            Image(systemName: "cursorarrow.rays").font(.system(size: 24, weight: .light)).foregroundStyle(.secondary)
            ForEach(0..<8, id: \.self) { slot in
                let action = model.actionRing.configuration.slots[slot]
                let angle = Double(slot)*(.pi/4)-(.pi/2)
                Button { selectedSlot = slot } label: {
                    VStack(spacing: 6) {
                        Image(systemName: action.symbol).font(.system(size: 19, weight: .regular))
                        Text(AppLocalization.text("ring.action."+action.rawValue)).font(.system(size: 10, weight: .medium)).lineLimit(1)
                    }
                    .frame(width: 70, height: 57)
                    .foregroundStyle(selectedSlot == slot ? MouseTheme.accent : Color.primary.opacity(0.8))
                    .background(selectedSlot == slot ? MouseTheme.accent.opacity(0.10) : MouseTheme.canvas, in: RoundedRectangle(cornerRadius: 14))
                    .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(selectedSlot == slot ? MouseTheme.accent.opacity(0.35) : .clear, lineWidth: 1))
                }
                .buttonStyle(.plain)
                .accessibilityLabel(AppLocalization.text("ring.slot", slot+1)+", "+AppLocalization.text("ring.action."+action.rawValue))
                .accessibilityAddTraits(selectedSlot == slot ? [.isSelected] : [])
                .offset(x: cos(angle)*96, y: sin(angle)*96)
            }
        }.frame(width: 280, height: 260)
    }

    private var slotPicker: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(AppLocalization.text("ring.slot", selectedSlot+1)).font(.system(size: 20, weight: .semibold)).tracking(-0.4)
            Text(AppLocalization.text("ring.chooseAction")).font(.system(size: 12)).foregroundStyle(.secondary)
            Picker(AppLocalization.text("ring.chooseAction"), selection: Binding(
                get: { model.actionRing.configuration.slots[selectedSlot] },
                set: { model.actionRing.setAction($0, at: selectedSlot) }
            )) {
                ForEach(RingAction.allCases, id: \.self) { action in
                    Label(AppLocalization.text("ring.action."+action.rawValue), systemImage: action.symbol).tag(action)
                }
            }
            .labelsHidden().frame(minWidth: 165, maxWidth: .infinity)
            Text(AppLocalization.text("ring.savedLocally"))
                .font(.system(size: 11)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        }.frame(minWidth: 165, maxWidth: .infinity, alignment: .leading)
    }
}
