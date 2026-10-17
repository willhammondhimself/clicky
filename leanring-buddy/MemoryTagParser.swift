//
//  MemoryTagParser.swift
//  leanring-buddy
//
//  Pulls `[REMEMBER:Section:fact]` and `[FORGET:text]` tags out of a model
//  reply. Tags can appear anywhere in the text (the model is asked to put
//  them at the end, before the point tag, but models drift), in any case,
//  with stray spaces. Must run BEFORE CompanionManager.parsePointingCoordinates,
//  whose regex is anchored to the end of the text.
//

import Foundation

nonisolated struct RememberedFact: Equatable, Sendable {
    /// Heading name as the model wrote it, e.g. "Tools". Empty when the model
    /// omitted the section; ProfileSection maps unknown names to Notes.
    let sectionName: String
    let factText: String
}

nonisolated struct MemoryTagParseResult: Equatable, Sendable {
    let textWithoutMemoryTags: String
    let rememberedFacts: [RememberedFact]
    let forgetRequests: [String]
}

nonisolated enum MemoryTagParser {
    /// Matches `[` + optional spaces + REMEMBER|FORGET + optional spaces + `:` +
    /// everything up to the first `]` — or to the end of the text when the
    /// model never closed the bracket (so bracket text is never spoken).
    private static let memoryTagRegex = try! NSRegularExpression(
        pattern: #"\[\s*(remember|forget)\s*:([^\]]*)(?:\]|$)"#,
        options: [.caseInsensitive]
    )

    private static let repeatedSpacesRegex = try! NSRegularExpression(pattern: #"[ \t]{2,}"#)

    static func parse(_ replyText: String) -> MemoryTagParseResult {
        let wholeRange = NSRange(replyText.startIndex..., in: replyText)
        let matches = memoryTagRegex.matches(in: replyText, range: wholeRange)

        var rememberedFacts: [RememberedFact] = []
        var forgetRequests: [String] = []
        var textWithoutMemoryTags = replyText

        // Remove from the end backwards so earlier ranges stay valid.
        for match in matches.reversed() {
            guard let keywordRange = Range(match.range(at: 1), in: replyText),
                  let contentRange = Range(match.range(at: 2), in: replyText),
                  let tagRange = Range(match.range, in: replyText) else { continue }

            let keyword = replyText[keywordRange].lowercased()
            let content = String(replyText[contentRange])
            if keyword == "remember" {
                if let rememberedFact = rememberedFact(fromTagContent: content) {
                    rememberedFacts.insert(rememberedFact, at: 0)
                }
            } else {
                let forgetText = content.trimmingCharacters(in: .whitespacesAndNewlines)
                if !forgetText.isEmpty {
                    forgetRequests.insert(forgetText, at: 0)
                }
            }
            textWithoutMemoryTags.removeSubrange(tagRange)
        }

        return MemoryTagParseResult(
            textWithoutMemoryTags: collapsingLeftoverSpaces(textWithoutMemoryTags),
            rememberedFacts: rememberedFacts,
            forgetRequests: forgetRequests
        )
    }

    /// "Tools:uses zed" → (Tools, uses zed); "likes tea" → ("", likes tea).
    /// Only the first colon separates the section, so facts keep their own
    /// colons ("meeting at 10:30").
    private static func rememberedFact(fromTagContent tagContent: String) -> RememberedFact? {
        let sectionName: String
        let factText: String
        if let firstColonIndex = tagContent.firstIndex(of: ":") {
            sectionName = String(tagContent[..<firstColonIndex])
            factText = String(tagContent[tagContent.index(after: firstColonIndex)...])
        } else {
            sectionName = ""
            factText = tagContent
        }
        let trimmedFactText = factText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedFactText.isEmpty else { return nil }
        return RememberedFact(
            sectionName: sectionName.trimmingCharacters(in: .whitespacesAndNewlines),
            factText: trimmedFactText
        )
    }

    private static func collapsingLeftoverSpaces(_ text: String) -> String {
        let wholeRange = NSRange(text.startIndex..., in: text)
        let collapsed = repeatedSpacesRegex.stringByReplacingMatches(in: text, range: wholeRange, withTemplate: " ")
        return collapsed.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
