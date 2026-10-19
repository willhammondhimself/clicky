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

nonisolated struct PointingRequestCounter {
    private var currentRequestNumber: Int?
    private var lastIssuedRequestNumber = 0

    mutating func beginRequest() -> Int {
        lastIssuedRequestNumber += 1
        currentRequestNumber = lastIssuedRequestNumber
        return lastIssuedRequestNumber
    }

    mutating func invalidateCurrentRequest() {
        currentRequestNumber = nil
    }

    func isCurrent(_ requestNumber: Int) -> Bool {
        currentRequestNumber == requestNumber
    }
}
