import Testing

#if canImport(leanring_buddy)
@testable import leanring_buddy
#else
@testable import LumenLogic
#endif

struct PointingHoldScheduleTests {

    @Test func theBubbleFinishingStartsTheThreeSecondHold() {
        var pointingHoldSchedule = PointingHoldSchedule()
        pointingHoldSchedule.beginPointing()
        let flyBack = pointingHoldSchedule.bubbleFinishedStreaming(atSeconds: 100)
        #expect(flyBack.delaySeconds == 3)
        #expect(pointingHoldSchedule.isCurrent(flyBack.generation))
    }

    @Test func aTargetChangeAfterTheBubbleRestartsTheHoldFromThatMoment() {
        // The grounded rect lands 2 s into the hold: the user still gets 3 s
        // to see the corrected mark.
        var pointingHoldSchedule = PointingHoldSchedule()
        pointingHoldSchedule.beginPointing()
        let firstFlyBack = pointingHoldSchedule.bubbleFinishedStreaming(atSeconds: 100)

        let extendedFlyBack = pointingHoldSchedule.targetRectChanged(atSeconds: 102)
        #expect(extendedFlyBack?.delaySeconds == 3)
        #expect(!pointingHoldSchedule.isCurrent(firstFlyBack.generation))
        #expect(extendedFlyBack.map { pointingHoldSchedule.isCurrent($0.generation) } == true)
    }

    @Test func extensionsAreCappedAtEightSecondsPastTheBubble() {
        var pointingHoldSchedule = PointingHoldSchedule()
        pointingHoldSchedule.beginPointing()
        _ = pointingHoldSchedule.bubbleFinishedStreaming(atSeconds: 100)

        let partlyCappedFlyBack = pointingHoldSchedule.targetRectChanged(atSeconds: 106)
        // 106 + 3 would be 109; the cap is 100 + 8.
        #expect(partlyCappedFlyBack?.delaySeconds == 2)

        // Already flying back at the cap: a later change can't push it further.
        let flyBackAfterTargetChange = pointingHoldSchedule.targetRectChanged(atSeconds: 107)
        #expect(flyBackAfterTargetChange == nil)
    }

    @Test func aTargetChangeBeforeTheBubbleFinishesNeedsNoNewTimer() {
        // Mid-flight or while the bubble types: the hold hasn't started yet
        // and will start from the bubble anyway.
        var pointingHoldSchedule = PointingHoldSchedule()
        pointingHoldSchedule.beginPointing()
        let flyBackAfterTargetChange = pointingHoldSchedule.targetRectChanged(atSeconds: 50)
        #expect(flyBackAfterTargetChange == nil)
    }

    @Test func aChangeThatWouldShortenTheHoldIsIgnored() {
        var pointingHoldSchedule = PointingHoldSchedule()
        pointingHoldSchedule.beginPointing()
        let firstFlyBack = pointingHoldSchedule.bubbleFinishedStreaming(atSeconds: 100)
        // Same instant as the bubble finishing: the hold already ends at 103.
        let flyBackAfterTargetChange = pointingHoldSchedule.targetRectChanged(atSeconds: 100)
        #expect(flyBackAfterTargetChange == nil)
        #expect(pointingHoldSchedule.isCurrent(firstFlyBack.generation))
    }

    @Test func aNewPointingMakesTheOldFlyBackTimerStale() {
        var pointingHoldSchedule = PointingHoldSchedule()
        pointingHoldSchedule.beginPointing()
        let oldFlyBack = pointingHoldSchedule.bubbleFinishedStreaming(atSeconds: 100)

        pointingHoldSchedule.beginPointing()
        #expect(!pointingHoldSchedule.isCurrent(oldFlyBack.generation))
        // The new pointing's bubble hasn't finished, so nothing to extend.
        let flyBackAfterTargetChange = pointingHoldSchedule.targetRectChanged(atSeconds: 101)
        #expect(flyBackAfterTargetChange == nil)
    }

