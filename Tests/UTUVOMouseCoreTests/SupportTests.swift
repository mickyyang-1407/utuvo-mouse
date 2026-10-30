import Foundation
import Testing
@testable import UTUVOMouseSupport

/// A login item that never touches the system.
///
/// It records every call, so the tests can prove that nothing happened without
/// a user action.
final class FakeLaunchItemRegistrar: LaunchItemRegistering, @unchecked Sendable {
    private let lock = NSLock()
    private var status: LaunchItemStatus
    private let registerError: Error?
    private let unregisterError: Error?
    private var registerCount = 0
    private var unregisterCount = 0
    private var statusCount = 0

    init(
        status: LaunchItemStatus = .notRegistered,
        registerError: Error? = nil,
        unregisterError: Error? = nil
    ) {
        self.status = status
        self.registerError = registerError
        self.unregisterError = unregisterError
    }

    func currentStatus() async -> LaunchItemStatus {
        lock.withLock { statusCount += 1 }
        return lock.withLock { status }
    }

    func register() async throws {
        lock.withLock { registerCount += 1 }
        if let registerError { throw registerError }
        lock.withLock { status = .enabled }
    }

    func unregister() async throws {
        lock.withLock { unregisterCount += 1 }
        if let unregisterError { throw unregisterError }
        lock.withLock { status = .notRegistered }
    }

    var calls: (status: Int, register: Int, unregister: Int) {
        lock.withLock { (statusCount, registerCount, unregisterCount) }
    }
}

/// Counts the install attempts.
final class InstallCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var value = 0

    var count: Int { lock.withLock { value } }

    func bump() {
        lock.withLock { value += 1 }
    }
}

/// A cleanup that waits until the test opens it.
///
/// It makes the "the cleanup is still running" moments deterministic.
@MainActor
final class CleanupGate {
    private var started = false
    private var isOpen = false
    private var startWaiters: [CheckedContinuation<Void, Never>] = []
    private var gateWaiters: [CheckedContinuation<Void, Never>] = []

    /// Marks the cleanup as running.
    func markStarted() {
        started = true
        let waiters = startWaiters
        startWaiters = []
        for waiter in waiters { waiter.resume() }
    }

    /// Waits until the cleanup really started.
    func waitUntilStarted() async {
        if started { return }
        await withCheckedContinuation { continuation in
            startWaiters.append(continuation)
        }
    }

    /// Waits until the test opens the gate.
    func wait() async {
        if isOpen { return }
        await withCheckedContinuation { continuation in
            gateWaiters.append(continuation)
        }
    }

    /// Lets the cleanup finish.
    func open() {
        isOpen = true
        let waiters = gateWaiters
        gateWaiters = []
        for waiter in waiters { waiter.resume() }
    }
}

private struct RefusedError: Error, LocalizedError {
    var errorDescription: String? { "系統拒絕了這個請求" }
}

@Suite("登入項目")
struct LaunchItemTests {

    @Test("控制器建立後不會碰系統")
    @MainActor
    func controllerStartsInert() async {
        let fake = FakeLaunchItemRegistrar()
        let controller = LaunchItemController(registrar: fake)
        #expect(fake.calls.status == 0)
        #expect(fake.calls.register == 0)
        #expect(fake.calls.unregister == 0)
        #expect(controller.isUnknown)
        #expect(!controller.isEnabled)
    }

    @Test("狀態以系統回報為準")
    @MainActor
    func statusIsTheTruth() async {
        let fake = FakeLaunchItemRegistrar(status: .enabled)
        let controller = LaunchItemController(registrar: fake)
        await controller.refreshStatus()
        #expect(controller.isEnabled)
        #expect(!controller.needsApproval)
        #expect(!controller.isUnknown)
    }

    @Test("系統拒絕時狀態不變而且有錯誤")
    @MainActor
    func refusedRegistrationKeepsTheState() async {
        let fake = FakeLaunchItemRegistrar(registerError: RefusedError())
        let controller = LaunchItemController(registrar: fake)
        await controller.refreshStatus()
        await controller.setEnabled(true)
        #expect(fake.calls.register == 1)
        #expect(!controller.isEnabled)
        #expect(controller.lastError != nil)
        // The state is read again instead of being believed.
        #expect(fake.calls.status == 2)
    }

