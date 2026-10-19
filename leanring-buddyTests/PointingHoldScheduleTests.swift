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
