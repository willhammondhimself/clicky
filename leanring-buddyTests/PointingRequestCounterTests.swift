import Testing

#if canImport(leanring_buddy)
@testable import leanring_buddy
#else
@testable import LumenLogic
#endif

struct PointingRequestCounterTests {

    @Test func aRequestIsCurrentUntilAnotherBegins() {
        var pointingRequestCounter = PointingRequestCounter()
        let firstRequestNumber = pointingRequestCounter.beginRequest()
        #expect(pointingRequestCounter.isCurrent(firstRequestNumber))

        let secondRequestNumber = pointingRequestCounter.beginRequest()
        #expect(!pointingRequestCounter.isCurrent(firstRequestNumber))
        #expect(pointingRequestCounter.isCurrent(secondRequestNumber))
    }

    @Test func invalidatingMakesTheCurrentRequestStale() {
        // Pointing ended (companion flew back) or the user pressed push-to-talk
        // again: a lookup that finishes afterwards must not move the mark.
        var pointingRequestCounter = PointingRequestCounter()
        let requestNumber = pointingRequestCounter.beginRequest()
        pointingRequestCounter.invalidateCurrentRequest()
        #expect(!pointingRequestCounter.isCurrent(requestNumber))
    }

    @Test func aLateLookupFromAnInterruptedReplyCannotApplyToTheNextReply() {
        // Reply A points, the user interrupts, reply B points, then A's slow
        // Accessibility lookup returns. Only B's lookup may set the rect.
        var pointingRequestCounter = PointingRequestCounter()
        let replyARequestNumber = pointingRequestCounter.beginRequest()
        pointingRequestCounter.invalidateCurrentRequest()
        let replyBRequestNumber = pointingRequestCounter.beginRequest()
        #expect(!pointingRequestCounter.isCurrent(replyARequestNumber))
        #expect(pointingRequestCounter.isCurrent(replyBRequestNumber))
    }

    @Test func noRequestIsCurrentBeforeTheFirstBegins() {
        let pointingRequestCounter = PointingRequestCounter()
        #expect(!pointingRequestCounter.isCurrent(0))
    }
}
