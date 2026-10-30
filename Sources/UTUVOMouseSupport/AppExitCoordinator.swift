import Foundation

/// The shared gate between the quit path and the update path.
///
/// One coordinator owns the whole exit sequence so that the app cannot write to
/// a device while it is shutting down, and so that a second callback cannot
/// install the update twice.
///
/// Sparkle hands over exactly one install handler per update and does not offer
/// it again. The handler is therefore kept when the cleanup fails, so the
/// interface can retry instead of stranding the update.
@MainActor
public final class AppExitCoordinator {

    /// Where the app is in the exit sequence.
    public enum Phase: Equatable, Sendable {
        /// The app runs normally.
        case idle
        /// A cleanup is running. Nothing new may be written to a device.
        case preparing
        /// The cleanup succeeded. The installer may take over.
        case ready
        /// The cleanup failed. The app stays alive and may try again.
        case failed
    }

    /// What happened to a postponed update installation.
    public enum InstallOutcome: Equatable, Sendable {
        /// The install handler ran. The update is being installed.
        case installed
        /// The cleanup failed. The handler is kept, the app stays alive and the
        /// installation can be retried.
        case waitingForRetry
        /// The attempt was given up. Nothing was installed.
        case discarded
    }

    /// The phase of the exit sequence.
    public private(set) var phase: Phase = .idle

    /// Device traffic is allowed while the app is idle or after a failed exit
    /// attempt. It is refused from the first cleanup step until the installer
    /// takes over, so nothing slips in between the cleanup and the exit.
    public var allowsDeviceOperations: Bool { phase == .idle || phase == .failed }

    /// How often the install action ran. The tests look at this.
    public private(set) var installHandlerInvocationCount = 0

    /// One postponed installation.
    private struct Attempt {
        let id: Int
        var handler: (@MainActor () -> Void)?
        var handlerRan = false
    }

    private var attempt: Attempt?
    private var attemptCounter = 0
    private var inFlight: Task<Bool, Never>?
    private var inFlightAttemptID: Int?
    private var cleanupGeneration = 0
    /// The ordinary quit owns the exclusion while the app waits to leave.
    private var quitOwnsExclusion = false
    /// The update owns the exclusion while the installer may take over.
    private var updateOwnsExclusion = false

    public init() {}

    /// True when an installation waits for a successful cleanup.
    public var hasPendingInstall: Bool {
        guard let attempt, !attempt.handlerRan, attempt.handler != nil else { return false }
        return true
    }

    /// Runs the cleanup once for every caller that shares the same exit.
    ///
    /// A caller that arrives while the cleanup runs waits for the same result
    /// instead of starting a second cleanup, so the quit path and the update
    /// path cannot race each other.
    ///
    /// - Returns: `true` when the cleanup succeeded.
    @discardableResult
    public func performExitSequence(cleanup: @escaping @MainActor () async -> Bool) async -> Bool {
        // Claim before joining the shared cleanup: an update abort may resume
        // before this caller does, but it must not unlock an ordinary quit.
        quitOwnsExclusion = true
        let succeeded = await runCleanup(attemptID: nil, cleanup: cleanup)
        if succeeded {
            phase = .ready
        } else {
            quitOwnsExclusion = false
            // A failed quit leaves the app alive, unless the update owns the
            // exclusion already.
            if !updateOwnsExclusion { phase = .failed }
        }
        return succeeded
    }

    /// Takes over a postponed update installation.
    ///
    /// The handler is stored before the cleanup runs: Sparkle offers it only
    /// once, so a failed cleanup must not throw it away.
    ///
    /// A repeated callback joins the attempt that is already running. The
    /// install block stays unique, and an attempt that already installed is
    /// never installed a second time.
    public func beginUpdateInstall(
        handler: @escaping @MainActor () -> Void,
        cleanup: @escaping @MainActor () async -> Bool
    ) async -> InstallOutcome {
        if let current = attempt {
            if current.handlerRan {
                // The update is already being installed: nothing to do.
                return .installed
            }
            // Join the pending attempt instead of replacing its handler.
            return await runAttempt(cleanup)
        }
        attemptCounter += 1
        attempt = Attempt(id: attemptCounter, handler: handler)
        return await runAttempt(cleanup)
    }

    /// Runs the cleanup again for an installation that is still pending.
    ///
    /// The kept handler runs as soon as the cleanup succeeds.
    @discardableResult
    public func retryUpdateInstall(
        cleanup: @escaping @MainActor () async -> Bool
    ) async -> InstallOutcome {
        guard let current = attempt, !current.handlerRan, current.handler != nil else {
            return .discarded
        }
        return await runAttempt(cleanup)
    }

    /// Gives up the pending installation.
    ///
    /// This is what a genuine framework abort does: the framework ended its
    /// session, so the block it handed over is dropped with it.
    ///
    /// The app only becomes usable again when the update owns the exclusion
    /// and no ordinary quit owns it. A cleanup that is still running keeps the
    /// app closed until it is over.
    public func abortUpdateInstall() {
        attempt = nil
        // A cleanup that is still running keeps the app closed until it ends.
        guard inFlight == nil else { return }
        // An ordinary quit owns the exclusion: an update abort must not unlock
        // a quit that is still waiting to leave.
        guard updateOwnsExclusion, !quitOwnsExclusion else { return }
        updateOwnsExclusion = false
        phase = .idle
    }

    /// Runs the cleanup of the current attempt and installs when it succeeds.
    private func runAttempt(_ cleanup: @escaping @MainActor () async -> Bool) async -> InstallOutcome {
        let id = attempt?.id
        let succeeded = await runCleanup(attemptID: id, cleanup: cleanup)
        guard var current = attempt, current.id == id else {
            // The attempt was given up or replaced while the cleanup ran. A
            // newer attempt owns the phase now, so it is left alone.
            if attempt == nil && !quitOwnsExclusion { phase = .idle }
            return .discarded
        }
        guard succeeded else {
            // The handler is kept: the interface can retry the cleanup.
            updateOwnsExclusion = false
            if !quitOwnsExclusion { phase = .failed }
            return .waitingForRetry
        }
        phase = .ready
        updateOwnsExclusion = true
        guard let handler = current.handler, !current.handlerRan else { return .installed }
        current.handlerRan = true
        attempt = current
        installHandlerInvocationCount += 1
        handler()
        return .installed
    }

    /// Runs the cleanup, or joins the one that is already running.
    ///
    /// The quit path joins any running cleanup: it is the same device work. An
    /// update attempt waits for a cleanup of another attempt and then runs its
    /// own, so a stale cleanup never decides the outcome of a fresh attempt.
    private func runCleanup(attemptID: Int?, cleanup: @escaping @MainActor () async -> Bool) async -> Bool {
        if let inFlight {
            if attemptID == nil || inFlightAttemptID == attemptID {
                return await inFlight.value
            }
            // Another attempt is cleaning up: wait, so the device is never
            // touched twice at the same time, and then clean up on its own.
            _ = await inFlight.value
        }
        cleanupGeneration += 1
        let generation = cleanupGeneration
        phase = .preparing
        let task = Task { @MainActor in await cleanup() }
        inFlight = task
        inFlightAttemptID = attemptID
        let succeeded = await task.value
        // Only the cleanup that is still current may clear the shared pointer.
        if cleanupGeneration == generation {
            inFlight = nil
            inFlightAttemptID = nil
        }
        return succeeded
    }
}
