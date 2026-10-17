import Foundation
import Testing

#if canImport(leanring_buddy)
@testable import leanring_buddy
#else
@testable import ClickyLogic
#endif

struct DailyNoteEntryTests {

    private var utcCalendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }

    // 2026-10-17 09:15:00 UTC
    private let fixedDate = Date(timeIntervalSince1970: 1_792_228_500)

    @Test func formatAndParseRoundTrip() {
        let entry = DailyNoteEntry(time: "09:15", applicationName: "Final Cut Pro", summary: "asked how to color grade; told them to open the color inspector")
        let line = DailyNoteLineFormat.format(entry)
        #expect(line == "09:15 · Final Cut Pro · asked how to color grade; told them to open the color inspector")
        #expect(DailyNoteLineFormat.parse(line) == entry)
    }

    @Test func parseToleratesAHandWrittenBulletAndKeepsSeparatorsInsideTheSummary() {
        let parsed = DailyNoteLineFormat.parse("- 14:02 · Xcode · a · b")
        #expect(parsed == DailyNoteEntry(time: "14:02", applicationName: "Xcode", summary: "a · b"))
    }

    @Test func headerBlankAndMalformedLinesAreNotEntries() {
        #expect(DailyNoteLineFormat.parse("# 2026-10-17") == nil)
        #expect(DailyNoteLineFormat.parse("") == nil)
        #expect(DailyNoteLineFormat.parse("   ") == nil)
        #expect(DailyNoteLineFormat.parse("just some text") == nil)
        #expect(DailyNoteLineFormat.parse("09:15 · only two parts") == nil)
    }

    @Test func applicationNamesAreMadeSafeForTheLineGrammar() {
        #expect(DailyNoteLineFormat.sanitizedApplicationName("Xcode") == "Xcode")
        #expect(DailyNoteLineFormat.sanitizedApplicationName("") == "unknown app")
        #expect(DailyNoteLineFormat.sanitizedApplicationName("   ") == "unknown app")
        #expect(DailyNoteLineFormat.sanitizedApplicationName("Odd · Name\nHere") == "Odd - Name Here")
        let entry = DailyNoteEntry(time: "09:15", applicationName: DailyNoteLineFormat.sanitizedApplicationName("A · B"), summary: "x")
        #expect(DailyNoteLineFormat.parse(DailyNoteLineFormat.format(entry)) == entry)
    }

    @Test func headerAndTimeStringUseTheInjectedCalendar() {
        #expect(DailyNoteLineFormat.header(forDateString: "2026-10-17") == "# 2026-10-17")
        #expect(DailyNoteLineFormat.timeString(for: fixedDate, calendar: utcCalendar) == "09:15")
    }

    @Test func fileNamingUsesTheInjectedCalendar() {
        #expect(DailyNoteFileNaming.dateString(for: fixedDate, calendar: utcCalendar) == "2026-10-17")
        #expect(DailyNoteFileNaming.fileName(forDateString: "2026-10-17") == "2026-10-17.md")

        var tokyoCalendar = Calendar(identifier: .gregorian)
        tokyoCalendar.timeZone = TimeZone(identifier: "Asia/Tokyo")!
        // 09:15 UTC is 18:15 the same day in Tokyo; 20:00 UTC would be the next day.
        let lateDate = Date(timeIntervalSince1970: 1_792_228_500 + 11 * 3600)
        #expect(DailyNoteFileNaming.dateString(for: lateDate, calendar: tokyoCalendar) == "2026-10-18")
    }

    @Test func dateStringFromFileNameRejectsEverythingElse() {
        #expect(DailyNoteFileNaming.dateString(fromFileName: "2026-10-17.md") == "2026-10-17")
        #expect(DailyNoteFileNaming.dateString(fromFileName: "index.json") == nil)
        #expect(DailyNoteFileNaming.dateString(fromFileName: "2026-10-17.txt") == nil)
        #expect(DailyNoteFileNaming.dateString(fromFileName: "notes.md") == nil)
    }
}
