import Foundation
import CoreGraphics
import ApplicationServices
import UTUVOMouseCore

/// The actions a diverted side button can trigger.
///
/// `native` means the control keeps its own function — nothing is diverted.
/// The media key is deliberately not offered: a consumer code is not a macOS
/// virtual key, so there is no correct key code to post for it.
public enum MappedAction: String, Codable, Sendable, CaseIterable {
    case native
    case copy
    case paste

    public var title: String {
        switch self {
        case .native: "預設（不改道）"
        case .copy: "複製"
        case .paste: "貼上"
        }
    }
}

/// Performs the action of a diverted button press.
///
/// The tests inject a recording performer, so no fixture ever posts a key event.
public protocol ActionPerforming: Sendable {
    func perform(_ action: MappedAction)
}

/// Posts the macOS command events for real.
public final class SystemActionPerformer: ActionPerforming, @unchecked Sendable {
    public init() {}

    public func perform(_ action: MappedAction) {
        switch action {
        case .copy: postCommand(key: 6)    // C
        case .paste: postCommand(key: 25)  // V
        case .native: break
        }
    }

    /// Sends one complete ⌘-C or ⌘-V.
    private func postCommand(key: CGKeyCode) {
        guard let down = CGEvent(keyboardEventSource: nil, virtualKey: key, keyDown: true),
              let up = CGEvent(keyboardEventSource: nil, virtualKey: key, keyDown: false) else { return }
        down.flags = .maskCommand
        up.flags = .maskCommand
        down.post(tap: .cghidEventTap)
        up.post(tap: .cghidEventTap)
    }
}

/// What a disable did.
public enum DiversionRestoreResult: Sendable, Equatable {
    /// The controls of this session were put back and confirmed.
    case restored([UInt16])
    /// This session owns nothing; a lease of an earlier run was left alone.
    case nothingOwned
}

/// Diverts the side buttons of an MX Master 4 M and turns the diverted presses
/// into macOS commands.
///
/// Only the controls the device itself advertises as divertable are eligible,
/// the temporary bit is the only thing that is ever changed, and the state the
/// device had before is written down before the first change.
public final class MXButtonRemapper: @unchecked Sendable {
    /// The control IDs of the three buttons this app may divert on the MX Master 4 M.
    public static let allowedCIDs: Set<UInt16> = [0x0052, 0x0053, 0x0056]

    private let client: HIDPPClient
    private let reprogram: ReprogramControlsClient
    private let store: DiversionStateStore
    private let deviceID: String
    private let performer: ActionPerforming
    /// Whether the remapper may divert. Injectable so the tests can run without
    /// the accessibility permission.
    private let accessibilityGranted: () -> Bool
    private let lock = NSLock()
    private var pressed: Set<UInt16> = []
    private var mappings: [UInt16: MappedAction] = [:]
    private var connectionValid = true
    /// The controls this session owns. Only these are put back.
    private var ownedCIDs: Set<UInt16> = []
    /// The owned controls whose state could not be confirmed. They stay owned
    /// until a restore is confirmed, so Disable and Quit keep retrying them.
    private var uncertainCIDs: Set<UInt16> = []

    public init(
        client: HIDPPClient,
        reprogram: ReprogramControlsClient,
        store: DiversionStateStore,
        deviceID: String,
        performer: ActionPerforming = SystemActionPerformer(),
        accessibilityGranted: @escaping () -> Bool = { AXIsProcessTrusted() }
    ) {
        self.client = client
        self.reprogram = reprogram
        self.store = store
        self.deviceID = deviceID
        self.performer = performer
        self.accessibilityGranted = accessibilityGranted
    }

    /// Whether macOS lets this process post keyboard events.
    public static var hasAccessibilityPermission: Bool {
        AXIsProcessTrusted()
    }

    /// The controls the device offers that may be diverted.
    public func divertableControls() async throws -> [ReprogramControl] {
        try await reprogram.readControls().filter { $0.isDivertCandidate }
    }

    /// The controls this session currently owns.
    public var ownedControls: [UInt16] {
        lock.withLock { ownedCIDs.sorted() }
    }

    /// The owned controls whose state is not confirmed.
    public var uncertainControls: [UInt16] {
        lock.withLock { uncertainCIDs.sorted() }
    }

    /// Stops the dispatch without touching the device.
    ///
    /// Used when the transport is replaced: the old channel is gone, so nothing
    /// is restored there. The lease stays as the evidence for the user.
    public func stopDispatch() {
        lock.withLock {
            connectionValid = false
            mappings = [:]
            pressed = []
        }
    }

