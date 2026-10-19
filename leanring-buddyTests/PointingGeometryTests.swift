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
}
