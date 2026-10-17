import Foundation
import Testing

#if canImport(leanring_buddy)
@testable import leanring_buddy
#else
@testable import ClickyLogic
#endif

struct MemoryStoreTests {

    private func makeStore() -> MemoryStore {
        let rootDirectoryURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("clicky-memory-tests-\(UUID().uuidString)", isDirectory: true)
        return MemoryStore(rootDirectoryURL: rootDirectoryURL)
    }

    @Test func starterFilesAreCreatedOnceAndNeverOverwritten() async throws {
        let store = makeStore()
        let createdFirstTime = try await store.ensureStarterFilesExist(starterProfileMarkdown: "# starter\n")
        #expect(createdFirstTime)
        #expect(try await store.readProfileMarkdown() == "# starter\n")

        try await store.writeProfileMarkdown("# edited\n")
        let createdSecondTime = try await store.ensureStarterFilesExist(starterProfileMarkdown: "# starter\n")
        #expect(!createdSecondTime)
        #expect(try await store.readProfileMarkdown() == "# edited\n")

        var isDirectory: ObjCBool = false
        let notesDirectoryExists = FileManager.default.fileExists(atPath: store.notesDirectoryURL.path, isDirectory: &isDirectory)
        #expect(notesDirectoryExists && isDirectory.boolValue)
    }

    @Test func appendingCreatesTheHeaderThenAppendsLines() async throws {
        let store = makeStore()
        _ = try await store.ensureStarterFilesExist(starterProfileMarkdown: "")
        try await store.appendDailyNoteLine("09:15 · Safari · first", forDateString: "2026-10-17")
        try await store.appendDailyNoteLine("10:00 · Xcode · second", forDateString: "2026-10-17")

        let noteText = try await store.readDailyNote(fileName: "2026-10-17.md")
        #expect(noteText == "# 2026-10-17\n\n09:15 · Safari · first\n10:00 · Xcode · second\n")
        #expect(try await store.readDailyNoteLines(forDateString: "2026-10-17") == ["# 2026-10-17", "", "09:15 · Safari · first", "10:00 · Xcode · second"])
        #expect(try await store.readDailyNoteLines(forDateString: "2026-01-01") == [])
    }

    @Test func listingIgnoresTheIndexAndStrayFiles() async throws {
        let store = makeStore()
        _ = try await store.ensureStarterFilesExist(starterProfileMarkdown: "")
        try await store.appendDailyNoteLine("09:15 · Safari · a", forDateString: "2026-10-16")
        try await store.appendDailyNoteLine("09:15 · Safari · b", forDateString: "2026-10-17")
        try await store.writeIndexDocument(.empty(embeddingModel: "embeddinggemma"))
        try "x".write(to: store.notesDirectoryURL.appendingPathComponent("scratch.txt"), atomically: true, encoding: .utf8)

        let listedFiles = try await store.listDailyNoteFiles()
        #expect(listedFiles.map(\.fileName) == ["2026-10-16.md", "2026-10-17.md"])
        #expect(listedFiles.allSatisfy { $0.modifiedAtUnixSeconds > 0 })
    }

    @Test func deletingTodayRemovesOnlyThatFile() async throws {
        let store = makeStore()
        _ = try await store.ensureStarterFilesExist(starterProfileMarkdown: "")
        try await store.appendDailyNoteLine("09:15 · Safari · a", forDateString: "2026-10-16")
        try await store.appendDailyNoteLine("09:15 · Safari · b", forDateString: "2026-10-17")

        #expect(try await store.deleteDailyNote(forDateString: "2026-10-17"))
        #expect(try await store.listDailyNoteFiles().map(\.fileName) == ["2026-10-16.md"])
        #expect(try await store.deleteDailyNote(forDateString: "2026-10-17") == false)
    }

    @Test func indexDocumentRoundTripsAndMissingIndexIsNil() async throws {
        let store = makeStore()
        _ = try await store.ensureStarterFilesExist(starterProfileMarkdown: "")
        #expect(await store.readIndexDocument() == nil)

        var document = MemoryIndexDocument.empty(embeddingModel: "embeddinggemma")
        document.files["2026-10-17.md"] = IndexedNoteFile(modifiedAtUnixSeconds: 1, entries: [IndexedNoteEntry(lineText: "a", embedding: [0.5])])
        try await store.writeIndexDocument(document)
        #expect(await store.readIndexDocument() == document)

        try "{not json".write(to: store.indexFileURL, atomically: true, encoding: .utf8)
        #expect(await store.readIndexDocument() == nil)
    }
}