    @Test func theHoldEndsNormallyWhenNoCorrectionIsPending() {
        var pointingHoldSchedule = PointingHoldSchedule()
        pointingHoldSchedule.beginPointing()
        let flyBack = pointingHoldSchedule.bubbleFinishedStreaming(atSeconds: 100)
        let holdEndOutcome = pointingHoldSchedule.holdTimerFired(
            generation: flyBack.generation,
            atSeconds: 103,
            isCorrectionPending: false
        )
        #expect(holdEndOutcome == .flyBack)
    }

    @Test func aStaleHoldTimerDoesNothing() {
        var pointingHoldSchedule = PointingHoldSchedule()
        pointingHoldSchedule.beginPointing()
        let oldFlyBack = pointingHoldSchedule.bubbleFinishedStreaming(atSeconds: 100)
        _ = pointingHoldSchedule.targetRectChanged(atSeconds: 102)
        let holdEndOutcome = pointingHoldSchedule.holdTimerFired(
            generation: oldFlyBack.generation,
            atSeconds: 103,
            isCorrectionPending: false
        )
        #expect(holdEndOutcome == .stale)
    }

    @Test func aPendingCorrectionKeepsThePointingOpenUntilTheCap() {
        // The grounding model is still answering when the 3 s hold ends:
        // flying back now would throw its answer away.
        var pointingHoldSchedule = PointingHoldSchedule()
        pointingHoldSchedule.beginPointing()
        let flyBack = pointingHoldSchedule.bubbleFinishedStreaming(atSeconds: 100)
        let holdEndOutcome = pointingHoldSchedule.holdTimerFired(
            generation: flyBack.generation,
            atSeconds: 103,
            isCorrectionPending: true
        )
        guard case .waitForCorrection(let capFlyBack) = holdEndOutcome else {
            Issue.record("expected to wait for the correction, got \(holdEndOutcome)")
            return
        }
        #expect(capFlyBack.delaySeconds == 5)
        #expect(pointingHoldSchedule.isCurrent(capFlyBack.generation))
        #expect(!pointingHoldSchedule.isCurrent(flyBack.generation))
    }

    @Test func aCorrectionArrivingWhileWaitingGetsItsFullHoldWithinTheCap() {
        var pointingHoldSchedule = PointingHoldSchedule()
        pointingHoldSchedule.beginPointing()
        let flyBack = pointingHoldSchedule.bubbleFinishedStreaming(atSeconds: 100)
        let holdEndOutcome = pointingHoldSchedule.holdTimerFired(
            generation: flyBack.generation,
            atSeconds: 103,
            isCorrectionPending: true
        )
        guard case .waitForCorrection(let capFlyBack) = holdEndOutcome else {
            Issue.record("expected to wait for the correction, got \(holdEndOutcome)")
            return
        }

        let correctedFlyBack = pointingHoldSchedule.targetRectChanged(atSeconds: 104)
        #expect(correctedFlyBack?.delaySeconds == 3)
        #expect(!pointingHoldSchedule.isCurrent(capFlyBack.generation))
        #expect(correctedFlyBack.map { pointingHoldSchedule.isCurrent($0.generation) } == true)
    }

    @Test func aCorrectionArrivingLateWhileWaitingStillStopsAtTheCap() {
        var pointingHoldSchedule = PointingHoldSchedule()
        pointingHoldSchedule.beginPointing()
        let flyBack = pointingHoldSchedule.bubbleFinishedStreaming(atSeconds: 100)
        _ = pointingHoldSchedule.holdTimerFired(generation: flyBack.generation, atSeconds: 103, isCorrectionPending: true)

        let correctedFlyBack = pointingHoldSchedule.targetRectChanged(atSeconds: 106.5)
        #expect(correctedFlyBack?.delaySeconds == 1.5)
    }

    @Test func aCorrectionThatEndsWithoutAMoveWhileWaitingFliesBackAtOnce() {
        // The grounding model gave no usable point, or failed.
        var pointingHoldSchedule = PointingHoldSchedule()
        pointingHoldSchedule.beginPointing()
        let flyBack = pointingHoldSchedule.bubbleFinishedStreaming(atSeconds: 100)
        let holdEndOutcome = pointingHoldSchedule.holdTimerFired(
            generation: flyBack.generation,
            atSeconds: 103,
            isCorrectionPending: true
        )
        guard case .waitForCorrection(let capFlyBack) = holdEndOutcome else {
            Issue.record("expected to wait for the correction, got \(holdEndOutcome)")
            return
        }

        let immediateFlyBack = pointingHoldSchedule.correctionFinished(atSeconds: 104)
        #expect(immediateFlyBack?.delaySeconds == 0)
        #expect(!pointingHoldSchedule.isCurrent(capFlyBack.generation))
        #expect(immediateFlyBack.map { pointingHoldSchedule.isCurrent($0.generation) } == true)
    }

