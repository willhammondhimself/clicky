//
//  PointingRequestCounter.swift
//  leanring-buddy
//
//  Speech starts before the Accessibility lookup for the exact element
//  finishes, so the lookup's result arrives later and may belong to a pointing
//  that is already over (the companion flew back, or the user pressed
//  push-to-talk again). Each pointing takes a number; a late result is applied
//  only while its number is still the current one.
//
//  One pointing can get two rects: the lookup at the chat model's point and,
//  with precise pointing, the lookup at the grounding model's point. They can
//  finish in either order (a slow app delays the first), so a rect from the
//  less accurate source never replaces one from the more accurate source.
//

nonisolated enum PointingTargetRectSource: Int, Comparable {
    case lookupAtChatModelPoint
    case lookupAtGroundedPoint

    static func < (lhs: PointingTargetRectSource, rhs: PointingTargetRectSource) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

nonisolated struct PointingRequestCounter {
    private var currentRequestNumber: Int?
    private var lastIssuedRequestNumber = 0
    /// The most accurate source whose rect was applied to the current request.
    private var mostAccurateAppliedSource: PointingTargetRectSource?

    mutating func beginRequest() -> Int {
        lastIssuedRequestNumber += 1
        currentRequestNumber = lastIssuedRequestNumber
        mostAccurateAppliedSource = nil
        return lastIssuedRequestNumber
    }

    mutating func invalidateCurrentRequest() {
        currentRequestNumber = nil
        mostAccurateAppliedSource = nil
    }

    func isCurrent(_ requestNumber: Int) -> Bool {
        currentRequestNumber == requestNumber
    }

    /// True (and recorded) when a rect from `source` may be applied now: its
    /// request is still current and no more accurate source has applied one.
    mutating func claimTargetRect(forRequest requestNumber: Int, from source: PointingTargetRectSource) -> Bool {
        guard isCurrent(requestNumber) else { return false }
        if let mostAccurateAppliedSource, source < mostAccurateAppliedSource {
            return false
        }
        mostAccurateAppliedSource = source
        return true
    }
}
