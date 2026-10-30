import Foundation
import Testing
@testable import UTUVOMouseSupport

/// A one-shot signal that a task really started.
@MainActor
final class StartSignal {
    private var signaled = false
    private var waiters: [CheckedContinuation<Void, Never>] = []

    /// Marks the task as started.
    func signal() {
        signaled = true
        let waiters = waiters
        self.waiters = []
        for waiter in waiters { waiter.resume() }
    }

    /// Waits until the task started.
    func wait() async {
        if signaled { return }
        await withCheckedContinuation { continuation in
            waiters.append(continuation)
        }
    }
}

/// The regressions of the second review, written against the production
/// Support API before the fix.
@Suite("R2 的回歸")
struct R2RegressionTests {

    @Test("成功之後的重複回呼不會再安裝一次")
    @MainActor
    func duplicateBeginAfterSuccessInstallsOnce() async {
        let coordinator = AppExitCoordinator()
        let counter = InstallCounter()
        let first = await coordinator.beginUpdateInstall(handler: { counter.bump() }, cleanup: { true })
        #expect(first == .installed)
        #expect(counter.count == 1)
        // Sparkle 的第二次回呼：handler 已經用過了，不能再叫一次。
        let second = await coordinator.beginUpdateInstall(handler: { counter.bump() }, cleanup: { true })
        #expect(second == .installed)
        #expect(counter.count == 1)
        #expect(coordinator.installHandlerInvocationCount == 1)
    }

    @Test("沒有更新時的 abort 不會解鎖一般退出")
    @MainActor
    func abortWithoutUpdateKeepsTheQuitExclusion() async {
        let coordinator = AppExitCoordinator()
        #expect(await coordinator.performExitSequence { true })
        #expect(coordinator.phase == .ready)
        #expect(!coordinator.allowsDeviceOperations)
        // 與這次退出無關的更新中止。
        coordinator.abortUpdateInstall()
        #expect(coordinator.phase == .ready)
        #expect(!coordinator.allowsDeviceOperations)
    }

    @Test("一般退出加入更新的清理後，框架中止仍保留退出的封鎖")
    @MainActor
    func quitJoinKeepsExclusionAfterAbort() async {
        let coordinator = AppExitCoordinator()
        let counter = InstallCounter()
        let gate = CleanupGate()
        let quitStarted = StartSignal()
        let update = Task { @MainActor in
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
        // 一般退出加入同一個清理。
        let quit = Task { @MainActor in
            quitStarted.signal()
            return await coordinator.performExitSequence { true }
        }
        await quitStarted.wait()
        gate.open()
        _ = await update.value
        #expect(await quit.value)
        #expect(!coordinator.allowsDeviceOperations)
        // 框架真的中止了這次更新，一般退出的封鎖必須留著。
        coordinator.abortUpdateInstall()
        #expect(coordinator.phase == .ready)
        #expect(!coordinator.allowsDeviceOperations)
    }
}
