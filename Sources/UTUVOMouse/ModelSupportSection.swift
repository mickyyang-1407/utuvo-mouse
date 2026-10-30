import SwiftUI
import UTUVOMouseCore
import UTUVOMouseSupport

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
                capabilityRows
                HStack {
                    Button(AppLocalization.text("support.openTasks")) { model.modelSupport.openTasks() }
                        .disabled(model.isDemo || model.modelSupport.phase(for: snapshot) == nil)
                    Button(AppLocalization.text("support.refresh")) { model.modelSupport.refreshProgress() }
                        .disabled(model.isDemo)
                    if model.modelSupport.isCapabilityModel(for: snapshot) {
                        Button(model.modelSupport.isCollecting
                               ? AppLocalization.text("support.capability.collecting")
                               : AppLocalization.text("support.capability.collect")) {
                            Task { await model.modelSupport.collectCapabilities() }
                        }
                        .disabled(!model.modelSupport.canCollectCapabilities(for: snapshot))
                    }
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

    /// Three compact rows: the capability report with its provenance, the
    /// program test of the current input, and the physical/release gates that
    /// stay closed.
    ///
    /// The input fingerprint stays out of this pane: it belongs to the
    /// developer JSON and the local status file.
    private var capabilityRows: some View {
        VStack(alignment: .leading, spacing: 7) {
            row(AppLocalization.text("support.capability.title"), capabilityValue)
            row(AppLocalization.text("support.tests.title"), programTestValue)
            HStack(alignment: .firstTextBaseline, spacing: 20) {
                gate(AppLocalization.text("support.physical.title"), AppLocalization.text("support.physical.value"))
                gate(AppLocalization.text("support.release.title"), AppLocalization.text("support.release.value"))
            }
        }
        .padding(.vertical, 2)
    }

    private func row(_ title: String, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text(title)
                .font(.caption).foregroundStyle(.secondary)
                .frame(width: 124, alignment: .leading)
            Text(value)
                .font(.caption)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func gate(_ title: String, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            Text(value).font(.caption).foregroundStyle(.tertiary)
        }
    }

    /// The provenance of the record on file. An imported record is never shown
    /// as device-confirmed. An invalid stored input is named as invalid.
    private var capabilityValue: String {
        if let invalid = model.modelSupport.capabilityInputFailure(for: snapshot) {
            return AppLocalization.text("support.capability.invalid") + " [" + invalid + "]"
        }
        if let failure = model.modelSupport.capabilityFailure(for: snapshot) {
            return AppLocalization.text("support.capability.failed") + " [" + failure + "]"
        }
        guard let record = model.modelSupport.capabilityRecord(for: snapshot) else {
            return AppLocalization.text("support.capability.none")
        }
        return AppLocalization.text("support.capability.origin." + record.origin.rawValue)
    }

    /// The program test result, marked with the input it actually covers.
    private var programTestValue: String {
        guard let phase = model.modelSupport.phase(for: snapshot) else {
            return AppLocalization.text("support.tests.none")
        }
        let phaseText = AppLocalization.text("support.phase." + phase.rawValue)
        switch model.modelSupport.programState(for: snapshot) {
        case .olderInput:
            // The result on file belongs to an earlier input, so it is never
            // presented as a result for the input that is on file now.
            return phaseText + " · " + AppLocalization.text("support.tests.earlierInput")
        case .invalidInput:
            return AppLocalization.text("support.tests.unavailable")
        case .currentInput, .pending, .metadataOnly, .noCapabilityInput, .failed, .noTask:
            return phaseText
        }
    }

    /// The short program state. It states what the result means for the
    /// capability input on file and never repeats the phase description.
    private var status: String {
        guard model.modelSupport.enabled else { return AppLocalization.text("support.disabled") }
        let state = model.modelSupport.programState(for: snapshot)
        if state == .invalidInput { return AppLocalization.text("support.program.invalidInput") }
        guard model.modelSupport.phase(for: snapshot) != nil else {
            return AppLocalization.text("support.unavailable")
        }
        return AppLocalization.text("support.program." + state.rawValue)
    }
}
