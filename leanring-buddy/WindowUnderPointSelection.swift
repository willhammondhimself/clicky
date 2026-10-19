//
//  WindowUnderPointSelection.swift
//  leanring-buddy
//
//  Which app owns the window under a pointing coordinate. Lumen's own
//  full-screen overlay sits above every app at screen-saver level, so a
//  system-wide Accessibility hit test could land on it instead of the app
//  underneath. Picking the topmost window from the on-screen window list
//  that is not Lumen's (and not fully transparent) and then hit-testing that
//  app's own Accessibility element sidesteps the overlay entirely.
//

import CoreGraphics

nonisolated struct OnScreenWindowInfo: Equatable {
    let processIdentifier: Int32
    /// Window bounds in global top-left-origin coordinates, the same space
    /// Accessibility uses (this is what CGWindowListCopyWindowInfo reports).
    let boundsInAccessibilitySpace: CGRect
    let alpha: Double
}

nonisolated enum WindowUnderPointSelection {
    static func processIdentifierOfTopmostWindow(
        atAccessibilityPoint accessibilityPoint: CGPoint,
        windowsFrontToBack: [OnScreenWindowInfo],
        ownProcessIdentifier: Int32
    ) -> Int32? {
        windowsFrontToBack.first { windowInfo in
            windowInfo.processIdentifier != ownProcessIdentifier
                && windowInfo.alpha > 0
                && windowInfo.boundsInAccessibilitySpace.contains(accessibilityPoint)
        }?.processIdentifier
    }
}
