//
//  ElementBoundsSelection.swift
//  leanring-buddy
//
//  Picks the rect a pointing mark is drawn around, from the Accessibility
//  element under the model's point and its ancestors. Rules:
//  - Lumen's own windows, whole windows/scroll areas/web areas and anything
//    covering more than a quarter of the display are misses.
//  - A tiny hit (a text run inside a button) walks up to the nearest ancestor
//    big enough to be a control, but never into a container; if none is found
//    the tiny element itself is used.
//  - A miss falls back to a small box centred on the point, so every skin
//    still draws its mark in the right place.
//  AccessibilityElementBoundsResolver gathers the candidates; this file only
//  decides, so it can be unit-tested.
//

import CoreGraphics

nonisolated struct AccessibilityElementCandidate: Equatable {
    let role: String?
    let frameInAppKitGlobal: CGRect
    let processIdentifier: Int32
}

nonisolated enum TargetRectSource: Equatable {
    case accessibilityElement
    case fallbackBox
}

nonisolated struct TargetRectResolution: Equatable {
    let rectInAppKitGlobal: CGRect
    let source: TargetRectSource
}

nonisolated enum ElementBoundsSelection {
    static let containerRoles: Set<String> = [
        "AXWindow", "AXScrollArea", "AXWebArea", "AXSplitGroup", "AXLayoutArea", "AXApplication", "AXBrowser",
    ]
    static let maximumAreaFractionOfDisplay: CGFloat = 0.25
    static let minimumElementWidth: CGFloat = 12
    static let minimumElementHeight: CGFloat = 10
    static let fallbackBoxSize = CGSize(width: 44, height: 28)

    static func resolve(
        candidatesFromHitUpward: [AccessibilityElementCandidate],
        appKitGlobalPoint: CGPoint,
        displayFrame: CGRect,
        ownProcessIdentifier: Int32
    ) -> TargetRectResolution {
        let fallback = fallbackResolution(appKitGlobalPoint: appKitGlobalPoint, displayFrame: displayFrame)

        guard let hitCandidate = candidatesFromHitUpward.first,
              hitCandidate.processIdentifier != ownProcessIdentifier,
              isUsable(hitCandidate, displayFrame: displayFrame) else {
            return fallback
        }

        var chosenCandidate = hitCandidate
        if !meetsMinimumSize(hitCandidate) {
            for ancestorCandidate in candidatesFromHitUpward.dropFirst() {
                guard isUsable(ancestorCandidate, displayFrame: displayFrame) else { break }
                chosenCandidate = ancestorCandidate
                if meetsMinimumSize(ancestorCandidate) { break }
            }
        }

        let clippedRect = chosenCandidate.frameInAppKitGlobal.intersection(displayFrame)
        guard !clippedRect.isNull, !clippedRect.isEmpty else { return fallback }
        return TargetRectResolution(rectInAppKitGlobal: clippedRect, source: .accessibilityElement)
    }

    private static func isUsable(_ candidate: AccessibilityElementCandidate, displayFrame: CGRect) -> Bool {
        if let role = candidate.role, containerRoles.contains(role) { return false }
        let frame = candidate.frameInAppKitGlobal
        if frame.isNull || frame.isEmpty { return false }
        let displayArea = displayFrame.width * displayFrame.height
        let candidateArea = frame.width * frame.height
        return candidateArea <= displayArea * maximumAreaFractionOfDisplay
    }

    private static func meetsMinimumSize(_ candidate: AccessibilityElementCandidate) -> Bool {
        candidate.frameInAppKitGlobal.width >= minimumElementWidth
            && candidate.frameInAppKitGlobal.height >= minimumElementHeight
    }

    private static func fallbackResolution(appKitGlobalPoint: CGPoint, displayFrame: CGRect) -> TargetRectResolution {
        let box = CGRect(
            x: appKitGlobalPoint.x - fallbackBoxSize.width / 2,
            y: appKitGlobalPoint.y - fallbackBoxSize.height / 2,
            width: fallbackBoxSize.width,
            height: fallbackBoxSize.height
        )
        let clippedBox = box.intersection(displayFrame)
        return TargetRectResolution(
            rectInAppKitGlobal: clippedBox.isNull ? box : clippedBox,
            source: .fallbackBox
        )
    }
}
