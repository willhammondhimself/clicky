//
//  ReplyDisplayMode.swift
//  leanring-buddy
//
//  Whether Lumen speaks its replies, shows them as text in a bubble beside
//  the companion (in the skin's font, like the "hey! i'm lumen" welcome), or
//  both. Chosen in the panel's Voice settings; voice + text by default.
//

import Foundation

nonisolated enum ReplyDisplayMode: String, CaseIterable, Identifiable {
    case voiceAndText
    case voiceOnly
    case textOnly

    static let defaultMode: ReplyDisplayMode = .voiceAndText

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .voiceAndText: return "Voice + text"
        case .voiceOnly: return "Voice only"
        case .textOnly: return "Text only"
        }
    }

    var speaksReply: Bool { self != .textOnly }
    var showsReplyText: Bool { self != .voiceOnly }
}

/// How fast the reply text appears and how long it stays.
nonisolated enum ReplyTextTiming {
    /// Faster than speech (about 15 characters a second), so the text runs a
    /// little ahead of the voice like a subtitle.
    static let revealCharactersPerSecond: Double = 40
    static let secondsShownAfterSpeechEnds: Double = 3

    static func revealedCharacterCount(secondsSinceShown: Double, totalCharacterCount: Int) -> Int {
        let revealedCharacterCount = Int(max(secondsSinceShown, 0) * revealCharactersPerSecond)
        return min(revealedCharacterCount, totalCharacterCount)
    }

    /// Text-only replies have no voice to time them by: about 15 characters a
    /// second of reading plus 2 s, kept between 3 s and 20 s.
    static func textOnlyHoldSeconds(characterCount: Int) -> Double {
        let readingSeconds = Double(characterCount) / 15 + 2
        return min(max(readingSeconds, 3), 20)
    }
}