    @Test("等待使用者批准會被標示出來")
    @MainActor
    func approvalIsReported() async {
        let fake = FakeLaunchItemRegistrar(status: .requiresApproval)
        let controller = LaunchItemController(registrar: fake)
        await controller.refreshStatus()
        #expect(controller.needsApproval)
        #expect(!controller.isEnabled)
    }

    @Test("示範模式不會註冊登入項目")
    @MainActor
    func demoNeverRegisters() async {
        let fake = FakeLaunchItemRegistrar()
        let controller = LaunchItemController(registrar: fake, policy: .demo)
        await controller.setEnabled(true)
        await controller.setEnabled(false)
        #expect(fake.calls.register == 0)
        #expect(fake.calls.unregister == 0)
        #expect(!controller.isEnabled)
        #expect(RuntimePolicy.demo.allowsLoginItemRegistration == false)
        #expect(RuntimePolicy.demo.allowsUpdater == false)
        #expect(RuntimePolicy.live.allowsLoginItemRegistration == true)
    }
}

/// The update exit path, driven the way the updater service drives it.
@Suite("結束閘門與更新")
struct UpdateExitTests {

    /// What the updater service does when Sparkle postpones the relaunch:
    /// the handler goes to the coordinator first, then the cleanup runs.
    private func beginInstall(
        _ coordinator: AppExitCoordinator,
        counter: InstallCounter,
        cleanup: @escaping @MainActor () async -> Bool
    ) async -> AppExitCoordinator.InstallOutcome {
        await coordinator.beginUpdateInstall(handler: { counter.bump() }, cleanup: cleanup)
    }

    @Test("忙碌時不安裝，App 留下來")
    @MainActor
    func busyKeepsTheAppAlive() async {
        let coordinator = AppExitCoordinator()
        let counter = InstallCounter()
        // The cleanup could not run: something was still busy.
        let outcome = await beginInstall(coordinator, counter: counter) { false }
        #expect(outcome == .waitingForRetry)
        #expect(counter.count == 0)
        #expect(coordinator.phase == .failed)
        // The app stays alive, so it may work again.
        #expect(coordinator.allowsDeviceOperations)
    }

    @Test("清理成功時安裝一次")
    @MainActor
    func successInstallsOnce() async {
        let coordinator = AppExitCoordinator()
        let counter = InstallCounter()
        let outcome = await beginInstall(coordinator, counter: counter) { true }
        #expect(outcome == .installed)
        #expect(counter.count == 1)
        #expect(coordinator.installHandlerInvocationCount == 1)
    }

    @Test("重複回呼不會安裝第二次")
    @MainActor
    func duplicateCallbackDoesNotInstallTwice() async {
        let coordinator = AppExitCoordinator()
        let counter = InstallCounter()
        #expect(await beginInstall(coordinator, counter: counter) { false } == .waitingForRetry)
        // A second callback with its own install block.
        #expect(await beginInstall(coordinator, counter: counter) { true } == .installed)
        #expect(counter.count == 1)
        #expect(coordinator.installHandlerInvocationCount == 1)
    }

    @Test("清理進行中與完成後都不准寫入裝置")
    @MainActor
    func noDeviceWriteWhilePreparingOrReady() async {
        let coordinator = AppExitCoordinator()
        let counter = InstallCounter()
        var allowedDuringCleanup = true
        let outcome = await beginInstall(coordinator, counter: counter) { [coordinator] in
            allowedDuringCleanup = coordinator.allowsDeviceOperations
            return true
        }
        #expect(outcome == .installed)
        #expect(!allowedDuringCleanup)
        #expect(coordinator.phase == .ready)
        #expect(!coordinator.allowsDeviceOperations)
    }

    @Test("兩條路徑同時結束只清理一次")
    @MainActor
    func twoPathsShareOneCleanup() async {
        let coordinator = AppExitCoordinator()
        let counter = InstallCounter()
        async let first = coordinator.performExitSequence {
            await Task.yield()
            counter.bump()
            return true
        }
        async let second = coordinator.performExitSequence {
            await Task.yield()
            counter.bump()
            return true
        }
        let results = await [first, second]
        #expect(counter.count == 1)
        #expect(results.allSatisfy { $0 })
    }

