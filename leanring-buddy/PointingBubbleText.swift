//
//  PointingBubbleText.swift
//  leanring-buddy
//
//  What the bubble next to a pointing mark says: the element's name from the
//  model's [POINT:x,y:label] tag when there is one, otherwise a short phrase.
//

import Foundation

nonisolated enum PointingBubbleText {
    static let fallbackPhrases = ["right here", "this one", "over here", "here it is"]

    static func bubbleText(elementLabel: String?, fallbackPhraseIndex: Int) -> String {
        let trimmedLabel = elementLabel?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !trimmedLabel.isEmpty && trimmedLabel.lowercased() != "none" {
            return trimmedLabel
        }
        let wrappedIndex = ((fallbackPhraseIndex % fallbackPhrases.count) + fallbackPhrases.count) % fallbackPhrases.count
        return fallbackPhrases[wrappedIndex]
    }
}
