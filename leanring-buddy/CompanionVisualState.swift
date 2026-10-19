//
//  CompanionVisualState.swift
//  leanring-buddy
//
//  Which animation the on-screen companion shows. Pointing is not a state of
//  its own: the skin's mark is drawn around the target separately, and the
//  parked companion keeps showing thinking or speaking while it points.
//

import Foundation

nonisolated enum CompanionVisualState: Equatable {
    case idle
    case listening
    case thinking
    case speaking
    case flying

    /// Precedence: flying > listening > thinking > speaking > idle.
    static func resolve(
        isListening: Bool,
        isProcessing: Bool,
        isResponding: Bool,
        isFlyingToOrFromTarget: Bool
    ) -> CompanionVisualState {
        if isFlyingToOrFromTarget { return .flying }
        if isListening { return .listening }
        if isProcessing { return .thinking }
        if isResponding { return .speaking }
        return .idle
    }
}
