import Foundation

/// Fixed failure codes for the capability import route.
///
/// They never carry a path, a file name, a model key or any other input value.
public enum CapabilityImportError: String, Error, Sendable, Equatable {
    case invalidArguments
    case mixedModes
    case unsafeFile
    case tooLarge
    case invalidReport
    case storageFailed
}

/// Pure routing for the file import command.
///
/// The import is consumed before any normal app setup, so a malformed request
/// cannot reach the GUI, the scanner or the broader --probe path.
public enum CapabilityImportInvocation: Sendable, Equatable {
    case notRequested
    case help
    case importCapabilities(file: String, supportDirectory: String?)

    public static let command = "--import-capabilities"
    public static let directoryOption = "--support-directory"

    /// Modes that must never be combined with an import.
    static let conflictingModes = [
        "--inspect-capabilities", "--allow-read-only-hidpp", "--probe", "--demo",
        "--localization-check", "--appearance"
    ]

    public static func parse(_ arguments: [String]) throws -> Self {
        let requested = arguments.contains { $0 == command || $0.hasPrefix(command + "=") }
        guard requested else { return .notRequested }
        for argument in arguments {
            for mode in conflictingModes where argument == mode || argument.hasPrefix(mode + "=") {
                throw CapabilityImportError.mixedModes
            }
        }
        if arguments == [command, "--help"] || arguments == [command, "-h"] { return .help }

        var file: String?
        var directory: String?
        var index = 0
        while index < arguments.count {
            let argument = arguments[index]
            if argument == command {
                index += 1
                guard index < arguments.count else { throw CapabilityImportError.invalidArguments }
                let value = arguments[index]
                guard file == nil, !value.isEmpty, !value.hasPrefix("-") else {
                    throw CapabilityImportError.invalidArguments
                }
                file = value
            } else if argument.hasPrefix(command + "=") {
                let value = String(argument.dropFirst(command.count + 1))
                guard file == nil, !value.isEmpty, !value.hasPrefix("-") else {
                    throw CapabilityImportError.invalidArguments
                }
                file = value
            } else if argument == directoryOption {
                index += 1
                guard index < arguments.count, directory == nil else {
                    throw CapabilityImportError.invalidArguments
                }
                let value = arguments[index]
                guard !value.isEmpty, !value.hasPrefix("-") else {
                    throw CapabilityImportError.invalidArguments
                }
                directory = value
            } else if argument.hasPrefix(directoryOption + "=") {
                let value = String(argument.dropFirst(directoryOption.count + 1))
                guard directory == nil, !value.isEmpty, !value.hasPrefix("-") else {
                    throw CapabilityImportError.invalidArguments
                }
                directory = value
            } else {
                throw CapabilityImportError.invalidArguments
            }
            index += 1
        }
        guard let file else { throw CapabilityImportError.invalidArguments }
        return .importCapabilities(file: file, supportDirectory: directory)
    }
}

/// How a program-test result relates to the capability input that is on file.
///
/// A program test proves program behaviour for one input revision only. It
/// never proves physical behaviour and it never transfers to a newer input.
public enum CapabilityProgressCoverage: String, Equatable, Sendable {
    /// No capability record is on file.
    case noCapabilityInput
    /// The program test ran against exactly this capability input.
    case currentInput
    /// The program test ran against an older capability input.
    case staleInput
    /// The program test predates capability records, so it covers no input.
    case unattributed
    /// The stored capability input is invalid, so no coverage can be claimed.
    case invalidInput
}

public enum ModelSupportCoverage {
    /// Compares the capability record fingerprint with the progress fingerprint.
    ///
    /// `invalidInput` is set when a capability file exists but cannot be
    /// validated. An invalid input never yields a coverage claim: the program
    /// result covers nothing that can be named.
    public static func coverage(
        record: CapabilityRecord?,
        progress: ModelSupportProgress?,
        invalidInput: Bool = false
    ) -> CapabilityProgressCoverage {
        if invalidInput { return .invalidInput }
        guard let record, let progress else { return .noCapabilityInput }
        guard let fingerprint = progress.capabilitiesFingerprint else { return .unattributed }
        return fingerprint == record.fingerprint ? .currentInput : .staleInput
    }
}

/// The short program state of one model job.
///
/// It states what the program result means for the capability input that is on
/// file right now. It never repeats a long phase description and it never
/// claims a coverage the input revision does not have.
public enum ModelSupportProgramState: String, Equatable, Sendable, CaseIterable {
    /// No local task exists for this model.
    case noTask
    /// The developer AI is still working; no result for the current input yet.
    case pending
    /// The program test covers exactly the capability input on file.
    case currentInput
    /// The capability input on file is newer than the tested input.
    case olderInput
    /// The stored capability input is invalid; program coverage is unavailable.
    case invalidInput
    /// The result on file covers metadata only.
    case metadataOnly
    /// The tested input is no longer on file.
    case noCapabilityInput
    /// The run stopped before it produced a result.
    case failed
}

public enum ModelSupportProgram {
    /// Resolves the short program state from the job phase and its input.
    ///
    /// The result is honest by construction: a corrupt capability file, a
    /// newer input than the tested one and a removed input can never resolve
    /// to `currentInput`.
    public static func state(
        phase: ModelSupportPhase?,
        record: CapabilityRecord?,
        progress: ModelSupportProgress?,
        invalidInput: Bool = false
    ) -> ModelSupportProgramState {
        let coverage = ModelSupportCoverage.coverage(record: record, progress: progress,
                                                     invalidInput: invalidInput)
        if coverage == .invalidInput { return .invalidInput }
        guard let phase else { return .noTask }
        switch phase {
        case .failed:
            return .failed
        case .queued, .preparing, .developing, .testing:
            return .pending
        case .needsHardware:
            switch coverage {
            case .currentInput:
                return .currentInput
            case .staleInput:
                return .olderInput
            case .unattributed:
                return .metadataOnly
            case .noCapabilityInput:
                // A legacy status without a fingerprint belongs to a
                // metadata-only job. A status with a fingerprint belongs to an
                // input that is no longer on file.
                return progress?.capabilitiesFingerprint == nil ? .metadataOnly : .noCapabilityInput
            case .invalidInput:
                return .invalidInput
            }
        }
    }
}

extension CapabilityFingerprint {
    /// A fingerprint is 64 lowercase hexadecimal characters.
    public static func isValid(_ value: String) -> Bool {
        value.count == 64 && value.allSatisfy { $0.isHexDigit && !$0.isUppercase }
    }
}
