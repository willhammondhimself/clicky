//
//  MemoryPromptBuilder.swift
//  leanring-buddy
//
//  Builds the dynamic memory block appended to the system prompt: the
//  profile, then the selected note entries oldest first. Enforces a
//  character cap so a long notes history can never crowd out the screenshot
//  and the question. Drop order when over the cap: past entries oldest
//  first, then today's oldest first, then the tail of the profile.
//

import Foundation

nonisolated enum MemoryPromptBuilder {
    enum Mode: Sendable {
        /// Past entries were chosen by embedding similarity to the question.
        case retrieved
        /// Embeddings unavailable: past entries are simply yesterday's.
        case lastTwoDaysFallback
    }

    /// ≈2,000 tokens.
    static let maximumCharacterCount = 8_000
    static let truncationMarker = "\n… (profile truncated)"

    private static let profileHeader = "what you know about the user:"
    private static let retrievedNotesHeader = "recent notes (oldest first; today's are complete, earlier ones were picked for this question):"
    private static let fallbackNotesHeader = "recent notes (today and yesterday):"

    static func build(
        profileText: String,
        todayDateString: String,
        todayEntries: [DailyNoteEntry],
        pastEntries: [DatedDailyNoteEntry],
        mode: Mode,
        maximumCharacterCount: Int = MemoryPromptBuilder.maximumCharacterCount
    ) -> String? {
        let trimmedProfileText = profileText.trimmingCharacters(in: .whitespacesAndNewlines)

        var pastNoteLines = pastEntries
            .sorted { lhs, rhs in
                if lhs.dateString != rhs.dateString { return lhs.dateString < rhs.dateString }
                return lhs.entry.time < rhs.entry.time
            }
            .map { noteLine(dateString: $0.dateString, entry: $0.entry) }
        var todayNoteLines = todayEntries
            .sorted { $0.time < $1.time }
            .map { noteLine(dateString: todayDateString, entry: $0) }

        guard !trimmedProfileText.isEmpty || !pastNoteLines.isEmpty || !todayNoteLines.isEmpty else {
            return nil
        }

        let notesHeader = mode == .retrieved ? retrievedNotesHeader : fallbackNotesHeader

        func assemble(profile: String) -> String {
            var sections: [String] = []
            if !profile.isEmpty {
                sections.append(profileHeader + "\n" + profile)
            }
            let noteLines = pastNoteLines + todayNoteLines
            if !noteLines.isEmpty {
                sections.append(notesHeader + "\n" + noteLines.joined(separator: "\n"))
            }
            return sections.joined(separator: "\n\n")
        }

        var block = assemble(profile: trimmedProfileText)
        while block.count > maximumCharacterCount, !pastNoteLines.isEmpty {
            pastNoteLines.removeFirst()
            block = assemble(profile: trimmedProfileText)
        }
        while block.count > maximumCharacterCount, !todayNoteLines.isEmpty {
            todayNoteLines.removeFirst()
            block = assemble(profile: trimmedProfileText)
        }
        if block.count > maximumCharacterCount {
            // Only the profile is left and it alone is over the cap.
            let availableProfileLength = max(0, maximumCharacterCount - profileHeader.count - 1 - truncationMarker.count)
            let truncatedProfile = String(trimmedProfileText.prefix(availableProfileLength)) + truncationMarker
            block = assemble(profile: truncatedProfile)
        }
        return block
    }

    private static func noteLine(dateString: String, entry: DailyNoteEntry) -> String {
        dateString + " " + DailyNoteLineFormat.format(entry)
    }
}
