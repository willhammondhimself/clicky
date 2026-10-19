//
//  CompanionAutoHide.swift
//  leanring-buddy
//
//  When the companion gets out of the way, following the cursor's own rules:
//  macOS hides the pointer while you type, video players hide it when the
//  mouse sits still, and full-screen apps (games, presentations, videos)
//  usually hide it too. There's no public API to ask whether another app
//  hid the pointer, so Lumen copies those rules. The companion always shows
//  while Lumen is listening, thinking, speaking or pointing.
//

import CoreGraphics

nonisolated enum CompanionAutoHide {
    static let mouseIdleSecondsBeforeHiding: Double = 3

    static func shouldHide(
        secondsSinceMouseMoved: Double,
        hasTypedSinceMouseMoved: Bool,
        isFrontmostAppFullScreen: Bool,
        isLumenBusy: Bool
    ) -> Bool {
        if isLumenBusy { return false }
        return hasTypedSinceMouseMoved
            || isFrontmostAppFullScreen
            || secondsSinceMouseMoved >= mouseIdleSecondsBeforeHiding
    }

    /// Keyboard shortcuts (⌘ or ⌃ held) aren't typing; macOS keeps the
    /// pointer visible for those too.
    static func countsAsTyping(hasCommandModifier: Bool, hasControlModifier: Bool) -> Bool {
        !hasCommandModifier && !hasControlModifier
    }

    /// A window is full screen when it covers a whole display, menu bar
    /// included. Both rects are in the window server's top-left space.
    static func isFullScreen(windowBounds: CGRect, displayBoundsList: [CGRect]) -> Bool {
        let tolerance: CGFloat = 1
        return displayBoundsList.contains { displayBounds in
            abs(windowBounds.minX - displayBounds.minX) <= tolerance
                && abs(windowBounds.minY - displayBounds.minY) <= tolerance
                && abs(windowBounds.width - displayBounds.width) <= tolerance
                && abs(windowBounds.height - displayBounds.height) <= tolerance
        }
    }
}
