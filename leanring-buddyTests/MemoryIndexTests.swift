import Foundation
import Testing

#if canImport(leanring_buddy)
@testable import leanring_buddy
#else
@testable import LumenLogic
#endif

struct MemoryIndexTests {

    private func makeDocument() -> MemoryIndexDocument {
        var document = MemoryIndexDocument.empty(embeddingModel: "embeddinggemma")
        document.files["2026-10-15.md"] = IndexedNoteFile(modifiedAtUnixSeconds: 100, entries: [
            IndexedNoteEntry(lineText: "10:00 · Xcode · swift error", embedding: [1, 0, 0]),
            IndexedNoteEntry(lineText: "11:00 · Safari · cat videos", embedding: [0, 1, 0]),
        ])
        document.files["2026-10-16.md"] = IndexedNoteFile(modifiedAtUnixSeconds: 200, entries: [
            IndexedNoteEntry(lineText: "09:00 · Xcode · swift concurrency", embedding: [0.9, 0.1, 0]),
        ])
        document.files["2026-10-17.md"] = IndexedNoteFile(modifiedAtUnixSeconds: 300, entries: [
            IndexedNoteEntry(lineText: "08:00 · Xcode · today's swift thing", embedding: [1, 0, 0]),
        ])
        return document
    }

    // MARK: - Cosine

    @Test func cosineSimilarityBasics() {
        #expect(abs(MemoryIndexSearch.cosineSimilarity([1, 2, 3], [1, 2, 3]) - 1) < 0.0001)
        #expect(MemoryIndexSearch.cosineSimilarity([1, 0], [0, 1]) == 0)
        #expect(MemoryIndexSearch.cosineSimilarity([0, 0], [1, 1]) == 0)
        #expect(MemoryIndexSearch.cosineSimilarity([1, 0], [1]) == 0)
    }

    // MARK: - Search

    @Test func topHitsAreSortedFilteredLimitedAndExcludeToday() {
        let hits = MemoryIndexSearch.topHits(
            for: [1, 0, 0],
            in: makeDocument(),
            excludingFileName: "2026-10-17.md",
            limit: 8,
            minimumSimilarity: 0.5
        )
        #expect(hits.map(\.lineText) == ["10:00 · Xcode · swift error", "09:00 · Xcode · swift concurrency"])
        #expect(hits.map(\.fileName) == ["2026-10-15.md", "2026-10-16.md"])
        #expect(hits.first?.similarity == 1)

        let limitedHits = MemoryIndexSearch.topHits(for: [1, 0, 0], in: makeDocument(), excludingFileName: nil, limit: 1, minimumSimilarity: 0)
        #expect(limitedHits.count == 1)

        let noHits = MemoryIndexSearch.topHits(for: [0, 0, 1], in: makeDocument(), excludingFileName: nil, limit: 8, minimumSimilarity: 0.5)
        #expect(noHits.isEmpty)
    }

    // MARK: - Staleness

    @Test func reportsChangedNewAndRemovedFiles() {
        let filesOnDisk = [
            NoteFileOnDisk(fileName: "2026-10-15.md", modifiedAtUnixSeconds: 100),   // unchanged
            NoteFileOnDisk(fileName: "2026-10-16.md", modifiedAtUnixSeconds: 250),   // edited
            NoteFileOnDisk(fileName: "2026-10-18.md", modifiedAtUnixSeconds: 400),   // new
        ]
        #expect(MemoryIndexStaleness.fileNamesNeedingReindex(document: makeDocument(), filesOnDisk: filesOnDisk) == ["2026-10-16.md", "2026-10-18.md"])
        #expect(MemoryIndexStaleness.fileNamesToRemove(document: makeDocument(), filesOnDisk: filesOnDisk) == ["2026-10-17.md"])
    }

    @Test func reusesEmbeddingsForUnchangedLines() {
        let previousFile = makeDocument().files["2026-10-15.md"]
        let reuse = MemoryIndexStaleness.lineEmbeddingReuse(
            forLineTexts: ["10:00 · Xcode · swift error", "12:00 · Mail · new line"],
            previousFile: previousFile
        )
        #expect(reuse.reusableEmbeddingsByLineText == ["10:00 · Xcode · swift error": [1, 0, 0]])
        #expect(reuse.lineTextsToEmbed == ["12:00 · Mail · new line"])

        let reuseWithoutPrevious = MemoryIndexStaleness.lineEmbeddingReuse(forLineTexts: ["a"], previousFile: nil)
        #expect(reuseWithoutPrevious.lineTextsToEmbed == ["a"])
    }

    // MARK: - Document

    @Test func codableRoundTripAndCompatibility() throws {
        let document = makeDocument()
        let data = try JSONEncoder().encode(document)
        let decoded = try JSONDecoder().decode(MemoryIndexDocument.self, from: data)
        #expect(decoded == document)
        #expect(document.isCompatible(withEmbeddingModel: "embeddinggemma"))
        #expect(!document.isCompatible(withEmbeddingModel: "nomic-embed-text"))

        var oldSchema = document
        oldSchema.schemaVersion = 0
        #expect(!oldSchema.isCompatible(withEmbeddingModel: "embeddinggemma"))
    }
}