    @Test func aCorrectionThatEndsBeforeTheHoldEndsChangesNothing() {
        var pointingHoldSchedule = PointingHoldSchedule()
        pointingHoldSchedule.beginPointing()
        let flyBack = pointingHoldSchedule.bubbleFinishedStreaming(atSeconds: 100)
        #expect(pointingHoldSchedule.correctionFinished(atSeconds: 101) == nil)
        #expect(pointingHoldSchedule.isCurrent(flyBack.generation))
    }

    @Test func aCorrectionThatEndsAfterTheMarkMovedChangesNothing() {
        // The grounded rect restarted the hold; the request ending right
        // after must not cut that hold short.
        var pointingHoldSchedule = PointingHoldSchedule()
        pointingHoldSchedule.beginPointing()
        let flyBack = pointingHoldSchedule.bubbleFinishedStreaming(atSeconds: 100)
        _ = pointingHoldSchedule.holdTimerFired(generation: flyBack.generation, atSeconds: 103, isCorrectionPending: true)
        let correctedFlyBack = pointingHoldSchedule.targetRectChanged(atSeconds: 104)

        #expect(pointingHoldSchedule.correctionFinished(atSeconds: 104) == nil)
        #expect(correctedFlyBack.map { pointingHoldSchedule.isCurrent($0.generation) } == true)
    }

    @Test func theCapTimerFliesBackEvenWhileTheCorrectionIsStillPending() {
        // A cold model load can take longer than the cap; the companion
        // doesn't wait forever.
        var pointingHoldSchedule = PointingHoldSchedule()
        pointingHoldSchedule.beginPointing()
        let flyBack = pointingHoldSchedule.bubbleFinishedStreaming(atSeconds: 100)
        let holdEndOutcome = pointingHoldSchedule.holdTimerFired(
            generation: flyBack.generation,
            atSeconds: 103,
            isCorrectionPending: true
        )
        guard case .waitForCorrection(let capFlyBack) = holdEndOutcome else {
            Issue.record("expected to wait for the correction, got \(holdEndOutcome)")
            return
        }
        let capOutcome = pointingHoldSchedule.holdTimerFired(
            generation: capFlyBack.generation,
            atSeconds: 108,
            isCorrectionPending: true
        )
        #expect(capOutcome == .flyBack)
    }

    @Test func aPendingCorrectionPastTheCapDoesNotHoldAnyLonger() throws {
        // A late rect already pushed the hold to the cap, and another
        // correction is somehow still pending when it ends.
        var pointingHoldSchedule = PointingHoldSchedule()
        pointingHoldSchedule.beginPointing()
        _ = pointingHoldSchedule.bubbleFinishedStreaming(atSeconds: 100)
        let possiblyCappedFlyBack = pointingHoldSchedule.targetRectChanged(atSeconds: 106)
        let cappedFlyBack = try #require(possiblyCappedFlyBack)
        let holdEndOutcome = pointingHoldSchedule.holdTimerFired(
            generation: cappedFlyBack.generation,
            atSeconds: 108,
            isCorrectionPending: true
        )
        #expect(holdEndOutcome == .flyBack)
    }

    @Test func endingThePointingMakesEveryTimerStale() {
        var pointingHoldSchedule = PointingHoldSchedule()
        pointingHoldSchedule.beginPointing()
        let flyBack = pointingHoldSchedule.bubbleFinishedStreaming(atSeconds: 100)
        pointingHoldSchedule.endPointing()
        #expect(!pointingHoldSchedule.isCurrent(flyBack.generation))
        let flyBackAfterTargetChange = pointingHoldSchedule.targetRectChanged(atSeconds: 101)
        #expect(flyBackAfterTargetChange == nil)
    }
}