    @Test("失敗之後還可以再試一次")
    @MainActor
    func aFailedExitCanBeRetried() async {
        let coordinator = AppExitCoordinator()
        #expect(await coordinator.performExitSequence { false } == false)
        #expect(coordinator.phase == .failed)
        #expect(await coordinator.performExitSequence { true })
        #expect(coordinator.phase == .ready)
    }
}

/// The regressions of the first review, driven through the same entry points
/// the updater service uses.
@Suite("更新的安裝流程")
struct UpdateInstallTests {

    @Test("清理失敗時保留 install handler，重試成功才安裝一次")
    @MainActor
    func failedCleanupKeepsTheHandlerForARetry() async {
        let coordinator = AppExitCoordinator()
        let counter = InstallCounter()
        // Sparkle 的回呼：忙碌時清理失敗。
        let first = await coordinator.beginUpdateInstall(
            handler: { counter.bump() },
            cleanup: { false }
        )
        #expect(first == .waitingForRetry)
        #expect(counter.count == 0)
        // Sparkle 不會再叫一次 delegate，handler 必須還在。
        #expect(coordinator.hasPendingInstall)
        #expect(coordinator.allowsDeviceOperations)

        // 使用者從設定視窗重試，清理成功。
        let second = await coordinator.retryUpdateInstall { true }
        #expect(second == .installed)
        #expect(counter.count == 1)
        #expect(coordinator.installHandlerInvocationCount == 1)
        #expect(!coordinator.hasPendingInstall)
    }

    @Test("重試仍然失敗時 handler 不會被叫，安裝次數維持 0")
    @MainActor
    func retryCanFailAgainWithoutInstalling() async {
        let coordinator = AppExitCoordinator()
        let counter = InstallCounter()
        _ = await coordinator.beginUpdateInstall(handler: { counter.bump() }, cleanup: { false })
        _ = await coordinator.retryUpdateInstall { false }
        #expect(counter.count == 0)
        #expect(coordinator.hasPendingInstall)
        #expect(coordinator.phase == .failed)
    }

    @Test("安裝被中止後 App 恢復可用並且可以再試一次")
    @MainActor
    func abortAfterReadyRecovers() async {
        let coordinator = AppExitCoordinator()
        let counter = InstallCounter()
        _ = await coordinator.beginUpdateInstall(handler: { counter.bump() }, cleanup: { true })
        #expect(coordinator.phase == .ready)
        #expect(!coordinator.allowsDeviceOperations)
        // Sparkle 中止，或安裝程式連不上。
        coordinator.abortUpdateInstall()
        #expect(coordinator.phase == .idle)
        #expect(coordinator.allowsDeviceOperations)
        #expect(!coordinator.hasPendingInstall)
        // 之後可以再來一次新的更新嘗試。
        let again = await coordinator.beginUpdateInstall(handler: { counter.bump() }, cleanup: { true })
        #expect(again == .installed)
        #expect(counter.count == 2)
    }

    @Test("清理進行中收到中止：不會解鎖寫入，也不會叫到舊 handler")
    @MainActor
    func abortDuringPendingCleanup() async {
        let coordinator = AppExitCoordinator()
        let counter = InstallCounter()
        let gate = CleanupGate()
        let task = Task { @MainActor in
            await coordinator.beginUpdateInstall(
                handler: { counter.bump() },
                cleanup: {
                    gate.markStarted()
                    await gate.wait()
                    return true
                }
            )
        }
        await gate.waitUntilStarted()
        #expect(coordinator.phase == .preparing)
        #expect(!coordinator.allowsDeviceOperations)
        // 清理還在跑的時候收到中止。
        coordinator.abortUpdateInstall()
        // 清理還在跑，不能解鎖寫入。
        #expect(!coordinator.allowsDeviceOperations)
        gate.open()
        let outcome = await task.value
        #expect(outcome == .discarded)
        // 舊的 handler 沒有被叫到。
        #expect(counter.count == 0)
        #expect(coordinator.installHandlerInvocationCount == 0)
        // App 恢復可用。
        #expect(coordinator.phase == .idle)
        #expect(coordinator.allowsDeviceOperations)
        #expect(!coordinator.hasPendingInstall)
    }

