import Testing
import UTUVOMouseSupport

@Suite("Automatic re-read policy")
struct WakeRetryPolicyTests {
    @Test("an incomplete read is retried, then stops after the bound")
    func incompleteBounded() {
        var retries = 0
        for read in 1...WakeRetryPolicy.maxIncompleteReadRetries {
            let d = WakeRetryPolicy.decide(receiverWaiting: false, incompleteRead: true, retries: retries, afterRead: true)
            #expect(d.retry, "read \(read) should schedule a retry")
            retries = d.retries
        }
        let last = WakeRetryPolicy.decide(receiverWaiting: false, incompleteRead: true, retries: retries, afterRead: true)
        #expect(!last.retry)
    }

    @Test("a complete read resets the count and stops retrying")
    func completeResets() {
        let d = WakeRetryPolicy.decide(receiverWaiting: false, incompleteRead: false, retries: 7, afterRead: true)
        #expect(!d.retry && d.retries == 0)
    }

    @Test("a sleeping mouse behind a receiver keeps being checked")
    func receiverUnbounded() {
        let d = WakeRetryPolicy.decide(receiverWaiting: true, incompleteRead: true, retries: 99, afterRead: true)
        #expect(d.retry)
    }

    @Test("calls that are not a read do not use up retries")
    func nonReadDoesNotCount() {
        let d = WakeRetryPolicy.decide(receiverWaiting: false, incompleteRead: true, retries: 3, afterRead: false)
        #expect(d.retry && d.retries == 3)
    }
}
