//
//  MemoryTranscriptCommand.swift
//  leanring-buddy
//
//  Detects "remember that …" spoken at the start of a question so the fact
//  is saved even when the model forgets to emit a [REMEMBER] tag. The
//  model's own tag wins when present (MemoryManager only uses this as a
//  fallback); the text is stored verbatim under the Notes section.
//

import Foundation

nonisolated enum MemoryTranscriptCommand {
    /// Optional wake-word style prefix, then "remember that/this/to". Bare
    /// "remember …" is deliberately not a command: it is usually a question
    /// ("remember what I was doing?") and would be stored as a fact. "to" is
    /// kept in the fact because "remember to ship friday" reads correctly.
    private static let rememberCommandRegex = try! NSRegularExpression(
        pattern: #"^\s*(?:(?:hey|ok|okay)?\s*lumen\s*[,:]?\s*)?remember\s+(?:(?:that|this)\b\s*[,:]?\s*(.*)|(to\b.*))$"#,
        options: [.caseInsensitive, .dotMatchesLineSeparators]
    )

    /// "remember that I use zed" → "I use zed"; nil when the transcript is
    /// not a remember command, is a question, or nothing follows the command.
    static func rememberedFact(fromTranscript transcript: String) -> String? {
        let trimmedTranscript = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedTranscript.hasSuffix("?") else { return nil }

        let wholeRange = NSRange(transcript.startIndex..., in: transcript)
        guard let match = rememberCommandRegex.firstMatch(in: transcript, range: wholeRange) else {
            return nil
        }
        let factRange = Range(match.range(at: 1), in: transcript) ?? Range(match.range(at: 2), in: transcript)
        guard let factRange else { return nil }

        var factText = transcript[factRange].trimmingCharacters(in: .whitespacesAndNewlines)
        while let lastCharacter = factText.last, ".!?".contains(lastCharacter) {
            factText.removeLast()
        }
        factText = factText.trimmingCharacters(in: .whitespacesAndNewlines)
        return factText.isEmpty ? nil : factText
    }
}
