import CoreGraphics
import Testing

#if canImport(leanring_buddy)
@testable import leanring_buddy
#else
@testable import LumenLogic
#endif

struct ElementBoundsSelectionTests {

    private let displayFrame = CGRect(x: 0, y: 0, width: 1512, height: 982)
    private let point = CGPoint(x: 240, y: 500)
    private let ownProcessIdentifier: Int32 = 4242
    private let otherProcessIdentifier: Int32 = 777

    private func candidate(_ role: String?, _ frame: CGRect, processIdentifier: Int32? = nil) -> AccessibilityElementCandidate {
        AccessibilityElementCandidate(
            role: role,
            frameInAppKitGlobal: frame,
            processIdentifier: processIdentifier ?? otherProcessIdentifier
        )
    }

    private func resolve(_ candidates: [AccessibilityElementCandidate], at resolvePoint: CGPoint? = nil) -> TargetRectResolution {
        ElementBoundsSelection.resolve(
            candidatesFromHitUpward: candidates,
            appKitGlobalPoint: resolvePoint ?? point,
            displayFrame: displayFrame,
            ownProcessIdentifier: ownProcessIdentifier
        )
    }

    private var expectedFallbackBox: TargetRectResolution {
        TargetRectResolution(rectInAppKitGlobal: CGRect(x: 218, y: 486, width: 44, height: 28), source: .fallbackBox)
    }

    @Test func emptyCandidatesFallBackToBox() {
        #expect(resolve([]) == expectedFallbackBox)
    }

    @Test func ownProcessHitFallsBackToBox() {
        let lumenOverlayHit = candidate("AXButton", CGRect(x: 200, y: 490, width: 80, height: 24), processIdentifier: ownProcessIdentifier)
        #expect(resolve([lumenOverlayHit]) == expectedFallbackBox)
    }

    @Test func containerRoleHitFallsBackToBox() {
        #expect(resolve([candidate("AXWebArea", CGRect(x: 100, y: 400, width: 300, height: 200))]) == expectedFallbackBox)
    }

    @Test func hugeHitFallsBackToBox() {
        // 800 x 557 is about 30 % of the 1512 x 982 display.
        #expect(resolve([candidate("AXGroup", CGRect(x: 0, y: 200, width: 800, height: 557))]) == expectedFallbackBox)
    }

    @Test func normalButtonIsUsedAsIs() {
        let buttonFrame = CGRect(x: 200, y: 490, width: 80, height: 24)
        #expect(resolve([candidate("AXButton", buttonFrame)]) == TargetRectResolution(rectInAppKitGlobal: buttonFrame, source: .accessibilityElement))
    }

    @Test func tinyHitWalksUpToTheButton() {
        let buttonFrame = CGRect(x: 200, y: 490, width: 80, height: 24)
        let candidates = [
            candidate("AXStaticText", CGRect(x: 210, y: 498, width: 30, height: 8)),
            candidate("AXButton", buttonFrame),
            candidate("AXWindow", displayFrame),
        ]
        #expect(resolve(candidates) == TargetRectResolution(rectInAppKitGlobal: buttonFrame, source: .accessibilityElement))
    }

    @Test func tinyHitWithOnlyHugeParentsKeepsTheTinyElement() {
        let textFrame = CGRect(x: 210, y: 498, width: 30, height: 8)
        let candidates = [
            candidate("AXStaticText", textFrame),
            candidate("AXWindow", displayFrame),
        ]
        #expect(resolve(candidates) == TargetRectResolution(rectInAppKitGlobal: textFrame, source: .accessibilityElement))
    }

    @Test func rectIsClippedToTheDisplay() {
        let halfOffScreenButton = CGRect(x: 1480, y: 490, width: 80, height: 24)
        #expect(resolve([candidate("AXButton", halfOffScreenButton)], at: CGPoint(x: 1500, y: 500))
            == TargetRectResolution(rectInAppKitGlobal: CGRect(x: 1480, y: 490, width: 32, height: 24), source: .accessibilityElement))
    }

    @Test func fallbackBoxIsClippedAtTheDisplayEdge() {
        #expect(resolve([], at: CGPoint(x: 5, y: 500))
            == TargetRectResolution(rectInAppKitGlobal: CGRect(x: 0, y: 486, width: 27, height: 28), source: .fallbackBox))
    }
}
