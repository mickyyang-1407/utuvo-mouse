import SwiftUI
import UTUVOMouseCore

struct ModelSupportSection: View {
    @Environment(AppModel.self) private var model
    let snapshot: DeviceSnapshot

    var body: some View {
        GroupBox(AppLocalization.text("support.title")) {
            VStack(alignment: .leading, spacing: 12) {
                Label(status, systemImage: "wrench.and.screwdriver")
                    .font(.system(size: 13, weight: .semibold))
                Text(AppLocalization.text("support.explanation"))
                    .font(.callout).foregroundStyle(.secondary)
                Text(AppLocalization.text("support.privacy"))
                    .font(.caption).foregroundStyle(.secondary)
                HStack {
                    Button(AppLocalization.text("support.openTasks")) { model.modelSupport.openTasks() }
                        .disabled(model.isDemo || model.modelSupport.phase(for: snapshot) == nil)
                    Button(AppLocalization.text("support.refresh")) { model.modelSupport.refreshProgress() }
                        .disabled(model.isDemo)
                    Spacer()
                }
                if model.modelSupport.storageFailed {
                    Text(AppLocalization.text("support.storageError"))
                        .font(.caption).foregroundStyle(.red)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var status: String {
        guard model.modelSupport.enabled else { return AppLocalization.text("support.disabled") }
        guard let phase = model.modelSupport.phase(for: snapshot) else {
            return AppLocalization.text("support.unavailable")
        }
        return AppLocalization.text("support.phase." + phase.rawValue)
    }
}
