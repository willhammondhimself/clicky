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
}
