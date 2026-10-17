import Foundation
import Testing

#if canImport(leanring_buddy)
@testable import leanring_buddy
#else
@testable import ClickyLogic
#endif

struct MemoryPromptBuilderTests {

    private let profileText = "# Profile\n\n## Tools\n- uses xcode"
    private let todayEntries = [
        DailyNoteEntry(time: "09:15", applicationName: "Safari", summary: "asked about color grading"),
        DailyNoteEntry(time: "14:02", applicationName: "Xcode", summary: "swift concurrency error"),
    ]
    private let pastEntries = [
        DatedDailyNoteEntry(dateString: "2026-10-16", entry: DailyNoteEntry(time: "16:00", applicationName: "Xcode", summary: "ollama bug")),
        DatedDailyNoteEntry(dateString: "2026-10-15", entry: DailyNoteEntry(time: "11:30", applicationName: "Mail", summary: "internship email")),
        DatedDailyNoteEntry(dateString: "2026-10-16", entry: DailyNoteEntry(time: "08:00", applicationName: "Finder", summary: "moved files")),
    ]

    @Test func underTheCapEverythingAppearsOldestFirst() throws {
        let block = try #require(MemoryPromptBuilder.build(
            profileText: profileText,
            todayDateString: "2026-10-17",
            todayEntries: todayEntries,
            pastEntries: pastEntries,
            mode: .retrieved
        ))
        let expected = """
        what you know about the user:
        # Profile

        ## Tools
        - uses xcode

        recent notes (oldest first; today's are complete, earlier ones were picked for this question):
        2026-10-15 11:30 · Mail · internship email
        2026-10-16 08:00 · Finder · moved files
        2026-10-16 16:00 · Xcode · ollama bug
        2026-10-17 09:15 · Safari · asked about color grading
        2026-10-17 14:02 · Xcode · swift concurrency error
        """
        #expect(block == expected)
    }

    @Test func fallbackModeUsesItsOwnHeader() throws {
        let block = try #require(MemoryPromptBuilder.build(
            profileText: profileText,
            todayDateString: "2026-10-17",
            todayEntries: [],
            pastEntries: pastEntries,
            mode: .lastTwoDaysFallback
        ))
        #expect(block.contains("recent notes (today and yesterday):"))
        #expect(!block.contains("picked for this question"))
    }

    @Test func overTheCapPastEntriesAreDroppedOldestFirstThenTodaysOldest() {
        let fullBlock = MemoryPromptBuilder.build(
            profileText: profileText,
            todayDateString: "2026-10-17",
            todayEntries: todayEntries,
            pastEntries: pastEntries,
            mode: .retrieved
        )!
        let cap = fullBlock.count - 10
        let trimmedBlock = MemoryPromptBuilder.build(
            profileText: profileText,
            todayDateString: "2026-10-17",
            todayEntries: todayEntries,
            pastEntries: pastEntries,
            mode: .retrieved,
            maximumCharacterCount: cap
        )!
        #expect(trimmedBlock.count <= cap)
        #expect(!trimmedBlock.contains("internship email"))
        #expect(trimmedBlock.contains("swift concurrency error"))

        let tinyCap = profileText.count + 120
        let tinyBlock = MemoryPromptBuilder.build(
            profileText: profileText,
            todayDateString: "2026-10-17",
            todayEntries: todayEntries,
            pastEntries: pastEntries,
            mode: .retrieved,
            maximumCharacterCount: tinyCap
        )!
        #expect(tinyBlock.count <= tinyCap)
        #expect(tinyBlock.contains("uses xcode"))
        #expect(!tinyBlock.contains("asked about color grading"))
    }

    @Test func aProfileAloneOverTheCapIsTruncatedWithAMarker() {
        let longProfile = String(repeating: "- fact line\n", count: 100)
        let block = MemoryPromptBuilder.build(
            profileText: longProfile,
            todayDateString: "2026-10-17",
            todayEntries: [],
            pastEntries: [],
            mode: .retrieved,
            maximumCharacterCount: 300
        )!
        #expect(block.count <= 300)
        #expect(block.hasSuffix(MemoryPromptBuilder.truncationMarker))
        #expect(block.hasPrefix("what you know about the user:\n- fact line"))
    }

    @Test func nothingToSayYieldsNil() {
        #expect(MemoryPromptBuilder.build(profileText: "  ", todayDateString: "2026-10-17", todayEntries: [], pastEntries: [], mode: .retrieved) == nil)
    }

    @Test func notesWithoutAProfileStillBuild() throws {
        let block = try #require(MemoryPromptBuilder.build(profileText: "", todayDateString: "2026-10-17", todayEntries: todayEntries, pastEntries: [], mode: .retrieved))
        #expect(block.hasPrefix("recent notes"))
    }
}
