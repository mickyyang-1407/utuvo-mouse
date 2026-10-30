public enum MXMappingPresentationState: Equatable, Sendable {
    case active
    case uncertain
    case previousLease
    case savedIntentOnly
    case savedDisabled
    case noSavedMapping
}

public enum MXMappingPresentationPolicy {
    public static func state(
        savedEnabledIntent: Bool,
        hasSavedMapping: Bool,
        activeControlCount: Int,
        uncertainControlCount: Int,
        hasLease: Bool
    ) -> MXMappingPresentationState {
        if uncertainControlCount > 0 { return .uncertain }
        if activeControlCount > 0 { return .active }
        if hasLease { return .previousLease }
        if savedEnabledIntent { return .savedIntentOnly }
        return hasSavedMapping ? .savedDisabled : .noSavedMapping
    }
}
