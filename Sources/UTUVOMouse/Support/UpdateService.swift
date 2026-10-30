import Foundation
import Observation
import Sparkle
import UTUVOMouseSupport

/// Carries Sparkle's install block across the task boundary.
///
/// The block Sparkle hands over is not `Sendable`, and it has to survive the
/// hop into the cleanup task.
final class InstallHandlerBox: @unchecked Sendable {
    private let handler: () -> Void

    init(_ handler: @escaping () -> Void) {
        self.handler = handler
    }

    /// Runs the block. It is only called on the main actor.
    func call() {
        handler()
    }
}

/// The one updater of the app.
///
/// The Sparkle controller and the delegate are held strongly for the life of
/// the app, because Sparkle keeps only a weak reference to its delegate.
/// Nothing is created when the release is not configured, so the demo mode and
/// a build without a public key never reach the network.
@MainActor
@Observable
final class UpdateService {

    /// The Sparkle controller. `nil` when the release is not configured.
    private(set) var controller: SPUStandardUpdaterController?

    /// The configuration the updater was created with.
    let configuration: UpdateConfiguration

    /// The last message the updater produced.
    private(set) var statusMessage: String?

    /// The updater's own values, mirrored for the interface.
    ///
    /// The framework stays the only truth: every value here is read back from
    /// the updater, and the observations keep the mirror current even when the
    /// framework changes the value on its own.
    private(set) var automaticallyChecksForUpdates = false
    private(set) var automaticallyDownloadsUpdates = false
    private(set) var canCheckForUpdates = false
    private(set) var lastCheckDate: Date?

    /// True while an update waits for a successful cleanup before it installs.
    var hasPendingInstall: Bool { coordinator.hasPendingInstall }

    /// The cleanup the app runs before the installer takes over.
    typealias Cleanup = @MainActor () async -> Bool

    private let coordinator: AppExitCoordinator
    private let delegate: SparkleUpdaterDelegate
    private var cleanup: Cleanup?
    private var observations: [NSKeyValueObservation] = []

    init(
        configuration: UpdateConfiguration,
        coordinator: AppExitCoordinator
    ) {
        self.configuration = configuration
        self.coordinator = coordinator
        self.delegate = SparkleUpdaterDelegate()
        guard configuration.isConfigured else { return }
        let controller = SPUStandardUpdaterController(
            startingUpdater: true,
            updaterDelegate: delegate,
            userDriverDelegate: nil
        )
        // No system profile and no telemetry leave the app.
        controller.updater.sendsSystemProfile = false
        self.controller = controller
        delegate.service = self
        observe(controller.updater)
        refreshSnapshot()
    }

    /// The cleanup that runs before the installer takes over.
    func setCleanup(_ cleanup: @escaping Cleanup) {
        self.cleanup = cleanup
    }

    /// True when an updater exists.
    var isAvailable: Bool { controller != nil }

    /// Why the updater does not run, if it does not.
    var configurationProblem: UpdateConfiguration.Problem? { configuration.problem }

    /// The feed the updater reads.
    var feedURL: URL? { controller?.updater.feedURL ?? configuration.feedURL }

    /// The version of the running app.
    var currentVersion: String {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String
        switch (version, build) {
        case let (version?, build?): return "\(version) (\(build))"
        case let (version?, nil): return version
        default: return "—"
        }
    }

    /// Starts a manual check.
    func checkForUpdates() {
        guard let controller, canCheckForUpdates else { return }
        statusMessage = SettingsStrings.update.checking
        controller.checkForUpdates(nil)
    }

    /// Whether the updater checks for updates on its own.
    ///
    /// The value is stored by Sparkle in the app's own preference domain, so
    /// the updater itself stays the only truth.
    var automaticChecksEnabled: Bool {
        get { automaticallyChecksForUpdates }
        set {
            controller?.updater.automaticallyChecksForUpdates = newValue
            refreshSnapshot()
        }
    }

    /// Whether the updater downloads an update without asking first.
    var automaticDownloadsEnabled: Bool {
        get { automaticallyDownloadsUpdates }
        set {
            controller?.updater.automaticallyDownloadsUpdates = newValue
            refreshSnapshot()
        }
    }

