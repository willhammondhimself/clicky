//
//  ProfileMarkdownEditor.swift
//  leanring-buddy
//
//  Pure string edits on PROFILE.md: one fact per "- " bullet under a "## "
//  heading. Kept free of file I/O so the risky part — removing a line the
//  model asked to forget — is fully unit-tested. MemoryStore does the disk
//  reads and writes.
//

import Foundation

/// The headings Lumen knows. The model names one in its [REMEMBER] tag;
/// anything it invents lands in Notes so no fact is lost.
nonisolated enum ProfileSection: String, CaseIterable, Sendable {
    case aboutMe = "About me"
    case projects = "Projects"
    case tools = "Tools"
    case preferences = "Preferences"
    case notes = "Notes"

    var heading: String { "## " + rawValue }

    init(matchingHeading headingName: String) {
        self = ProfileSection.section(exactlyMatchingHeading: headingName) ?? .notes
    }

    static func isKnownHeadingName(_ headingName: String) -> Bool {
        section(exactlyMatchingHeading: headingName) != nil
    }

    private static func section(exactlyMatchingHeading headingName: String) -> ProfileSection? {
        let normalizedHeadingName = headingName.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return ProfileSection.allCases.first { $0.rawValue.lowercased() == normalizedHeadingName }
    }
}

nonisolated enum ProfileMarkdownEditor {
    private static let bulletPrefix = "- "
    private static let headingPrefix = "## "

    static func starterMarkdown() -> String {
        """
        <!-- lumen reads this file before every reply. one fact per line, as a "- " bullet under a heading. edit it freely; lumen adds lines when you say "remember that…" and removes them when you say "forget…". -->

        # Profile

        ## About me
        - Will Hammond, student at Pitzer College (Claremont); computer science, quant finance and physics
        - builds his own tools; wants a local-first, always-on JARVIS-style assistant (this app)

        ## Projects
        - Lumen: this macOS assistant (Swift/SwiftUI), meant as the final layer of his stack: sees what he's doing, gives contextual hints, runs locally in the background on very little inference
        - Market Population Dynamics: agent-based market simulation research (paused), advisor Alan Kahn
        - Haven: iOS care companion app for an elderly user and a caretaker
        - Lucid: lucid-dream training iOS app using Apple Watch / Oura sleep data
        - WHAM: AR glasses assistant
        - Summer 2027 quant internship tracker (Jane Street, Citadel, D.E. Shaw, Two Sigma…)
        - PHYS114 quantum mechanics coursework in Mathematica

        ## Tools
        - MacBook Pro M4 Pro, 48 GB, macOS 26; Xcode; Ollama with gemma4:26b; Claude Code; Obsidian; Mathematica
        - uses conventional commits and feature branches

        ## Preferences
        - likes short, casual, specific answers; dislikes robotic voices (uses the British male Kokoro voice)
        - cares about privacy and running things offline; cheap or free inference over frontier APIs

        ## Notes

        """
    }

    // MARK: - Editing

    /// Inserts `- factText` as the last bullet of `section`, creating the
    /// section at the end of the file when missing. A fact that already
    /// exists byte-for-byte anywhere in the file is not added again.
    static func appendingFact(_ factText: String, underSection section: ProfileSection, to markdown: String) -> String {
        let trimmedFactText = factText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedFactText.isEmpty, !factLines(in: markdown).contains(trimmedFactText) else {
            return markdown
        }
        let newBulletLine = bulletPrefix + trimmedFactText

        var lines = markdown.components(separatedBy: "\n")

        guard let headingIndex = lines.firstIndex(where: { $0.trimmingCharacters(in: .whitespaces) == section.heading }) else {
            // Missing section: append it after whatever is there, separated by one blank line.
            while let lastLine = lines.last, lastLine.trimmingCharacters(in: .whitespaces).isEmpty {
                lines.removeLast()
            }
            lines.append("")
            lines.append(section.heading)
            lines.append(newBulletLine)
            lines.append("")
            return lines.joined(separator: "\n")
        }

        // Insert after the section's last bullet, or right after the heading
        // when it has none. Stop at the next heading.
        var insertionIndex = headingIndex + 1
        var lineIndex = headingIndex + 1
        while lineIndex < lines.count, !lines[lineIndex].hasPrefix(headingPrefix) {
            if lines[lineIndex].hasPrefix(bulletPrefix) {
                insertionIndex = lineIndex + 1
            }
            lineIndex += 1
        }
        lines.insert(newBulletLine, at: insertionIndex)

        var result = lines.joined(separator: "\n")
        if !result.hasSuffix("\n") {
            result += "\n"
        }
        return result
    }

    /// Removes the bullet whose text equals `factText`. Only bullet lines can
    /// be removed; headings, the title and the comment never match. Nil when
    /// no such bullet exists.
    static func removingFactLine(_ factText: String, from markdown: String) -> String? {
        let targetLine = bulletPrefix + factText.trimmingCharacters(in: .whitespacesAndNewlines)
        var lines = markdown.components(separatedBy: "\n")
        guard let lineIndex = lines.firstIndex(where: { $0.trimmingCharacters(in: .whitespaces) == targetLine }) else {
            return nil
        }
        lines.remove(at: lineIndex)
        return lines.joined(separator: "\n")
    }

    // MARK: - Reading

    /// Bullet texts in file order, without the "- " prefix; empty bullets skipped.
    static func factLines(in markdown: String) -> [String] {
        markdown.components(separatedBy: "\n").compactMap { line in
            let trimmedLine = line.trimmingCharacters(in: .whitespaces)
            guard trimmedLine.hasPrefix(bulletPrefix) else { return nil }
            let factText = trimmedLine.dropFirst(bulletPrefix.count).trimmingCharacters(in: .whitespaces)
            return factText.isEmpty ? nil : factText
        }
    }

    static func factLineCount(in markdown: String) -> Int {
        factLines(in: markdown).count
    }

    /// What the model sees: the file without the HTML comment and without
    /// empty bullets, trimmed.
    static func textForPrompt(from markdown: String) -> String {
        let withoutComments = markdown.replacingOccurrences(
            of: #"<!--.*?-->"#,
            with: "",
            options: [.regularExpression]
        )
        let keptLines = withoutComments.components(separatedBy: "\n").filter { line in
            let trimmedLine = line.trimmingCharacters(in: .whitespaces)
            return trimmedLine != "-" && trimmedLine != "- "
        }
        return keptLines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
