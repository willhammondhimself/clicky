//
//  MemoryStore.swift
//  leanring-buddy
//
//  All file I/O for the memory folder:
//
//      ~/Library/Application Support/Clicky/Memory/
//        PROFILE.md
//        notes/YYYY-MM-DD.md
//        notes/index.json
//
//  An actor so reads and writes happen off the main actor and serialise
//  with each other. The root directory is injected so tests use a temp dir.
//  Nothing here knows Markdown or embeddings; see ProfileMarkdownEditor,
//  DailyNoteEntry and MemoryIndex for the pure logic.
//

import Foundation

actor MemoryStore {
    static let defaultRootDirectoryURL: URL = FileManager.default
        .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("Clicky/Memory", isDirectory: true)

    static let indexFileName = "index.json"

    nonisolated let rootDirectoryURL: URL
    nonisolated let profileFileURL: URL
    nonisolated let notesDirectoryURL: URL
    nonisolated let indexFileURL: URL

    private let fileManager = FileManager.default

    init(rootDirectoryURL: URL) {
        self.rootDirectoryURL = rootDirectoryURL
        profileFileURL = rootDirectoryURL.appendingPathComponent("PROFILE.md")
        notesDirectoryURL = rootDirectoryURL.appendingPathComponent("notes", isDirectory: true)
        indexFileURL = notesDirectoryURL.appendingPathComponent(Self.indexFileName)
    }

    // MARK: - Setup

    /// Creates the folders and, only when missing, the profile. Returns true
    /// when the profile was written this call.
    @discardableResult
    func ensureStarterFilesExist(starterProfileMarkdown: String) throws -> Bool {
        try fileManager.createDirectory(at: notesDirectoryURL, withIntermediateDirectories: true)
        guard !fileManager.fileExists(atPath: profileFileURL.path) else { return false }
        try starterProfileMarkdown.write(to: profileFileURL, atomically: true, encoding: .utf8)
        return true
    }

    // MARK: - Profile

    func readProfileMarkdown() throws -> String {
        try String(contentsOf: profileFileURL, encoding: .utf8)
    }

    func writeProfileMarkdown(_ profileMarkdown: String) throws {
        try profileMarkdown.write(to: profileFileURL, atomically: true, encoding: .utf8)
    }

    // MARK: - Daily notes

    func appendDailyNoteLine(_ line: String, forDateString dateString: String) throws {
        let noteFileURL = dailyNoteURL(forDateString: dateString)
        if !fileManager.fileExists(atPath: noteFileURL.path) {
            let header = DailyNoteLineFormat.header(forDateString: dateString) + "\n\n"
            try header.write(to: noteFileURL, atomically: true, encoding: .utf8)
        }
        let fileHandle = try FileHandle(forWritingTo: noteFileURL)
        defer { try? fileHandle.close() }
        try fileHandle.seekToEnd()
        try fileHandle.write(contentsOf: Data((line + "\n").utf8))
    }

    /// Raw lines including the header; empty when the file doesn't exist.
    func readDailyNoteLines(forDateString dateString: String) throws -> [String] {
        let noteFileURL = dailyNoteURL(forDateString: dateString)
        guard fileManager.fileExists(atPath: noteFileURL.path) else { return [] }
        return try readDailyNote(fileName: noteFileURL.lastPathComponent).lines
    }

    func readDailyNote(fileName: String) throws -> String {
        try String(contentsOf: notesDirectoryURL.appendingPathComponent(fileName), encoding: .utf8)
    }

    /// Only `YYYY-MM-DD.md` files, sorted by name (which is date order).
    func listDailyNoteFiles() throws -> [NoteFileOnDisk] {
        guard fileManager.fileExists(atPath: notesDirectoryURL.path) else { return [] }
        let fileURLs = try fileManager.contentsOfDirectory(
            at: notesDirectoryURL,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles]
        )
        return try fileURLs
            .filter { DailyNoteFileNaming.dateString(fromFileName: $0.lastPathComponent) != nil }
            .map { fileURL in
                let modificationDate = try fileURL.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate ?? Date(timeIntervalSince1970: 0)
                return NoteFileOnDisk(fileName: fileURL.lastPathComponent, modifiedAtUnixSeconds: modificationDate.timeIntervalSince1970)
            }
            .sorted { $0.fileName < $1.fileName }
    }

    /// Returns false when there was nothing to delete.
    @discardableResult
    func deleteDailyNote(forDateString dateString: String) throws -> Bool {
        let noteFileURL = dailyNoteURL(forDateString: dateString)
        guard fileManager.fileExists(atPath: noteFileURL.path) else { return false }
        try fileManager.removeItem(at: noteFileURL)
        return true
    }

    // MARK: - Index

    /// Nil when there is no index yet or it cannot be decoded (then it is
    /// simply rebuilt).
    func readIndexDocument() -> MemoryIndexDocument? {
        guard let indexData = try? Data(contentsOf: indexFileURL) else { return nil }
        return try? JSONDecoder().decode(MemoryIndexDocument.self, from: indexData)
    }

    func writeIndexDocument(_ document: MemoryIndexDocument) throws {
        try fileManager.createDirectory(at: notesDirectoryURL, withIntermediateDirectories: true)
        let indexData = try JSONEncoder().encode(document)
        try indexData.write(to: indexFileURL, options: .atomic)
    }

    // MARK: - Private

    private func dailyNoteURL(forDateString dateString: String) -> URL {
        notesDirectoryURL.appendingPathComponent(DailyNoteFileNaming.fileName(forDateString: dateString))
    }
}

private extension String {
    /// Split on newlines, dropping the empty element a trailing newline makes.
    var lines: [String] {
        var lines = components(separatedBy: "\n")
        if lines.last == "" {
            lines.removeLast()
        }
        return lines
    }
}
