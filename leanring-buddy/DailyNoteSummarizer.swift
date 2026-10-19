//
//  DailyNoteSummarizer.swift
//  leanring-buddy
//
//  Prompts and output cleaning for the one-line daily-note summary that the
//  Ollama chat model (the one that just answered, already loaded) writes
//  after each exchange, which model that is, plus the raw fallback the app
//  writes itself for cloud chat providers or when the model fails.
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

    /// The Ollama model that writes the summary: the chat model itself when
    /// the chat provider is Ollama, so no extra model has to be loaded (Ollama
    /// keeps at most 3 resident and a fourth evicted embeddinggemma, adding
    /// ~0.8 s before every reply). Nil for cloud providers, and for a blank
    /// model name, meaning "write `rawFallbackSummary` instead": Lumen must not
    /// load a local model just for summaries. Takes a Bool rather than
    /// `ChatProviderKind` because that enum lives in AppSettings.swift, which
    /// the terminal test harness can't compile.
    static func summaryModelName(isChatProviderOllama: Bool, chatModelName: String) -> String? {
        guard isChatProviderOllama else { return nil }
        let trimmedChatModelName = chatModelName.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmedChatModelName.isEmpty ? nil : trimmedChatModelName
    }

    /// `question → first sentence of the reply`, or just the question when the
    /// reply is empty. Used when there is no summary model or it fails.
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
