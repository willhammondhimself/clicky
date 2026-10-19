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
//  timers never stall; the whole lookup is capped at 400 ms. Lumen already holds the Accessibility permission (the
//  push-to-talk shortcut needs it), so this asks for nothing new.
//

import AppKit
import ApplicationServices

nonisolated enum AccessibilityElementBoundsResolver {
    private static let messagingTimeoutSeconds: Float = 0.15
    private static let maximumAncestorCount = 6
    /// Cap on the whole lookup (window list, hit test and ancestor walk), so a
    /// slow app delays the spoken reply by at most this much.
    private static let maximumLookupDuration: Duration = .milliseconds(400)
    /// The labelled-element search runs while the reply is already being
    /// spoken, so it gets a longer budget of its own.
    private static let maximumLabelSearchDuration: Duration = .milliseconds(1000)
    /// Roles whose outline the mark should hug when the matched name is a
    /// text run inside them.
    private static let controlRoles: Set<String> = [
        "AXButton", "AXLink", "AXMenuItem", "AXMenuBarItem", "AXMenuButton", "AXCheckBox",
        "AXRadioButton", "AXPopUpButton", "AXTab", "AXCell", "AXTextField", "AXComboBox",
    ]

    @MainActor
    static func resolveTargetRect(
        atAppKitGlobalPoint appKitGlobalPoint: CGPoint,
        displayFrame: CGRect,
        pointingLabel: String?
    ) async -> TargetRectResolution {
        // NSScreen is main-actor only, so read the primary display here. The
        // primary display is the one whose frame starts at the global origin.
        let primaryScreenHeight = NSScreen.screens.first(where: { $0.frame.origin == .zero })?.frame.height
            ?? NSScreen.screens.first?.frame.height
            ?? displayFrame.height
        let ownProcessIdentifier = getpid()

        let collectedCandidates = await Task.detached(priority: .userInitiated) {
            collectCandidates(
                atAppKitGlobalPoint: appKitGlobalPoint,
                primaryScreenHeight: primaryScreenHeight,
                ownProcessIdentifier: ownProcessIdentifier,
                displayFrame: displayFrame,
                pointingLabel: pointingLabel
            )
        }.value

        // A nearby element named like the model's label beats whatever sits
        // exactly under the point: the point is often a few points off.
        if let namedElement = NamedElementSnap.chooseElement(
            pointingLabel: pointingLabel,
            candidates: collectedCandidates.labelledCandidatesNearby
        ) {
            let clippedRect = namedElement.frameInAppKitGlobal.intersection(displayFrame)
            if !clippedRect.isNull, !clippedRect.isEmpty {
                return TargetRectResolution(rectInAppKitGlobal: clippedRect, source: .labelledElementNearby)
            }
        }

        let candidatesFromHitUpward = collectedCandidates.candidatesFromHitUpward
        return ElementBoundsSelection.resolve(
            candidatesFromHitUpward: candidatesFromHitUpward,
            appKitGlobalPoint: appKitGlobalPoint,
            displayFrame: displayFrame,
            ownProcessIdentifier: ownProcessIdentifier
        )
    }

    /// The element under the point followed by up to `maximumAncestorCount`
    /// parents. The hit test runs against the app that owns the topmost
    /// window under the point (never Lumen's own overlay, which covers every
    /// screen). Any Accessibility error ends the walk; an error on the hit
    /// itself returns an empty list, which ElementBoundsSelection treats as a
    /// miss. The whole lookup stops at `maximumLookupDuration`.
    private struct CollectedCandidates {
        var candidatesFromHitUpward: [AccessibilityElementCandidate] = []
        var labelledCandidatesNearby: [LabeledElementCandidate] = []
    }

    private static func collectCandidates(
        atAppKitGlobalPoint appKitGlobalPoint: CGPoint,
        primaryScreenHeight: CGFloat,
        ownProcessIdentifier: Int32,
        displayFrame: CGRect,
        pointingLabel: String?
    ) -> CollectedCandidates {
        let clock = ContinuousClock()
        let deadline = clock.now + maximumLookupDuration
        let accessibilityPoint = PointingGeometry.accessibilityPoint(
            fromAppKitGlobalPoint: appKitGlobalPoint,
            primaryScreenHeight: primaryScreenHeight
        )

        guard let targetProcessIdentifier = WindowUnderPointSelection.processIdentifierOfTopmostWindow(
            atAccessibilityPoint: accessibilityPoint,
            windowsFrontToBack: onScreenWindowsFrontToBack(),
            ownProcessIdentifier: ownProcessIdentifier
        ) else { return CollectedCandidates() }

        // Setting the timeout on the system-wide element applies it to every
        // element queried below; set it on the app element too to be explicit.
        AXUIElementSetMessagingTimeout(AXUIElementCreateSystemWide(), messagingTimeoutSeconds)
        let applicationElement = AXUIElementCreateApplication(targetProcessIdentifier)
        AXUIElementSetMessagingTimeout(applicationElement, messagingTimeoutSeconds)

        var hitElement: AXUIElement?
        let hitResult = AXUIElementCopyElementAtPosition(
            applicationElement,
            Float(accessibilityPoint.x),
            Float(accessibilityPoint.y),
            &hitElement
        )
        guard hitResult == .success, var currentElement = hitElement else { return CollectedCandidates() }

        var candidatesFromHitUpward: [AccessibilityElementCandidate] = []
        for _ in 0...maximumAncestorCount {
            guard clock.now < deadline,
                  let candidate = makeCandidate(from: currentElement, primaryScreenHeight: primaryScreenHeight) else { break }
            candidatesFromHitUpward.append(candidate)

            var parentValue: CFTypeRef?
            guard AXUIElementCopyAttributeValue(currentElement, kAXParentAttribute as CFString, &parentValue) == .success,
                  let parentValue,
                  CFGetTypeID(parentValue) == AXUIElementGetTypeID() else { break }
            currentElement = parentValue as! AXUIElement
        }

        var collectedCandidates = CollectedCandidates(candidatesFromHitUpward: candidatesFromHitUpward)
        if let pointingLabel, !pointingLabel.isEmpty {
            collectedCandidates.labelledCandidatesNearby = collectLabelledCandidatesNearby(
                applicationElement: applicationElement,
                accessibilityPoint: accessibilityPoint,
                appKitGlobalPoint: appKitGlobalPoint,
                primaryScreenHeight: primaryScreenHeight,
                displayFrame: displayFrame,
                ownProcessIdentifier: ownProcessIdentifier,
                deadline: ContinuousClock.now + maximumLabelSearchDuration
            )
        }
        return collectedCandidates
    }

    /// Named elements around the point, for NamedElementSnap: hit-tests a
    /// 9×9 grid (every 20 points, out to 80) and walks up to two parents from each hit.
    /// A text run inside a control (the "Resign" text in a button) is reported
    /// with the control's frame, so the mark hugs the whole button.
    private static func collectLabelledCandidatesNearby(
        applicationElement: AXUIElement,
        accessibilityPoint: CGPoint,
        appKitGlobalPoint: CGPoint,
        primaryScreenHeight: CGFloat,
        displayFrame: CGRect,
        ownProcessIdentifier: Int32,
        deadline: ContinuousClock.Instant
    ) -> [LabeledElementCandidate] {
        var labelledCandidates: [LabeledElementCandidate] = []
        var seenFrameKeys: Set<String> = []

        for samplePoint in NamedElementSnap.samplePoints(around: accessibilityPoint) {
            guard ContinuousClock.now < deadline else { break }
            var sampleHitElement: AXUIElement?
            guard AXUIElementCopyElementAtPosition(applicationElement, Float(samplePoint.x), Float(samplePoint.y), &sampleHitElement) == .success,
                  var currentElement = sampleHitElement else { continue }

            for _ in 0..<3 {
                guard ContinuousClock.now < deadline,
                      let candidate = makeCandidate(from: currentElement, primaryScreenHeight: primaryScreenHeight) else { break }
                let parentElement = parent(of: currentElement)

                if candidate.processIdentifier != ownProcessIdentifier,
                   ElementBoundsSelection.isUsable(candidate, displayFrame: displayFrame),
                   let elementLabel = label(of: currentElement) {
                    var frameForMark = candidate.frameInAppKitGlobal
                    if candidate.role == "AXStaticText",
                       let parentElement,
                       let parentCandidate = makeCandidate(from: parentElement, primaryScreenHeight: primaryScreenHeight),
                       let parentRole = parentCandidate.role,
                       controlRoles.contains(parentRole),
                       ElementBoundsSelection.isUsable(parentCandidate, displayFrame: displayFrame) {
                        frameForMark = parentCandidate.frameInAppKitGlobal
                    }
                    let frameKey = "\(frameForMark)|\(elementLabel)"
                    if !seenFrameKeys.contains(frameKey) {
                        seenFrameKeys.insert(frameKey)
                        labelledCandidates.append(LabeledElementCandidate(
                            label: elementLabel,
                            frameInAppKitGlobal: frameForMark,
                            distanceFromPoint: NamedElementSnap.distance(from: appKitGlobalPoint, to: frameForMark)
                        ))
                    }
                }

                guard let parentElement else { break }
                currentElement = parentElement
            }
        }
        return labelledCandidates
    }

    private static func parent(of element: AXUIElement) -> AXUIElement? {
        var parentValue: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXParentAttribute as CFString, &parentValue) == .success,
              let parentValue,
              CFGetTypeID(parentValue) == AXUIElementGetTypeID() else { return nil }
        return (parentValue as! AXUIElement)
    }

    /// The element's visible name: its title, else its description, else its
    /// text value. Nil when it has none.
    private static func label(of element: AXUIElement) -> String? {
        for attributeName in [kAXTitleAttribute, kAXDescriptionAttribute, kAXValueAttribute] {
            var attributeValue: CFTypeRef?
            guard AXUIElementCopyAttributeValue(element, attributeName as CFString, &attributeValue) == .success,
                  let text = attributeValue as? String else { continue }
            let trimmedText = text.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmedText.isEmpty && trimmedText.count <= 120 {
                return trimmedText
            }
        }
        return nil
    }

    /// On-screen windows, front to back, from the window server. Owner pid and
    /// bounds are readable without Screen Recording permission.
    private static func onScreenWindowsFrontToBack() -> [OnScreenWindowInfo] {
        guard let windowDictionaries = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as? [[String: Any]] else {
            return []
        }
        return windowDictionaries.compactMap { windowDictionary in
            guard let ownerProcessIdentifier = windowDictionary[kCGWindowOwnerPID as String] as? Int32,
                  let boundsDictionary = windowDictionary[kCGWindowBounds as String] as? NSDictionary,
                  let windowBounds = CGRect(dictionaryRepresentation: boundsDictionary as CFDictionary) else { return nil }
            let windowAlpha = windowDictionary[kCGWindowAlpha as String] as? Double ?? 1
            return OnScreenWindowInfo(
                processIdentifier: ownerProcessIdentifier,
                boundsInAccessibilitySpace: windowBounds,
                alpha: windowAlpha
            )
        }
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
