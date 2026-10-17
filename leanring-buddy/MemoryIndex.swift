//
//  MemoryIndex.swift
//  leanring-buddy
//
//  The embedding index for daily-note entries (`notes/index.json`): Codable
//  document types, cosine search, and the staleness rules that decide which
//  note files and lines need (re-)embedding after hand edits. Pure; the
//  embeddings themselves come from Ollama via MemoryManager.
//

import Foundation

nonisolated struct IndexedNoteEntry: Codable, Equatable, Sendable {
    let lineText: String
    let embedding: [Float]
}

nonisolated struct IndexedNoteFile: Codable, Equatable, Sendable {
    let modifiedAtUnixSeconds: Double
    let entries: [IndexedNoteEntry]
}

nonisolated struct MemoryIndexDocument: Codable, Equatable, Sendable {
    static let currentSchemaVersion = 1

    var schemaVersion: Int
    var embeddingModel: String
    /// Keyed by note file name, e.g. "2026-10-17.md".
    var files: [String: IndexedNoteFile]

    static func empty(embeddingModel: String) -> MemoryIndexDocument {
        MemoryIndexDocument(schemaVersion: currentSchemaVersion, embeddingModel: embeddingModel, files: [:])
    }

    /// False when the vectors were made by another model or an older schema;
    /// the caller then rebuilds from scratch rather than mixing vector spaces.
    func isCompatible(withEmbeddingModel requiredEmbeddingModel: String) -> Bool {
        schemaVersion == Self.currentSchemaVersion && embeddingModel == requiredEmbeddingModel
    }
}

nonisolated struct MemoryIndexHit: Equatable, Sendable {
    let fileName: String
    let lineText: String
    let similarity: Float
}

nonisolated enum MemoryIndexSearch {
    /// 0 for mismatched lengths or a zero vector.
    static func cosineSimilarity(_ left: [Float], _ right: [Float]) -> Float {
        guard left.count == right.count, !left.isEmpty else { return 0 }
        var dotProduct: Float = 0
        var leftMagnitudeSquared: Float = 0
        var rightMagnitudeSquared: Float = 0
        for index in left.indices {
            dotProduct += left[index] * right[index]
            leftMagnitudeSquared += left[index] * left[index]
            rightMagnitudeSquared += right[index] * right[index]
        }
        guard leftMagnitudeSquared > 0, rightMagnitudeSquared > 0 else { return 0 }
        return dotProduct / (leftMagnitudeSquared.squareRoot() * rightMagnitudeSquared.squareRoot())
    }

    /// Best-matching entries across all indexed files except `excludingFileName`
    /// (today's note, which is injected whole), most similar first.
    static func topHits(
        for queryEmbedding: [Float],
        in document: MemoryIndexDocument,
        excludingFileName: String?,
        limit: Int,
        minimumSimilarity: Float
    ) -> [MemoryIndexHit] {
        var hits: [MemoryIndexHit] = []
        for (fileName, indexedFile) in document.files where fileName != excludingFileName {
            for entry in indexedFile.entries {
                let similarity = cosineSimilarity(queryEmbedding, entry.embedding)
                if similarity >= minimumSimilarity {
                    hits.append(MemoryIndexHit(fileName: fileName, lineText: entry.lineText, similarity: similarity))
                }
            }
        }
        hits.sort { lhs, rhs in
            if lhs.similarity != rhs.similarity { return lhs.similarity > rhs.similarity }
            if lhs.fileName != rhs.fileName { return lhs.fileName < rhs.fileName }
            return lhs.lineText < rhs.lineText
        }
        return Array(hits.prefix(max(0, limit)))
    }
}

nonisolated struct NoteFileOnDisk: Equatable, Sendable {
    let fileName: String
    let modifiedAtUnixSeconds: Double
}

nonisolated struct LineEmbeddingReuse: Equatable, Sendable {
    let reusableEmbeddingsByLineText: [String: [Float]]
    let lineTextsToEmbed: [String]
}

nonisolated enum MemoryIndexStaleness {
    /// Files on disk that are new or whose modification time differs from the
    /// index (hand edits), sorted by name.
    static func fileNamesNeedingReindex(document: MemoryIndexDocument, filesOnDisk: [NoteFileOnDisk]) -> [String] {
        filesOnDisk
            .filter { fileOnDisk in
                guard let indexedFile = document.files[fileOnDisk.fileName] else { return true }
                return indexedFile.modifiedAtUnixSeconds != fileOnDisk.modifiedAtUnixSeconds
            }
            .map(\.fileName)
            .sorted()
    }

    /// Indexed files that no longer exist on disk, sorted by name.
    static func fileNamesToRemove(document: MemoryIndexDocument, filesOnDisk: [NoteFileOnDisk]) -> [String] {
        let fileNamesOnDisk = Set(filesOnDisk.map(\.fileName))
        return document.files.keys.filter { !fileNamesOnDisk.contains($0) }.sorted()
    }

    /// Lines whose text is unchanged keep their vector; only the rest go to
    /// the embedding model.
    static func lineEmbeddingReuse(forLineTexts lineTexts: [String], previousFile: IndexedNoteFile?) -> LineEmbeddingReuse {
        var previousEmbeddingsByLineText: [String: [Float]] = [:]
        for entry in previousFile?.entries ?? [] {
            previousEmbeddingsByLineText[entry.lineText] = entry.embedding
        }

        var reusableEmbeddingsByLineText: [String: [Float]] = [:]
        var lineTextsToEmbed: [String] = []
        for lineText in lineTexts {
            if let previousEmbedding = previousEmbeddingsByLineText[lineText] {
                reusableEmbeddingsByLineText[lineText] = previousEmbedding
            } else {
                lineTextsToEmbed.append(lineText)
            }
        }
        return LineEmbeddingReuse(reusableEmbeddingsByLineText: reusableEmbeddingsByLineText, lineTextsToEmbed: lineTextsToEmbed)
    }
}