    @Test("中止後的新嘗試不被舊任務重置")
    @MainActor
    func aNewAttemptSurvivesTheStaleTask() async {
        let coordinator = AppExitCoordinator()
        let counter = InstallCounter()
        let gate = CleanupGate()
        let stale = Task { @MainActor in
            await coordinator.beginUpdateInstall(
                handler: { counter.bump() },
                cleanup: {
                    gate.markStarted()
                    await gate.wait()
                    return false
                }
            )
        }
        await gate.waitUntilStarted()
        coordinator.abortUpdateInstall()
        // 舊的清理還在跑；新的嘗試等它結束，然後自己清理。
        let fresh = Task { @MainActor in
            await coordinator.beginUpdateInstall(handler: { counter.bump() }, cleanup: { true })
        }
        gate.open()
        let staleOutcome = await stale.value
        let freshOutcome = await fresh.value
        #expect(staleOutcome == .discarded)
        #expect(freshOutcome == .installed)
        // 只有新嘗試的 handler 被叫到一次。
        #expect(counter.count == 1)
        #expect(coordinator.installHandlerInvocationCount == 1)
    }

    @Test("框架中止後待安裝的更新不會再安裝")
    @MainActor
    func frameworkAbortStopsThePendingInstall() async {
        let coordinator = AppExitCoordinator()
        let counter = InstallCounter()
        _ = await coordinator.beginUpdateInstall(handler: { counter.bump() }, cleanup: { false })
        #expect(coordinator.hasPendingInstall)
        coordinator.abortUpdateInstall()
        let outcome = await coordinator.retryUpdateInstall { true }
        #expect(outcome == .discarded)
        #expect(counter.count == 0)
    }
}

@Suite("更新設定")
struct UpdateConfigurationTests {

    private let feed = URL(string: "https://github.com/mickyyang-1407/utuvo-mouse/releases/latest/download/appcast.xml")
    private let key = "uIF/gSHM6GZ0y1uP1RP7Xk1rfLbQFv0LMuT9jK0k3dE="

    @Test("沒有金鑰就不算設定完成")
    func missingKey() {
        let configuration = UpdateConfiguration(feedURL: feed, publicEDKey: "")
        #expect(!configuration.isConfigured)
        #expect(configuration.problem == .missingPublicKey)
    }

    @Test("壞掉的金鑰不算設定完成")
    func invalidKey() {
        let configuration = UpdateConfiguration(feedURL: feed, publicEDKey: "not-a-key")
        #expect(!configuration.isConfigured)
        #expect(configuration.problem == .invalidPublicKey)
    }

    @Test("更新來源必須是 HTTPS")
    func insecureFeed() {
        let configuration = UpdateConfiguration(
            feedURL: URL(string: "http://example.com/appcast.xml"),
            publicEDKey: key
        )
        #expect(!configuration.isConfigured)
        #expect(configuration.problem == .insecureFeedURL)
    }

    @Test("沒有主機名稱的 HTTPS 不算設定完成")
    func feedWithoutHost() {
        let configuration = UpdateConfiguration(
            feedURL: URL(string: "https:///appcast.xml"),
            publicEDKey: key
        )
        #expect(!configuration.isConfigured)
        #expect(configuration.problem == .invalidFeedURL)
    }

    @Test("沒有來源網址不算設定完成")
    func missingFeed() {
        let configuration = UpdateConfiguration(feedURL: nil, publicEDKey: key)
        #expect(!configuration.isConfigured)
        #expect(configuration.problem == .missingFeedURL)
    }

    @Test("來源與金鑰都在才算設定完成")
    func completeConfiguration() {
        let configuration = UpdateConfiguration(feedURL: feed, publicEDKey: key)
        #expect(configuration.isConfigured)
        #expect(configuration.problem == nil)
        #expect(UpdateConfiguration.isValidPublicKey(key))
        #expect(!UpdateConfiguration.isValidPublicKey("short"))
    }
}
