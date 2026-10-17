//
//  DailyNoteSummarizer.swift
//  leanring-buddy
//
//  Prompts and output cleaning for the one-line daily-note summary that a
//  small Ollama model (gemma4:e2b) writes after each exchange, plus the raw
//  fallback the app writes itself when that model is unavailable.
//

import Foundation

nonisolated enum DailyNoteSummarizer {
    static let maximumSummaryLength = 160

    static let systemPrompt = """
    you write one short line for a personal daily log. given what the user asked their desktop assistant, which app they were in, and what the assistant answered, reply with a single lowercase sentence (at most 20 words) that says what the user was doing or asking and the gist of the answer. no preamble, no quotes, no bullet, no markdown, nothing else.
    """

    static func userPrompt(question: String, spokenReply: String, applicationName: String) -> String {
        """
        app: \(applicationName)
        user asked: \(question)
        assistant answered: \(spokenReply)
        """
    }

    /// First non-empty line of the model output with list markers, quotes, a
    /// "Summary:" label, leftover memory tags and the note separator removed,
    /// capped at `maximumSummaryLength`. Nil when nothing usable is left.
    static func sanitizedSummary(fromModelOutput modelOutput: String) -> String? {
        guard let firstLine = modelOutput
            .components(separatedBy: .newlines)
            .map({ $0.trimmingCharacters(in: .whitespaces) })
            .first(where: { !$0.isEmpty }) else {
            return nil
        }

        var summary = firstLine
        summary = summary.replacingOccurrences(of: #"\[[^\]]*\]"#, with: "", options: .regularExpression)
        summary = summary.replacingOccurrences(of: #"^(?:[-*•]\s*)+"#, with: "", options: .regularExpression)
        summary = summary.replacingOccurrences(of: #"^(?:summary|log|note)\s*:\s*"#, with: "", options: [.regularExpression, .caseInsensitive])
        summary = summary.trimmingCharacters(in: CharacterSet(charactersIn: "\"'“”‘’ "))
        summary = separatorFree(summary)
        summary = summary.replacingOccurrences(of: #"\s{2,}"#, with: " ", options: .regularExpression)
        summary = summary.trimmingCharacters(in: .whitespaces)

        guard !summary.isEmpty else { return nil }
        if summary.count > maximumSummaryLength {
            summary = String(summary.prefix(maximumSummaryLength))
        }
        return summary
    }

    /// `question → first sentence of the reply`, or just the question when the
    /// reply is empty. Used when the summariser model is unavailable.
    static func rawFallbackSummary(question: String, spokenReply: String) -> String {
        let cleanedQuestion = separatorFree(question).trimmingCharacters(in: .whitespacesAndNewlines)
        let firstSentence = firstSentence(of: spokenReply)
        guard !firstSentence.isEmpty else { return cleanedQuestion }
        return cleanedQuestion + " → " + separatorFree(firstSentence)
    }

    /// Up to and including the first sentence-ending punctuation that is
    /// followed by whitespace (or the whole text). Deliberately not
    /// SentenceSplitter, which merges short sentences for speech pacing.
    private static func firstSentence(of text: String) -> String {
        let trimmedText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let wholeRange = NSRange(trimmedText.startIndex..., in: trimmedText)
        let sentenceEndRegex = try! NSRegularExpression(pattern: #"[.!?](?=\s)"#)
        guard let match = sentenceEndRegex.firstMatch(in: trimmedText, range: wholeRange),
              let endRange = Range(match.range, in: trimmedText) else {
            return trimmedText
        }
        return String(trimmedText[..<endRange.upperBound])
    }

    /// Daily-note lines are split on " · " and newlines, so neither may appear
    /// inside a summary.
    private static func separatorFree(_ text: String) -> String {
        text.replacingOccurrences(of: "·", with: "-")
            .replacingOccurrences(of: #"[\r\n]+"#, with: " ", options: .regularExpression)
    }
}
