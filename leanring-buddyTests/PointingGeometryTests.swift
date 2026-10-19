import CoreGraphics
import Testing

#if canImport(leanring_buddy)
@testable import leanring_buddy
#else
@testable import LumenLogic
#endif

struct PointingGeometryTests {

    private let primaryScreenHeight: CGFloat = 982

    @Test func accessibilityPointFlipsAgainstThePrimaryScreen() {
        let accessibilityPoint = PointingGeometry.accessibilityPoint(
            fromAppKitGlobalPoint: CGPoint(x: 100, y: 900),
            primaryScreenHeight: primaryScreenHeight
        )
        #expect(accessibilityPoint == CGPoint(x: 100, y: 82))
    }

    @Test func conversionsRoundTripOnDisplayLeftOfAndAbovePrimary() {
        // A 1920x1080 display sitting above and to the left of the primary.
        let screenFrame = CGRect(x: -1920, y: 982, width: 1920, height: 1080)
        let appKitRect = PointingGeometry.appKitGlobalRect(
            fromAccessibilityPosition: CGPoint(x: -1500, y: -400),
            size: CGSize(width: 80, height: 24),
            primaryScreenHeight: primaryScreenHeight
        )
        #expect(appKitRect == CGRect(x: -1500, y: 1358, width: 80, height: 24))

        let backToAccessibility = PointingGeometry.accessibilityPoint(
            fromAppKitGlobalPoint: CGPoint(x: appKitRect.minX, y: appKitRect.maxY),
            primaryScreenHeight: primaryScreenHeight
        )
        #expect(backToAccessibility == CGPoint(x: -1500, y: -400))

        let overlayRect = PointingGeometry.overlayLocalRect(fromAppKitGlobalRect: appKitRect, screenFrame: screenFrame)
        #expect(overlayRect == CGRect(x: 420, y: 680, width: 80, height: 24))
    }

    @Test func overlayLocalRectOnPrimary() {
        let overlayRect = PointingGeometry.overlayLocalRect(
            fromAppKitGlobalRect: CGRect(x: 100, y: 900, width: 50, height: 20),
            screenFrame: CGRect(x: 0, y: 0, width: 1512, height: 982)
        )
        #expect(overlayRect == CGRect(x: 100, y: 62, width: 50, height: 20))
    }

    @Test func parkingSitsBelowLeftOfTheTarget() {
        let parkingPoint = PointingGeometry.companionParkingPoint(
            forTargetRectInOverlay: CGRect(x: 200, y: 200, width: 80, height: 24),
            overlaySize: CGSize(width: 1512, height: 982),
            companionRadius: 8,
            gap: 6
        )
        #expect(parkingPoint == CGPoint(x: 186, y: 238))
    }

    @Test func bubbleSitsBelowRightOfTheCompanionByDefault() {
        let bubbleCenter = PointingGeometry.pointingBubbleCenter(
            companionPoint: CGPoint(x: 186, y: 238),
            bubbleSize: CGSize(width: 90, height: 22),
            targetRectInOverlay: CGRect(x: 200, y: 200, width: 80, height: 24)
        )
        #expect(bubbleCenter == CGPoint(x: 241, y: 256))
    }

    @Test func bubbleNeverCoversTheTargetWhenTheCompanionParksAbove() {
        let overlaySize = CGSize(width: 1512, height: 982)
        let bubbleSize = CGSize(width: 90, height: 22)
        // Targets along the bottom edge make the companion flip above them.
        for targetRect in [CGRect(x: 200, y: 958, width: 80, height: 24), CGRect(x: 0, y: 958, width: 80, height: 24)] {
            let parkingPoint = PointingGeometry.companionParkingPoint(
                forTargetRectInOverlay: targetRect,
                overlaySize: overlaySize,
                companionRadius: 10,
                gap: 6
            )
            let bubbleCenter = PointingGeometry.pointingBubbleCenter(
                companionPoint: parkingPoint,
                bubbleSize: bubbleSize,
                targetRectInOverlay: targetRect
            )
            let bubbleRect = CGRect(
                x: bubbleCenter.x - bubbleSize.width / 2,
                y: bubbleCenter.y - bubbleSize.height / 2,
                width: bubbleSize.width,
                height: bubbleSize.height
            )
            #expect(!bubbleRect.intersects(targetRect), "\(targetRect)")
        }
    }

    @Test func parkingFlipsToStayOnScreenAtEveryCorner() {
        let overlaySize = CGSize(width: 1512, height: 982)
        let companionRadius: CGFloat = 8
        let targetsTouchingEachCorner = [
            CGRect(x: 0, y: 0, width: 80, height: 24),
            CGRect(x: 1432, y: 0, width: 80, height: 24),
            CGRect(x: 0, y: 958, width: 80, height: 24),
            CGRect(x: 1432, y: 958, width: 80, height: 24),
        ]
        for targetRect in targetsTouchingEachCorner {
            let parkingPoint = PointingGeometry.companionParkingPoint(
                forTargetRectInOverlay: targetRect,
                overlaySize: overlaySize,
                companionRadius: companionRadius,
                gap: 6
            )
            #expect(parkingPoint.x >= companionRadius && parkingPoint.x <= overlaySize.width - companionRadius, "\(targetRect)")
            #expect(parkingPoint.y >= companionRadius && parkingPoint.y <= overlaySize.height - companionRadius, "\(targetRect)")
            #expect(!targetRect.contains(parkingPoint), "\(targetRect)")
        }
    }

    // MARK: - Pointing grid

    @Test func gridPointsScaleToTheDisplaysPoints() {
        // The model answers on a 0-1000 grid over the screenshot; a 1512x982
        // display maps (500, 500) to its centre.
        let displaySize = CGSize(width: 1512, height: 982)
        #expect(PointingGeometry.displayLocalPoint(fromGridPoint: CGPoint(x: 500, y: 500), displaySize: displaySize) == CGPoint(x: 756, y: 491))
        #expect(PointingGeometry.displayLocalPoint(fromGridPoint: CGPoint(x: 0, y: 0), displaySize: displaySize) == .zero)
        #expect(PointingGeometry.displayLocalPoint(fromGridPoint: CGPoint(x: 1000, y: 1000), displaySize: displaySize) == CGPoint(x: 1512, y: 982))
    }

    @Test func gridPointsOutsideZeroToAThousandAreClampedToTheScreen() {
        let displaySize = CGSize(width: 1000, height: 500)
        #expect(PointingGeometry.displayLocalPoint(fromGridPoint: CGPoint(x: 1280, y: -40), displaySize: displaySize) == CGPoint(x: 1000, y: 0))
    }
}
