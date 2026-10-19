//
//  PointingGeometry.swift
//  leanring-buddy
//
//  Coordinate conversions between the three spaces pointing passes through:
//  - AppKit global: origin at the bottom-left of the primary display, y up.
//  - Accessibility (AX): origin at the top-left of the primary display, y down.
//  - Overlay local: SwiftUI top-left space of one screen's overlay window.
//  Plus where the companion parks next to a target so it never covers it.
//

import CoreGraphics

nonisolated enum PointingGeometry {

    /// The model gives [POINT] coordinates on a 0-1000 grid over the
    /// screenshot (0,0 top-left, 1000,1000 bottom-right). Vision models are
    /// trained on that grid: on a test screen, asking for screenshot pixels
    /// instead left most points ~200 px off.
    static let pointingGridSize: CGFloat = 1000

    /// A grid point as a point on the display, top-left origin, clamped to
    /// the display.
    static func displayLocalPoint(fromGridPoint gridPoint: CGPoint, displaySize: CGSize) -> CGPoint {
        let clampedGridX = min(max(gridPoint.x, 0), pointingGridSize)
        let clampedGridY = min(max(gridPoint.y, 0), pointingGridSize)
        return CGPoint(
            x: clampedGridX / pointingGridSize * displaySize.width,
            y: clampedGridY / pointingGridSize * displaySize.height
        )
    }

    /// A grid point over one display's screenshot as an AppKit global point
    /// (bottom-left origin). Both the chat model's and the grounding model's
    /// points go through here so they land in the same space.
    static func appKitGlobalPoint(fromGridPoint gridPoint: CGPoint, displaySize: CGSize, displayFrame: CGRect) -> CGPoint {
        let pointOnDisplay = displayLocalPoint(fromGridPoint: gridPoint, displaySize: displaySize)
        // The screenshot's origin is top-left; AppKit's is bottom-left.
        let appKitYOnDisplay = displaySize.height - pointOnDisplay.y
        return CGPoint(
            x: pointOnDisplay.x + displayFrame.origin.x,
            y: appKitYOnDisplay + displayFrame.origin.y
        )
    }

    static func accessibilityPoint(fromAppKitGlobalPoint appKitGlobalPoint: CGPoint, primaryScreenHeight: CGFloat) -> CGPoint {
        CGPoint(x: appKitGlobalPoint.x, y: primaryScreenHeight - appKitGlobalPoint.y)
    }

    static func appKitGlobalRect(fromAccessibilityPosition accessibilityPosition: CGPoint, size: CGSize, primaryScreenHeight: CGFloat) -> CGRect {
        CGRect(
            x: accessibilityPosition.x,
            y: primaryScreenHeight - accessibilityPosition.y - size.height,
            width: size.width,
            height: size.height
        )
    }

    static func overlayLocalRect(fromAppKitGlobalRect appKitGlobalRect: CGRect, screenFrame: CGRect) -> CGRect {
        CGRect(
            x: appKitGlobalRect.minX - screenFrame.minX,
            y: screenFrame.maxY - appKitGlobalRect.maxY,
            width: appKitGlobalRect.width,
            height: appKitGlobalRect.height
        )
    }

    /// Just outside the target's bottom-left corner. Flips to the right side
    /// when that would leave the screen on the left, above the target when it
    /// would leave at the bottom, then clamps so the whole companion stays on
    /// screen.
    static func companionParkingPoint(
        forTargetRectInOverlay targetRect: CGRect,
        overlaySize: CGSize,
        companionRadius: CGFloat,
        gap: CGFloat
    ) -> CGPoint {
        let clearance = gap + companionRadius

        var parkingX = targetRect.minX - clearance
        if parkingX < companionRadius {
            parkingX = targetRect.maxX + clearance
        }

        var parkingY = targetRect.maxY + clearance
        if parkingY > overlaySize.height - companionRadius {
            parkingY = targetRect.minY - clearance
        }

        return CGPoint(
            x: min(max(parkingX, companionRadius), overlaySize.width - companionRadius),
            y: min(max(parkingY, companionRadius), overlaySize.height - companionRadius)
        )
    }

    /// Where the pointing bubble goes: below-right of the companion, except
    /// when the companion parked above the target (bottom-edge flip), where
    /// below would cover the target, so the bubble goes above the companion.
    static func pointingBubbleCenter(companionPoint: CGPoint, bubbleSize: CGSize, targetRectInOverlay: CGRect?) -> CGPoint {
        let bubbleCenterX = companionPoint.x + 10 + bubbleSize.width / 2
        if let targetRectInOverlay, companionPoint.y < targetRectInOverlay.minY {
            return CGPoint(x: bubbleCenterX, y: companionPoint.y - 14 - bubbleSize.height / 2)
        }
        return CGPoint(x: bubbleCenterX, y: companionPoint.y + 18)
    }
}
