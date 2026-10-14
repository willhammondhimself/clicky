//
//  SentenceSplitter.swift
//  leanring-buddy
//
//  Splits a spoken reply into sentence-sized chunks for the Kokoro TTS
//  client. Kokoro's fast vocoder path covers up to five seconds of audio per
//  call, and synthesizing sentence by sentence lets playback start after the
//  first ~80 ms instead of after the whole reply. Pure and nonisolated so it
//  can be unit-tested from the terminal harness.
//

import Foundation

nonisolated enum SentenceSplitter {
    /// Pieces shorter than this are merged into a neighbour so "ok." does not
    /// become its own synthesis call.
    static let minimumChunkCharacterCount = 20

    /// Pieces longer than this are split at the last comma before the limit
    /// so each chunk stays within roughly five seconds of speech.
    static let maximumChunkCharacterCount = 300

    static func split(_ text: String) -> [String] {
        let trimmedText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedText.isEmpty else { return [] }

        let sentencePieces = splitOnSentenceBoundaries(trimmedText)
        let mergedPieces = mergeShortPieces(sentencePieces)
        return mergedPieces.flatMap(splitOverlongPiece)
    }

    // MARK: - Sentence boundaries

    private static func isSentenceTerminator(_ character: Character) -> Bool {
        character == "." || character == "?" || character == "!" || character == "…"
    }

    /// Quote and bracket characters that may trail a sentence terminator and
    /// should stay attached to the sentence they close.
    private static func isClosingPunctuation(_ character: Character) -> Bool {
        "\"'”’)]".contains(character)
    }

    /// Splits on newlines, and on runs of `. ? ! …` (plus any closing quotes)
    /// that are followed by whitespace or the end of the text. A terminator
    /// followed directly by a non-space character ("3.5", "e.g.x") does not
    /// split, which keeps decimals intact.
    private static func splitOnSentenceBoundaries(_ text: String) -> [String] {
        let characters = Array(text)
        var pieces: [String] = []
        var currentPiece = ""
        var index = 0

        while index < characters.count {
            let character = characters[index]

            if character == "\n" {
                pieces.append(currentPiece)
                currentPiece = ""
                index += 1
                continue
            }

            currentPiece.append(character)

            guard isSentenceTerminator(character) else {
                index += 1
                continue
            }

            // Absorb the rest of the terminator run ("...", "?!") and any
            // closing quotes so they end up in this piece.
            var lookaheadIndex = index + 1
            while lookaheadIndex < characters.count,
                  isSentenceTerminator(characters[lookaheadIndex]) || isClosingPunctuation(characters[lookaheadIndex]) {
                currentPiece.append(characters[lookaheadIndex])
                lookaheadIndex += 1
            }

            let reachedEndOfText = lookaheadIndex >= characters.count
            let nextCharacterIsWhitespace = !reachedEndOfText && characters[lookaheadIndex].isWhitespace
            if reachedEndOfText || nextCharacterIsWhitespace {
                pieces.append(currentPiece)
                currentPiece = ""
            }
            index = lookaheadIndex
        }

        pieces.append(currentPiece)

        return pieces
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    // MARK: - Short pieces

    /// Carries pieces shorter than `minimumChunkCharacterCount` forward into
    /// the next piece. A short piece at the very end is appended to the
    /// previous one.
    private static func mergeShortPieces(_ pieces: [String]) -> [String] {
        var mergedPieces: [String] = []
        var pendingShortPrefix = ""

        for piece in pieces {
            let candidate = pendingShortPrefix.isEmpty ? piece : pendingShortPrefix + " " + piece
            if candidate.count < minimumChunkCharacterCount {
                pendingShortPrefix = candidate
            } else {
                mergedPieces.append(candidate)
                pendingShortPrefix = ""
            }
        }

        if !pendingShortPrefix.isEmpty {
            if mergedPieces.isEmpty {
                mergedPieces.append(pendingShortPrefix)
            } else {
                mergedPieces[mergedPieces.count - 1] += " " + pendingShortPrefix
            }
        }

        return mergedPieces
    }

    // MARK: - Overlong pieces

    /// Splits at the last comma before `maximumChunkCharacterCount`. A piece
    /// with no comma in range is left whole; the Kokoro library still chunks
    /// anything over 510 phonemes on its own.
    private static func splitOverlongPiece(_ piece: String) -> [String] {
        guard piece.count > maximumChunkCharacterCount else { return [piece] }

        let characters = Array(piece)
        let searchRange = 0..<maximumChunkCharacterCount
        guard let lastCommaIndex = searchRange.reversed().first(where: { characters[$0] == "," }) else {
            return [piece]
        }

        let headPiece = String(characters[...lastCommaIndex]).trimmingCharacters(in: .whitespaces)
        let tailPiece = String(characters[(lastCommaIndex + 1)...]).trimmingCharacters(in: .whitespaces)

        var result = [headPiece]
        if !tailPiece.isEmpty {
            result.append(contentsOf: splitOverlongPiece(tailPiece))
        }
        return result
    }
}