    /// Diverts the chosen controls. Only ever called from an explicit user action.
    public func enable(mappings newMappings: [UInt16: MappedAction]) async throws {
        let targets = newMappings.filter { $0.value != .native }
        guard !targets.isEmpty else { return }
        guard lock.withLock({ connectionValid }) else { throw DiversionError.reconnectRequired }
        guard accessibilityGranted() else { throw DiversionError.accessibilityRequired }

        // A diversion of this session has to be stopped first — the owned set is
        // never replaced or merged.
        let owned: Set<UInt16> = lock.withLock { ownedCIDs }
        guard owned.isEmpty else { throw DiversionError.disableFirstRequired }

        // A lease of an earlier run is not our ownership. It is only cleared when
        // the device shows that every control of it is back in its native state.
        if let lease = store.load(deviceID: deviceID), !lease.originals.isEmpty {
            for cid in lease.originals.keys {
                let reporting = try await reprogram.readReporting(cid: cid)
                if reporting.isTemporarilyDiverted {
                    // Somebody may own that mapping now: nothing is changed.
                    throw DiversionError.reconnectRequired
                }
            }
            try? store.clear(deviceID: deviceID)
        }

        // The device is asked which controls may be diverted at all. A control
        // that is not advertised as divertable is refused before anything is sent.
        let controls = try await reprogram.readControls()
        for cid in targets.keys {
            guard Self.allowedCIDs.contains(cid) else {
                throw DiversionError.notAllowed(cid: cid)
            }
            guard let control = controls.first(where: { $0.cid == cid }) else {
                throw DiversionError.unknownControl(cid: cid)
            }
            guard control.isDivertable, !control.isVirtual else {
                throw DiversionError.notDivertable(cid: cid)
            }
        }

        // Read the current state: a control that is already diverted belongs to
        // somebody else and is not taken over.
        var originals: [UInt16: UInt8] = [:]
        for cid in targets.keys {
            let reporting = try await reprogram.readReporting(cid: cid)
            if reporting.isTemporarilyDiverted {
                throw DiversionError.ownershipConflict(cid: cid)
            }
            originals[cid] = reporting.flags
        }

        // The state is written down before the first change.
        var lease = store.load(deviceID: deviceID)
            ?? DiversionLease(deviceID: deviceID, createdAt: Date(), originals: [:], actions: [:])
        lease.originals.merge(originals) { _, new in new }
        lease.actions = newMappings.mapValues(\.rawValue)
        try store.save(lease)

        // Every attempt is tracked, so a failure can put every attempted control
        // back — including one whose write went through but did not verify.
        var attempted: [UInt16] = []
        do {
            for cid in targets.keys {
                guard lock.withLock({ connectionValid }) else { throw DiversionError.reconnectRequired }
                // The control belongs to this session from the moment the write
                // is sent — a write that applies but does not verify must still
                // be put back.
                attempted.append(cid)
                lock.withLock { ownedCIDs.insert(cid) }
                try await reprogram.writeTemporaryDiversion(cid: cid, change: .enable)
                let verify = try await reprogram.readReporting(cid: cid)
                guard verify.isTemporarilyDiverted else {
                    throw DiversionError.notAccepted(cid: cid)
                }
            }
            try lock.withLock {
                guard connectionValid else { throw DiversionError.reconnectRequired }
                mappings = newMappings
                pressed = []
            }
        } catch {
            // Only a confirmed restore gives a control back.
            var restored: Set<UInt16> = []
            for cid in attempted where await restore(cid) {
                restored.insert(cid)
            }
            let unconfirmed = Set(attempted).subtracting(restored)
            lock.withLock {
                ownedCIDs.subtract(restored)
                uncertainCIDs = unconfirmed
            }
            if !unconfirmed.isEmpty {
                // The device state is unknown: the lease stays as the evidence
                // and the controls stay owned, so Disable and Quit retry them.
                throw DiversionError.rollbackUnconfirmed(cids: unconfirmed.sorted())
            }
            try? store.clear(deviceID: deviceID)
            throw error
        }
    }

    /// Puts the temporary diversion back and forgets the lease.
    ///
    /// Only the controls of this session are restored. A lease of an earlier run
    /// belongs to a state this app cannot see any more — it is left alone.
    public func disable() async throws -> DiversionRestoreResult {
        // Stop dispatching first: no action may run while the device is restored.
        let owned: Set<UInt16> = lock.withLock {
            mappings = [:]
            pressed = []
            return ownedCIDs
        }
        guard !owned.isEmpty else {
            return .nothingOwned
        }
        var unconfirmed: [UInt16] = []
        for cid in owned.sorted() where !(await restore(cid)) {
            unconfirmed.append(cid)
        }
        if !unconfirmed.isEmpty {
            // The state is still unknown: the lease stays and the quit is blocked.
            lock.withLock { uncertainCIDs = Set(unconfirmed) }
            throw DiversionError.restoreUnconfirmed(cid: unconfirmed[0])
        }
        // Only now the evidence is cleared.
        try store.clear(deviceID: deviceID)
        lock.withLock {
            ownedCIDs = []
            uncertainCIDs = []
        }
        return .restored(owned.sorted())
    }

    /// Whether this app currently holds a lease for the device.
    public var hasLease: Bool { store.load(deviceID: deviceID) != nil }

    /// Handles one notification frame.
    ///
    /// Only a notification of the reprogram feature on this device counts: the
    /// frame has to carry the feature index, function 0 and software ID 0.
    public func handle(frame: [UInt8]) {
        guard let response = try? HIDPPResponse.parse(frame) else { return }
        guard response.softwareID == HIDPPSoftwareID.device else { return }
        guard response.featureIndex == reprogram.feature.index else { return }
        guard response.function == 0 else { return }
        guard response.deviceIndex == client.deviceIndex else { return }

        let current = Set(ReprogramControlsClient.pressedControls(in: response.data))
        let previous: Set<UInt16> = lock.withLock { pressed }
        let down = current.subtracting(previous)
        let up = previous.subtracting(current)
        lock.withLock { pressed = current }
        for cid in down { press(cid) }
        for cid in up { release(cid) }
    }

    /// Puts one control back and checks that the device agrees.
    private func restore(_ cid: UInt16) async -> Bool {
        guard lock.withLock({ connectionValid }) else { return false }
        do {
            try await reprogram.writeTemporaryDiversion(cid: cid, change: .disable)
            let verify = try await reprogram.readReporting(cid: cid)
            return !verify.isTemporarilyDiverted
        } catch {
            return false
        }
    }

    private func press(_ cid: UInt16) {
        lock.withLock {
            guard connectionValid, let action = mappings[cid], action != .native else { return }
            performer.perform(action)
        }
    }

    private func release(_ cid: UInt16) {
        // The command events are complete on press, so nothing is held here.
    }
}
