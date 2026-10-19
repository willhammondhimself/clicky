//
//  CompanionAutoHideMonitor.swift
//  leanring-buddy
//
//  Feeds CompanionAutoHide: polls the mouse four times a second, watches
//  keystrokes in other apps, and checks once a second whether the frontmost
//  app has a full-screen window. Keystrokes typed into Lumen's own panel
//  never reach a global monitor, so typing there doesn't hide the companion.
//  Reports only changes, through `onShouldHideChange`.
//

import AppKit

final class CompanionAutoHideMonitor {
    /// Read on every check; the companion never hides while this is true.
    var isLumenBusy: () -> Bool = { false }
    var onShouldHideChange: (Bool) -> Void = { _ in }

    private static let pollInterval: Duration = .milliseconds(250)
    /// The window list is the costliest check, so it runs every fourth poll.
    private static let pollsPerFullScreenCheck = 4

    private var lastMouseLocation = NSEvent.mouseLocation
    private var lastMouseMovedAt = Date()
    private var lastTypedAt: Date?
    private var isFrontmostAppFullScreen = false
    private var pollCount = 0
    private var currentShouldHide = false
    private var pollTask: Task<Void, Never>?
    private var keyDownMonitor: Any?

    func start() {
        guard pollTask == nil else { return }

        // Global key monitors need the Accessibility permission, which Lumen
        // already holds for push-to-talk.
        keyDownMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] keyDownEvent in
            let modifierFlags = keyDownEvent.modifierFlags
            let isTyping = CompanionAutoHide.countsAsTyping(
                hasCommandModifier: modifierFlags.contains(.command),
                hasControlModifier: modifierFlags.contains(.control)
            )
            guard isTyping else { return }
            Task { @MainActor in
                self?.lastTypedAt = Date()
                self?.evaluate()
            }
        }

        pollTask = Task { [weak self] in
            while !Task.isCancelled {
                self?.poll()
                try? await Task.sleep(for: Self.pollInterval)
            }
        }
    }

    func stop() {
        pollTask?.cancel()
        pollTask = nil
        if let keyDownMonitor {
            NSEvent.removeMonitor(keyDownMonitor)
        }
        keyDownMonitor = nil
    }

    private func poll() {
        let mouseLocation = NSEvent.mouseLocation
        if mouseLocation != lastMouseLocation {
            lastMouseLocation = mouseLocation
            lastMouseMovedAt = Date()
        }

        if pollCount % Self.pollsPerFullScreenCheck == 0 {
            isFrontmostAppFullScreen = Self.frontmostAppHasFullScreenWindow()
        }
        pollCount += 1

        evaluate()
    }

    private func evaluate() {
        let hasTypedSinceMouseMoved = lastTypedAt.map { $0 > lastMouseMovedAt } ?? false
        let shouldHide = CompanionAutoHide.shouldHide(
            secondsSinceMouseMoved: Date().timeIntervalSince(lastMouseMovedAt),
            hasTypedSinceMouseMoved: hasTypedSinceMouseMoved,
            isFrontmostAppFullScreen: isFrontmostAppFullScreen,
            isLumenBusy: isLumenBusy()
        )
        guard shouldHide != currentShouldHide else { return }
        currentShouldHide = shouldHide
        onShouldHideChange(shouldHide)
    }

    /// Owner pid and bounds come from the window server without Screen
    /// Recording permission; display and window bounds share its top-left space.
    private static func frontmostAppHasFullScreenWindow() -> Bool {
        guard let frontmostProcessIdentifier = NSWorkspace.shared.frontmostApplication?.processIdentifier,
              let windowDictionaries = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] else {
            return false
        }

        var activeDisplayIdentifiers = [CGDirectDisplayID](repeating: 0, count: 16)
        var activeDisplayCount: UInt32 = 0
        CGGetActiveDisplayList(UInt32(activeDisplayIdentifiers.count), &activeDisplayIdentifiers, &activeDisplayCount)
        let displayBoundsList = activeDisplayIdentifiers.prefix(Int(activeDisplayCount)).map { CGDisplayBounds($0) }

        return windowDictionaries.contains { windowDictionary in
            guard (windowDictionary[kCGWindowOwnerPID as String] as? Int32) == frontmostProcessIdentifier,
                  (windowDictionary[kCGWindowLayer as String] as? Int) == 0,
                  let boundsDictionary = windowDictionary[kCGWindowBounds as String] as? NSDictionary,
                  let windowBounds = CGRect(dictionaryRepresentation: boundsDictionary as CFDictionary) else { return false }
            return CompanionAutoHide.isFullScreen(windowBounds: windowBounds, displayBoundsList: displayBoundsList)
        }
    }
}
