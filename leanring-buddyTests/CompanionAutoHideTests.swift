import CoreGraphics
import Testing

#if canImport(leanring_buddy)
@testable import leanring_buddy
#else
@testable import LumenLogic
#endif

struct CompanionAutoHideTests {

    private func shouldHide(
        secondsSinceMouseMoved: Double = 0,
        hasTypedSinceMouseMoved: Bool = false,
        isFrontmostAppFullScreen: Bool = false,
        isLumenBusy: Bool = false
    ) -> Bool {
        CompanionAutoHide.shouldHide(
            secondsSinceMouseMoved: secondsSinceMouseMoved,
            hasTypedSinceMouseMoved: hasTypedSinceMouseMoved,
            isFrontmostAppFullScreen: isFrontmostAppFullScreen,
            isLumenBusy: isLumenBusy
        )
    }

    @Test func visibleWhileTheMouseIsMoving() {
        #expect(!shouldHide())
    }

    @Test func hidesOnceTheUserTypes() {
        #expect(shouldHide(hasTypedSinceMouseMoved: true))
    }

    @Test func hidesAfterTheMouseSitsStillForThreeSeconds() {
        #expect(!shouldHide(secondsSinceMouseMoved: 2.9))
        #expect(shouldHide(secondsSinceMouseMoved: 3))
    }

    @Test func hidesWhileAFullScreenAppIsFrontmost() {
        #expect(shouldHide(isFrontmostAppFullScreen: true))
    }

    @Test func neverHidesWhileLumenIsListeningThinkingSpeakingOrPointing() {
        #expect(!shouldHide(secondsSinceMouseMoved: 60, hasTypedSinceMouseMoved: true, isFrontmostAppFullScreen: true, isLumenBusy: true))
    }

    @Test func shortcutsAreNotTyping() {
        #expect(CompanionAutoHide.countsAsTyping(hasCommandModifier: false, hasControlModifier: false))
        #expect(!CompanionAutoHide.countsAsTyping(hasCommandModifier: true, hasControlModifier: false))
        #expect(!CompanionAutoHide.countsAsTyping(hasCommandModifier: false, hasControlModifier: true))
    }

    @Test func aWindowCoveringAWholeDisplayIsFullScreen() {
        let displays = [CGRect(x: 0, y: 0, width: 1512, height: 982), CGRect(x: 1512, y: -200, width: 2560, height: 1440)]
        #expect(CompanionAutoHide.isFullScreen(windowBounds: CGRect(x: 1512, y: -200, width: 2560, height: 1440), displayBoundsList: displays))
        // Half a point of rounding in the window server's bounds still counts.
        #expect(CompanionAutoHide.isFullScreen(windowBounds: CGRect(x: 0, y: 0, width: 1512, height: 982.5), displayBoundsList: displays))
    }

    @Test func aMaximisedWindowBelowTheMenuBarIsNotFullScreen() {
        let displays = [CGRect(x: 0, y: 0, width: 1512, height: 982)]
        #expect(!CompanionAutoHide.isFullScreen(windowBounds: CGRect(x: 0, y: 33, width: 1512, height: 949), displayBoundsList: displays))
    }
}
