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
    /// Optional wake-word style prefix, then the remember keyword, then an
    /// optional "that"/"this" filler, then the fact. "to" is kept because
    /// "remember to ship friday" reads correctly as a fact.
    private static let rememberCommandRegex = try! NSRegularExpression(
        pattern: #"^\s*(?:(?:hey|ok|okay)?\s*clicky\s*[,:]?\s*)?remember\b\s*(?:(?:that|this)\b)?\s*[,:]?\s*(.*)$"#,
        options: [.caseInsensitive, .dotMatchesLineSeparators]
    )

    /// "remember that I use zed" → "I use zed"; nil when the transcript is
    /// not a remember command or nothing follows the command.
    static func rememberedFact(fromTranscript transcript: String) -> String? {
        let wholeRange = NSRange(transcript.startIndex..., in: transcript)
        guard let match = rememberCommandRegex.firstMatch(in: transcript, range: wholeRange),
              let factRange = Range(match.range(at: 1), in: transcript) else {
            return nil
        }

        var factText = transcript[factRange].trimmingCharacters(in: .whitespacesAndNewlines)
        while let lastCharacter = factText.last, ".!?".contains(lastCharacter) {
            factText.removeLast()
        }
        factText = factText.trimmingCharacters(in: .whitespacesAndNewlines)
        return factText.isEmpty ? nil : factText
    }
}