    /// Retries the cleanup of an update that is still waiting.
    ///
    /// Sparkle offers its install handler only once, so the handler is kept
    /// here until the cleanup succeeds.
    func retryPendingInstall() {
        guard hasPendingInstall else { return }
        Task { @MainActor in
            let outcome = await coordinator.retryUpdateInstall { await self.runCleanup() }
            self.handleInstallOutcome(outcome)
        }
    }

    /// Reads the updater's own values into the mirror.
    private func refreshSnapshot() {
        guard let updater = controller?.updater else { return }
        automaticallyChecksForUpdates = updater.automaticallyChecksForUpdates
        automaticallyDownloadsUpdates = updater.automaticallyDownloadsUpdates
        canCheckForUpdates = updater.canCheckForUpdates
        lastCheckDate = updater.lastUpdateCheckDate
    }

    /// Follows the updater's properties.
    ///
    /// Sparkle's properties are Objective-C and KVO compliant, so the interface
    /// also sees changes that Sparkle makes on its own.
    private func observe(_ updater: SPUUpdater) {
        let observed: [NSKeyValueObservation] = [
            updater.observe(\.automaticallyChecksForUpdates, options: [.initial, .new]) { [weak self] _, _ in
                Task { @MainActor in self?.refreshSnapshot() }
            },
            updater.observe(\.automaticallyDownloadsUpdates, options: [.initial, .new]) { [weak self] _, _ in
                Task { @MainActor in self?.refreshSnapshot() }
            },
            updater.observe(\.canCheckForUpdates, options: [.initial, .new]) { [weak self] _, _ in
                Task { @MainActor in self?.refreshSnapshot() }
            },
            updater.observe(\.lastUpdateCheckDate, options: [.initial, .new]) { [weak self] _, _ in
                Task { @MainActor in self?.refreshSnapshot() }
            },
        ]
        observations.append(contentsOf: observed)
    }

    /// The cleanup the app asked for, or `true` when there is none.
    private func runCleanup() async -> Bool {
        guard let cleanup else { return true }
        return await cleanup()
    }

    fileprivate func handleInstallOutcome(_ outcome: AppExitCoordinator.InstallOutcome) {
        switch outcome {
        case .installed:
            statusMessage = SettingsStrings.update.installing
        case .waitingForRetry:
            statusMessage = SettingsStrings.update.cleanupFailed
        case .discarded:
            statusMessage = SettingsStrings.update.installDiscarded
        }
    }

    fileprivate func handleAbort(_ message: String) {
        // The app has to be usable again and the old attempt is gone.
        coordinator.abortUpdateInstall()
        statusMessage = SettingsStrings.update.aborted(message)
    }

    /// The Sparkle delegate.
    ///
    /// Sparkle keeps only a weak reference to its delegate, so the service
    /// holds it. The service is held weakly to avoid a cycle.
    @MainActor
    final class SparkleUpdaterDelegate: NSObject, SPUUpdaterDelegate {
        weak var service: UpdateService?

        /// The app always postpones the relaunch.
        ///
        /// The handler is handed to the coordinator before the cleanup runs, so
        /// a failed cleanup does not strand the update: the interface can retry
        /// instead of starting a second Sparkle session.
        func updater(
            _ updater: SPUUpdater,
            shouldPostponeRelaunchForUpdate appcastItem: SUAppcastItem,
            untilInvokingBlock installHandler: @escaping () -> Void
        ) -> Bool {
            guard let service else { return true }
            let box = InstallHandlerBox(installHandler)
            Task { @MainActor in
                let outcome = await service.coordinator.beginUpdateInstall(
                    handler: { box.call() },
                    cleanup: { await service.runCleanup() }
                )
                service.handleInstallOutcome(outcome)
            }
            return true
        }

        func updater(_ updater: SPUUpdater, didFindValidUpdate item: SUAppcastItem) {
            service?.statusMessage = SettingsStrings.update.found(item.displayVersionString)
        }

        func updaterDidNotFindUpdate(_ updater: SPUUpdater, error: Error) {
            service?.statusMessage = SettingsStrings.update.upToDate
        }

        func updater(_ updater: SPUUpdater, didAbortWithError error: Error) {
            service?.handleAbort(error.localizedDescription)
        }
    }
}
