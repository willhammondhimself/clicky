//
//  DailyNoteEntry.swift
//  leanring-buddy
//
//  One line of a daily note (`notes/YYYY-MM-DD.md`):
//
//      14:02 · Xcode · hit a swift concurrency error; suggested nonisolated
//
//  Pure formatting, parsing and file naming. Dates are passed around as
//  "YYYY-MM-DD" strings because that is both the file name and the sort key.
//

import Foundation

nonisolated struct DailyNoteEntry: Equatable, Sendable {
    /// "HH:MM", local time.
    let time: String
    let applicationName: String
    let summary: String
}

/// An entry together with the day it belongs to, for prompt building.
nonisolated struct DatedDailyNoteEntry: Equatable, Sendable {
    let dateString: String
    let entry: DailyNoteEntry
}

nonisolated enum DailyNoteLineFormat {
    /// U+00B7 middle dot with single spaces; summaries never contain it
    /// (DailyNoteSummarizer replaces it) so the first two separators are
    /// unambiguous.
    static let separator = " · "

    private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "HH:mm"
        return formatter
    }()

    static func format(_ entry: DailyNoteEntry) -> String {
        [entry.time, entry.applicationName, entry.summary].joined(separator: separator)
    }

    /// Nil for the `# date` header, blank lines and anything else that is not
    /// `time · app · summary`. A leading "- " (hand-written bullet) is accepted.
    static func parse(_ line: String) -> DailyNoteEntry? {
        var trimmedLine = line.trimmingCharacters(in: .whitespaces)
        if trimmedLine.hasPrefix("- ") {
            trimmedLine.removeFirst(2)
        }
        let parts = trimmedLine.components(separatedBy: separator)
        guard parts.count >= 3 else { return nil }
        let time = parts[0]
        let applicationName = parts[1]
        let summary = parts[2...].joined(separator: separator)
        guard time.count == 5, time[time.index(time.startIndex, offsetBy: 2)] == ":",
              !applicationName.isEmpty, !summary.isEmpty else {
            return nil
        }
        return DailyNoteEntry(time: time, applicationName: applicationName, summary: summary)
    }

    /// App names come from `NSWorkspace`; make sure one can never break the
    /// line grammar (separator or newline inside, or empty).
    static func sanitizedApplicationName(_ applicationName: String) -> String {
        let cleaned = applicationName
            .replacingOccurrences(of: "·", with: "-")
            .replacingOccurrences(of: #"[\r\n]+"#, with: " ", options: .regularExpression)
            .replacingOccurrences(of: #"\s{2,}"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return cleaned.isEmpty ? "unknown app" : cleaned
    }

    static func header(forDateString dateString: String) -> String {
        "# " + dateString
    }

    static func timeString(for date: Date, calendar: Calendar) -> String {
        let formatter = timeFormatter.copy() as! DateFormatter
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        return formatter.string(from: date)
    }
}

nonisolated enum DailyNoteFileNaming {
    private static let fileNameRegex = try! NSRegularExpression(pattern: #"^(\d{4}-\d{2}-\d{2})\.md$"#)

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()

    static func dateString(for date: Date, calendar: Calendar) -> String {
        let formatter = dateFormatter.copy() as! DateFormatter
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        return formatter.string(from: date)
    }

    static func fileName(forDateString dateString: String) -> String {
        dateString + ".md"
    }

    /// "2026-10-17.md" → "2026-10-17"; nil for index.json and anything else.
    static func dateString(fromFileName fileName: String) -> String? {
        let wholeRange = NSRange(fileName.startIndex..., in: fileName)
        guard let match = fileNameRegex.firstMatch(in: fileName, range: wholeRange),
              let dateRange = Range(match.range(at: 1), in: fileName) else {
            return nil
        }
        return String(fileName[dateRange])
    }
}
