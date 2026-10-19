import CoreGraphics
import Testing

#if canImport(leanring_buddy)
@testable import leanring_buddy
#else
@testable import LumenLogic
#endif

struct WindowUnderPointSelectionTests {

    private let ownProcessIdentifier: Int32 = 4242
    private let point = CGPoint(x: 300, y: 200)

    private func window(_ processIdentifier: Int32, _ bounds: CGRect, alpha: Double = 1) -> OnScreenWindowInfo {
        OnScreenWindowInfo(processIdentifier: processIdentifier, boundsInAccessibilitySpace: bounds, alpha: alpha)
    }

    @Test func skipsLumensOwnFullScreenOverlay() {
        let windowsFrontToBack = [
            window(ownProcessIdentifier, CGRect(x: 0, y: 0, width: 1512, height: 982)),
            window(777, CGRect(x: 100, y: 100, width: 800, height: 500)),
        ]
        #expect(WindowUnderPointSelection.processIdentifierOfTopmostWindow(
            atAccessibilityPoint: point,
            windowsFrontToBack: windowsFrontToBack,
            ownProcessIdentifier: ownProcessIdentifier
        ) == 777)
    }

    @Test func skipsFullyTransparentWindows() {
        let windowsFrontToBack = [
            window(555, CGRect(x: 0, y: 0, width: 1512, height: 982), alpha: 0),
            window(777, CGRect(x: 100, y: 100, width: 800, height: 500)),
        ]
        #expect(WindowUnderPointSelection.processIdentifierOfTopmostWindow(
            atAccessibilityPoint: point,
            windowsFrontToBack: windowsFrontToBack,
            ownProcessIdentifier: ownProcessIdentifier
        ) == 777)
    }

    @Test func picksTheFrontmostWindowContainingThePoint() {
        let windowsFrontToBack = [
            window(111, CGRect(x: 1000, y: 0, width: 200, height: 200)),
            window(222, CGRect(x: 250, y: 150, width: 200, height: 200)),
            window(333, CGRect(x: 0, y: 0, width: 1512, height: 982)),
        ]
        #expect(WindowUnderPointSelection.processIdentifierOfTopmostWindow(
            atAccessibilityPoint: point,
            windowsFrontToBack: windowsFrontToBack,
            ownProcessIdentifier: ownProcessIdentifier
        ) == 222)
    }

    @Test func returnsNilWhenNoWindowContainsThePoint() {
        #expect(WindowUnderPointSelection.processIdentifierOfTopmostWindow(
            atAccessibilityPoint: point,
            windowsFrontToBack: [window(111, CGRect(x: 1000, y: 0, width: 200, height: 200))],
            ownProcessIdentifier: ownProcessIdentifier
        ) == nil)
    }
}
