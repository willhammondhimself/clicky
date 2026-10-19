//
//  AccessibilityElementBoundsResolver.swift
//  leanring-buddy
//
//  Asks macOS Accessibility which element sits under the model's pointing
//  coordinate, collects that element and a few ancestors, and hands them to
//  ElementBoundsSelection to pick the rect the skin's mark is drawn around.
//
//  Accessibility calls are synchronous IPC into the target app, so they run
//  off the main actor with a short messaging timeout: a hung app costs at most
//  ~150 ms per call instead of the ~6 s default, and the overlay's animation
//  timers never stall. Lumen already holds the Accessibility permission (the
//  push-to-talk shortcut needs it), so this asks for nothing new.
//

import AppKit
import ApplicationServices

nonisolated enum AccessibilityElementBoundsResolver {
    private static let messagingTimeoutSeconds: Float = 0.15
    private static let maximumAncestorCount = 6

    @MainActor
    static func resolveTargetRect(atAppKitGlobalPoint appKitGlobalPoint: CGPoint, displayFrame: CGRect) async -> TargetRectResolution {
        // NSScreen is main-actor only, so read the primary display here. The
        // primary display is the one whose frame starts at the global origin.
        let primaryScreenHeight = NSScreen.screens.first(where: { $0.frame.origin == .zero })?.frame.height
            ?? NSScreen.screens.first?.frame.height
            ?? displayFrame.height
        let ownProcessIdentifier = getpid()

        let candidatesFromHitUpward = await Task.detached(priority: .userInitiated) {
            collectCandidates(atAppKitGlobalPoint: appKitGlobalPoint, primaryScreenHeight: primaryScreenHeight)
        }.value

        return ElementBoundsSelection.resolve(
            candidatesFromHitUpward: candidatesFromHitUpward,
            appKitGlobalPoint: appKitGlobalPoint,
            displayFrame: displayFrame,
            ownProcessIdentifier: ownProcessIdentifier
        )
    }

    /// The element under the point followed by up to `maximumAncestorCount`
    /// parents. Any Accessibility error ends the walk; an error on the hit
    /// itself returns an empty list, which ElementBoundsSelection treats as a
    /// miss.
    private static func collectCandidates(atAppKitGlobalPoint appKitGlobalPoint: CGPoint, primaryScreenHeight: CGFloat) -> [AccessibilityElementCandidate] {
        let accessibilityPoint = PointingGeometry.accessibilityPoint(
            fromAppKitGlobalPoint: appKitGlobalPoint,
            primaryScreenHeight: primaryScreenHeight
        )

        let systemWideElement = AXUIElementCreateSystemWide()
        // Setting the timeout on the system-wide element applies it to every
        // element queried below.
        AXUIElementSetMessagingTimeout(systemWideElement, messagingTimeoutSeconds)

        var hitElement: AXUIElement?
        let hitResult = AXUIElementCopyElementAtPosition(
            systemWideElement,
            Float(accessibilityPoint.x),
            Float(accessibilityPoint.y),
            &hitElement
        )
        guard hitResult == .success, var currentElement = hitElement else { return [] }

        var candidatesFromHitUpward: [AccessibilityElementCandidate] = []
        for _ in 0...maximumAncestorCount {
            guard let candidate = makeCandidate(from: currentElement, primaryScreenHeight: primaryScreenHeight) else { break }
            candidatesFromHitUpward.append(candidate)

            var parentValue: CFTypeRef?
            guard AXUIElementCopyAttributeValue(currentElement, kAXParentAttribute as CFString, &parentValue) == .success,
                  let parentValue,
                  CFGetTypeID(parentValue) == AXUIElementGetTypeID() else { break }
            currentElement = parentValue as! AXUIElement
        }
        return candidatesFromHitUpward
    }

    private static func makeCandidate(from element: AXUIElement, primaryScreenHeight: CGFloat) -> AccessibilityElementCandidate? {
        guard let position = pointAttribute(kAXPositionAttribute, of: element),
              let size = sizeAttribute(kAXSizeAttribute, of: element) else { return nil }

        var roleValue: CFTypeRef?
        let role: String? = AXUIElementCopyAttributeValue(element, kAXRoleAttribute as CFString, &roleValue) == .success
            ? roleValue as? String
            : nil

        var processIdentifier: pid_t = 0
        AXUIElementGetPid(element, &processIdentifier)

        return AccessibilityElementCandidate(
            role: role,
            frameInAppKitGlobal: PointingGeometry.appKitGlobalRect(
                fromAccessibilityPosition: position,
                size: size,
                primaryScreenHeight: primaryScreenHeight
            ),
            processIdentifier: processIdentifier
        )
    }

    private static func pointAttribute(_ attributeName: String, of element: AXUIElement) -> CGPoint? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attributeName as CFString, &value) == .success,
              let value, CFGetTypeID(value) == AXValueGetTypeID() else { return nil }
        var point = CGPoint.zero
        return AXValueGetValue(value as! AXValue, .cgPoint, &point) ? point : nil
    }

    private static func sizeAttribute(_ attributeName: String, of element: AXUIElement) -> CGSize? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attributeName as CFString, &value) == .success,
              let value, CFGetTypeID(value) == AXValueGetTypeID() else { return nil }
        var size = CGSize.zero
        return AXValueGetValue(value as! AXValue, .cgSize, &size) ? size : nil
    }
}
