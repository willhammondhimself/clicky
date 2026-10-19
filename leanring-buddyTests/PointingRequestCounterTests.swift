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

    @Test func theLookupAtTheChatModelsPointAppliesWhenNothingElseHas() {
        var pointingRequestCounter = PointingRequestCounter()
        let requestNumber = pointingRequestCounter.beginRequest()
        let chatModelRectWasApplied = pointingRequestCounter.claimTargetRect(forRequest: requestNumber, from: .lookupAtChatModelPoint)
        #expect(chatModelRectWasApplied)
    }

    @Test func theGroundedRectReplacesTheChatModelsRect() {
        // Usual order: the chat model's lookup (≤1.4 s) lands first, the
        // grounding model's point (2.5-4 s after speech starts) corrects it.
        var pointingRequestCounter = PointingRequestCounter()
        let requestNumber = pointingRequestCounter.beginRequest()
        let chatModelRectWasApplied = pointingRequestCounter.claimTargetRect(forRequest: requestNumber, from: .lookupAtChatModelPoint)
        #expect(chatModelRectWasApplied)
        let groundedRectWasApplied = pointingRequestCounter.claimTargetRect(forRequest: requestNumber, from: .lookupAtGroundedPoint)
        #expect(groundedRectWasApplied)
    }

    @Test func aLateChatModelLookupCannotOverwriteTheGroundedRect() {
        // A slow app makes the chat model's lookup finish after grounding:
        // the box at the less accurate point must not win.
        var pointingRequestCounter = PointingRequestCounter()
        let requestNumber = pointingRequestCounter.beginRequest()
        let groundedRectWasApplied = pointingRequestCounter.claimTargetRect(forRequest: requestNumber, from: .lookupAtGroundedPoint)
        #expect(groundedRectWasApplied)
        let lateChatModelRectWasApplied = pointingRequestCounter.claimTargetRect(forRequest: requestNumber, from: .lookupAtChatModelPoint)
        #expect(!lateChatModelRectWasApplied)
        #expect(pointingRequestCounter.isCurrent(requestNumber))
    }

    @Test func aStaleRequestClaimsNothing() {
        var pointingRequestCounter = PointingRequestCounter()
        let firstRequestNumber = pointingRequestCounter.beginRequest()
        pointingRequestCounter.invalidateCurrentRequest()
        let staleGroundedRectWasApplied = pointingRequestCounter.claimTargetRect(forRequest: firstRequestNumber, from: .lookupAtGroundedPoint)
        #expect(!staleGroundedRectWasApplied)
    }

    @Test func aNewRequestStartsWithNoRectClaimed() {
        // Reply A was grounded; reply B's chat-model lookup must still apply.
        var pointingRequestCounter = PointingRequestCounter()
        let replyARequestNumber = pointingRequestCounter.beginRequest()
        let replyAGroundedRectWasApplied = pointingRequestCounter.claimTargetRect(forRequest: replyARequestNumber, from: .lookupAtGroundedPoint)
        #expect(replyAGroundedRectWasApplied)
        let replyBRequestNumber = pointingRequestCounter.beginRequest()
        let replyBChatModelRectWasApplied = pointingRequestCounter.claimTargetRect(forRequest: replyBRequestNumber, from: .lookupAtChatModelPoint)
        #expect(replyBChatModelRectWasApplied)
    }

    @Test func noRequestIsCurrentBeforeTheFirstBegins() {
        let pointingRequestCounter = PointingRequestCounter()
        #expect(!pointingRequestCounter.isCurrent(0))
    }
}
