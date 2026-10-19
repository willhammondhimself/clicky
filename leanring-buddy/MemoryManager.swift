//
//  MemoryManager.swift
//  leanring-buddy
//
//  The one object CompanionManager and the panel talk to for memory:
//
//    - prepareAtLaunch: create the folder + starter PROFILE.md, make sure the
//      two Ollama models are installed (pulling them if not).
//    - memoryPromptBlock(forQuestion:): the profile + relevant note entries
//      to append to the system prompt (retrieved by embedding similarity, or
//      the last two days whole when embeddings aren't available).
//    - applyMemoryTags: write [REMEMBER] facts to the profile, remove the
//      closest line for [FORGET], and say what happened.
//    - recordExchange: summarise the exchange into today's note and index it,
//      in the background.
//
//  Every error is caught and logged here; nothing may throw into the reply
//  pipeline. File I/O is in the MemoryStore actor; everything else pure.
//

import Combine
import Foundation

nonisolated struct MemoryWriteOutcome: Equatable, Sendable {
    /// Appended to the spoken reply (e.g. "forgot: uses vscode."), nil when
    /// there is nothing to say.
    let spokenConfirmation: String?
}

@MainActor
final class MemoryManager: ObservableObject {
    static let shared = MemoryManager()

    @Published private(set) var provisioningState: MemoryModelProvisioningState = .notChecked
    @Published private(set) var profileFactLineCount: Int = 0

    /// Shown by the panel's "Open memory folder" button.
    var memoryRootDirectoryURL: URL { memoryStore.rootDirectoryURL }

    var isMemoryEnabled: Bool { appSettings.isMemoryEnabled }

    // Retrieval tuning. Thresholds were calibrated against embeddinggemma on
    // 2026-10-17 with the task prefixes below: a note line that answers the
    // question scores ≈0.45–0.5, unrelated lines ≤0.2, off-topic questions
    // ≈0. For FORGET, an exact restatement scores ≈0.85, a paraphrase
    // ("the cat", "my editor") 0.45–0.6, and a fact that isn't there ≤0.25.
    static let retrievedEntryLimit = 8
    static let retrievedEntryMinimumSimilarity: Float = 0.3
    static let forgetMinimumSimilarity: Float = 0.4
    static let retrievalTimeoutSeconds: Double = 5
    /// EmbeddingGemma's recommended task prefixes; queries and documents are
    /// embedded differently. Without them the scores bunch together
    /// (unrelated lines reach 0.3+), so keep them.
    private static let queryEmbeddingPrefix = "task: search result | query: "
    private static let documentEmbeddingPrefix = "title: none | text: "

    private let appSettings: AppSettings
    private let memoryStore: MemoryStore
    private var modelProvisioner: MemoryModelProvisioner!
    private var indexDocument: MemoryIndexDocument?
    private var cancellables: Set<AnyCancellable> = []

    private var calendar: Calendar { Calendar.current }

    private convenience init() {
        self.init(appSettings: AppSettings.shared, memoryStore: MemoryStore(rootDirectoryURL: MemoryStore.defaultRootDirectoryURL))
    }

    init(appSettings: AppSettings, memoryStore: MemoryStore) {
        self.appSettings = appSettings
        self.memoryStore = memoryStore

        modelProvisioner = MemoryModelProvisioner(
            requiredModels: MemoryModelCatalog.requiredModels,
            listInstalledModels: { [weak self] in
                guard let self else { return [] }
                return try await self.makeNativeClient().listInstalledModelNames()
            },
            pullModel: { [weak self] modelName, onProgress in
                guard let self else { return }
                try await self.makeNativeClient().pullModel(named: modelName, onProgress: onProgress)
            }
        )
        modelProvisioner.$provisioningState
            .sink { [weak self] newState in self?.provisioningState = newState }
            .store(in: &cancellables)

        appSettings.$isMemoryEnabled
            .dropFirst()
            .removeDuplicates()
            .sink { [weak self] isEnabled in
                if isEnabled { self?.prepareAtLaunch() }
            }
            .store(in: &cancellables)
    }

    // MARK: - Launch

    /// Creates the memory folder and starter profile, then checks/pulls the
    /// Ollama models in the background. Safe to call again.
    func prepareAtLaunch() {
        guard isMemoryEnabled else { return }
        Task { [weak self] in
            guard let self else { return }
            do {
                let wroteStarterProfile = try await memoryStore.ensureStarterFilesExist(starterProfileMarkdown: ProfileMarkdownEditor.starterMarkdown())
                if wroteStarterProfile {
                    print("🧠 Memory: wrote starter PROFILE.md at \(memoryStore.profileFileURL.path)")
                }
                await refreshProfileFactLineCount()
            } catch {
                print("⚠️ Memory: couldn't create the memory folder: \(error)")
            }
            await modelProvisioner.prepareIfNeeded()
            if modelProvisioner.isReady {
                await refreshIndexIfStaleLogged()
            }
        }
    }

    func retryProvisioning() {
        Task { [weak self] in
            await self?.modelProvisioner.retry()
            if self?.modelProvisioner.isReady == true {
                await self?.refreshIndexIfStaleLogged()
            }
        }
    }

    // MARK: - Reading

    /// The block appended to the system prompt, or nil when memory is off or
    /// empty. Never takes longer than the retrieval timeout.
    func memoryPromptBlock(forQuestion question: String) async -> String? {
        guard isMemoryEnabled else { return nil }

        let todayDateString = DailyNoteFileNaming.dateString(for: Date(), calendar: calendar)
        let profileText: String
        let todayEntries: [DailyNoteEntry]
        do {
            try await memoryStore.ensureStarterFilesExist(starterProfileMarkdown: ProfileMarkdownEditor.starterMarkdown())
            profileText = ProfileMarkdownEditor.textForPrompt(from: try await memoryStore.readProfileMarkdown())
            todayEntries = try await memoryStore.readDailyNoteLines(forDateString: todayDateString).compactMap(DailyNoteLineFormat.parse)
        } catch {
            print("⚠️ Memory: couldn't read the memory folder: \(error)")
            return nil
        }

        var pastEntries: [DatedDailyNoteEntry] = []
        var mode: MemoryPromptBuilder.Mode = .lastTwoDaysFallback

        // Ollama may have come up since launch (launch-at-login); the
        // provisioner throttles this to one re-check per interval.
        if case .ollamaUnreachable = modelProvisioner.provisioningState {
            await modelProvisioner.prepareIfNeeded()
        }

        if modelProvisioner.isReady {
            do {
                pastEntries = try await withTimeout(seconds: Self.retrievalTimeoutSeconds) { [self] in
                    try await retrievedEntries(forQuestion: question, excludingFileName: DailyNoteFileNaming.fileName(forDateString: todayDateString))
                }
                mode = .retrieved
                print("🧠 Memory: \(pastEntries.count) retrieved note entries for the question")
            } catch {
                print("⚠️ Memory: retrieval failed, falling back to the last two days: \(error)")
            }
        }

        if mode == .lastTwoDaysFallback {
            pastEntries = await yesterdaysEntries(todayDateString: todayDateString)
        }

        let block = MemoryPromptBuilder.build(
            profileText: profileText,
            todayDateString: todayDateString,
            todayEntries: todayEntries,
            pastEntries: pastEntries,
            mode: mode
        )
        if let block {
            print("🧠 Memory block: \(block.count) chars (\(mode == .retrieved ? "retrieved" : "fallback"))")
        }
        return block
    }

    // MARK: - Writing

    /// Applies the tags the model emitted, plus the transcript fallback when
    /// it emitted no [REMEMBER] tag.
    func applyMemoryTags(_ parseResult: MemoryTagParseResult, transcript: String) async -> MemoryWriteOutcome {
        guard isMemoryEnabled else { return MemoryWriteOutcome(spokenConfirmation: nil) }

        for rememberedFact in parseResult.rememberedFacts {
            await appendFactToProfile(rememberedFact.factText, section: ProfileSection(matchingHeading: rememberedFact.sectionName))
        }
        if parseResult.rememberedFacts.isEmpty {
            await applyTranscriptFallbackIfNeeded(transcript)
        }

        var confirmations: [String] = []
        for forgetText in parseResult.forgetRequests {
            confirmations.append(await forgetProfileLine(matching: forgetText))
        }

        await refreshProfileFactLineCount()
        return MemoryWriteOutcome(spokenConfirmation: confirmations.isEmpty ? nil : confirmations.joined(separator: " "))
    }

    /// "remember that …" spoken at the start of the question goes to Notes.
    /// Called on its own when the chat provider failed so the fact survives.
    func applyTranscriptFallbackIfNeeded(_ transcript: String) async {
        guard isMemoryEnabled,
              let factText = MemoryTranscriptCommand.rememberedFact(fromTranscript: transcript) else { return }
        await appendFactToProfile(factText, section: .notes)
        await refreshProfileFactLineCount()
    }

    /// Writes one line to today's note (summarised by the small model when
    /// available, raw otherwise) and indexes it. Fire-and-forget.
    func recordExchange(question: String, spokenReply: String, frontmostApplicationName: String) {
        guard isMemoryEnabled else { return }
        let recordedAt = Date()
        Task(priority: .utility) { [weak self] in
            guard let self else { return }
            let summary = await self.summary(question: question, spokenReply: spokenReply, applicationName: frontmostApplicationName)
            let entry = DailyNoteEntry(
                time: DailyNoteLineFormat.timeString(for: recordedAt, calendar: self.calendar),
                applicationName: DailyNoteLineFormat.sanitizedApplicationName(frontmostApplicationName),
                summary: summary
            )
            let dateString = DailyNoteFileNaming.dateString(for: recordedAt, calendar: self.calendar)
            do {
                try await self.memoryStore.appendDailyNoteLine(DailyNoteLineFormat.format(entry), forDateString: dateString)
                print("🧠 Memory: logged \"\(summary)\"")
            } catch {
                print("⚠️ Memory: couldn't append to today's note: \(error)")
                return
            }
            if self.modelProvisioner.isReady {
                await self.refreshIndexIfStaleLogged()
            }
        }
    }

    /// Deletes today's note and its index entries. Panel "Forget today".
    func forgetToday() async {
        let todayDateString = DailyNoteFileNaming.dateString(for: Date(), calendar: calendar)
        do {
            let deleted = try await memoryStore.deleteDailyNote(forDateString: todayDateString)
            if deleted, var document = await loadIndexDocument() {
                document.files.removeValue(forKey: DailyNoteFileNaming.fileName(forDateString: todayDateString))
                try await saveIndexDocument(document)
            }
            print("🧠 Memory: forgot today (\(deleted ? "note deleted" : "nothing to delete"))")
        } catch {
            print("⚠️ Memory: couldn't delete today's note: \(error)")
        }
    }

    // MARK: - Private: profile

    private func appendFactToProfile(_ factText: String, section: ProfileSection) async {
        do {
            let profileMarkdown = try await memoryStore.readProfileMarkdown()
            let updatedMarkdown = ProfileMarkdownEditor.appendingFact(factText, underSection: section, to: profileMarkdown)
            guard updatedMarkdown != profileMarkdown else {
                print("🧠 Memory: already knew \"\(factText)\"")
                return
            }
            try await memoryStore.writeProfileMarkdown(updatedMarkdown)
            print("🧠 Memory: remembered \"\(factText)\" under \(section.rawValue)")
        } catch {
            print("⚠️ Memory: couldn't write the profile: \(error)")
        }
    }

    /// Removes the profile line most similar to `forgetText` and returns what
    /// Lumen should say about it.
    private func forgetProfileLine(matching forgetText: String) async -> String {
        do {
            let profileMarkdown = try await memoryStore.readProfileMarkdown()
            let factLines = ProfileMarkdownEditor.factLines(in: profileMarkdown)
            guard !factLines.isEmpty,
                  let matchedLine = await bestMatchingFactLine(for: forgetText, among: factLines),
                  let updatedMarkdown = ProfileMarkdownEditor.removingFactLine(matchedLine, from: profileMarkdown) else {
                return "i couldn't find that in my memory."
            }
            try await memoryStore.writeProfileMarkdown(updatedMarkdown)
            print("🧠 Memory: forgot \"\(matchedLine)\"")

            // Paper trail in today's note so a wrong match can be recovered by hand.
            let now = Date()
            let paperTrailEntry = DailyNoteEntry(
                time: DailyNoteLineFormat.timeString(for: now, calendar: calendar),
                applicationName: "Lumen",
                summary: "forgot: " + matchedLine.replacingOccurrences(of: "·", with: "-")
            )
            try? await memoryStore.appendDailyNoteLine(
                DailyNoteLineFormat.format(paperTrailEntry),
                forDateString: DailyNoteFileNaming.dateString(for: now, calendar: calendar)
            )
            return "forgot: \(matchedLine)."
        } catch {
            print("⚠️ Memory: couldn't update the profile for forget: \(error)")
            return "i couldn't update my memory."
        }
    }

    /// Embedding similarity when the model is available, case-insensitive
    /// substring containment otherwise. Bounded by the retrieval timeout
    /// because the caller is in the spoken-reply path.
    private func bestMatchingFactLine(for forgetText: String, among factLines: [String]) async -> String? {
        if modelProvisioner.isReady {
            do {
                let client = try makeNativeClient()
                let embeddings = try await withTimeout(seconds: Self.retrievalTimeoutSeconds) {
                    try await client.embed(
                        texts: [Self.queryEmbeddingPrefix + forgetText] + factLines.map { Self.documentEmbeddingPrefix + $0 },
                        model: MemoryModelCatalog.embeddingModel
                    )
                }
                guard embeddings.count == factLines.count + 1 else { return nil }
                let queryEmbedding = embeddings[0]
                var bestLine: String?
                var bestSimilarity: Float = Self.forgetMinimumSimilarity
                for (lineIndex, factLine) in factLines.enumerated() {
                    let similarity = MemoryIndexSearch.cosineSimilarity(queryEmbedding, embeddings[lineIndex + 1])
                    if similarity >= bestSimilarity {
                        bestSimilarity = similarity
                        bestLine = factLine
                    }
                }
                return bestLine
            } catch {
                print("⚠️ Memory: embedding for forget failed, using text match: \(error)")
            }
        }
        // Longest containing match wins so a short line ("ai") can't hijack
        // "forget the thing about my ai course".
        let loweredForgetText = forgetText.lowercased()
        return factLines
            .filter { factLine in
                let loweredFactLine = factLine.lowercased()
                return loweredFactLine.contains(loweredForgetText) || loweredForgetText.contains(loweredFactLine)
            }
            .max { $0.count < $1.count }
    }

    private func refreshProfileFactLineCount() async {
        if let profileMarkdown = try? await memoryStore.readProfileMarkdown() {
            profileFactLineCount = ProfileMarkdownEditor.factLineCount(in: profileMarkdown)
        }
    }

    // MARK: - Private: notes and retrieval

    private func summary(question: String, spokenReply: String, applicationName: String) async -> String {
        if modelProvisioner.isReady {
            do {
                let client = try makeNativeClient()
                let modelOutput = try await client.generate(
                    model: MemoryModelCatalog.summarizerModel,
                    systemPrompt: DailyNoteSummarizer.systemPrompt,
                    userPrompt: DailyNoteSummarizer.userPrompt(question: question, spokenReply: spokenReply, applicationName: applicationName)
                )
                if let sanitizedSummary = DailyNoteSummarizer.sanitizedSummary(fromModelOutput: modelOutput) {
                    return sanitizedSummary
                }
            } catch {
                print("⚠️ Memory: summariser failed, writing a raw entry: \(error)")
            }
        }
        return DailyNoteSummarizer.rawFallbackSummary(question: question, spokenReply: spokenReply)
    }

    private func retrievedEntries(forQuestion question: String, excludingFileName: String) async throws -> [DatedDailyNoteEntry] {
        let document = try await refreshIndexIfStale()
        guard !document.files.isEmpty else { return [] }

        let client = try makeNativeClient()
        let queryEmbeddings = try await client.embed(texts: [Self.queryEmbeddingPrefix + question], model: MemoryModelCatalog.embeddingModel)
        guard let queryEmbedding = queryEmbeddings.first else { return [] }

        let hits = MemoryIndexSearch.topHits(
            for: queryEmbedding,
            in: document,
            excludingFileName: excludingFileName,
            limit: Self.retrievedEntryLimit,
            minimumSimilarity: Self.retrievedEntryMinimumSimilarity
        )
        return hits.compactMap { hit in
            guard let dateString = DailyNoteFileNaming.dateString(fromFileName: hit.fileName),
                  let entry = DailyNoteLineFormat.parse(hit.lineText) else { return nil }
            return DatedDailyNoteEntry(dateString: dateString, entry: entry)
        }
    }

    private func yesterdaysEntries(todayDateString: String) async -> [DatedDailyNoteEntry] {
        guard let yesterday = calendar.date(byAdding: .day, value: -1, to: Date()) else { return [] }
        let yesterdayDateString = DailyNoteFileNaming.dateString(for: yesterday, calendar: calendar)
        let lines = (try? await memoryStore.readDailyNoteLines(forDateString: yesterdayDateString)) ?? []
        return lines.compactMap(DailyNoteLineFormat.parse).map { DatedDailyNoteEntry(dateString: yesterdayDateString, entry: $0) }
    }

    /// Brings the index in line with the note files on disk: drops deleted
    /// files, re-embeds new or hand-edited files (only their changed lines).
    private func refreshIndexIfStale() async throws -> MemoryIndexDocument {
        var document = await loadIndexDocument() ?? .empty(embeddingModel: MemoryModelCatalog.embeddingModel)
        let filesOnDisk = try await memoryStore.listDailyNoteFiles()

        let fileNamesToRemove = MemoryIndexStaleness.fileNamesToRemove(document: document, filesOnDisk: filesOnDisk)
        let fileNamesNeedingReindex = MemoryIndexStaleness.fileNamesNeedingReindex(document: document, filesOnDisk: filesOnDisk)
        guard !fileNamesToRemove.isEmpty || !fileNamesNeedingReindex.isEmpty else { return document }

        for fileName in fileNamesToRemove {
            document.files.removeValue(forKey: fileName)
        }

        let client = try makeNativeClient()
        for fileName in fileNamesNeedingReindex {
            guard let fileOnDisk = filesOnDisk.first(where: { $0.fileName == fileName }) else { continue }
            let lineTexts = try await memoryStore.readDailyNote(fileName: fileName)
                .components(separatedBy: "\n")
                .filter { DailyNoteLineFormat.parse($0) != nil }
                .map { $0.trimmingCharacters(in: .whitespaces) }

            let reuse = MemoryIndexStaleness.lineEmbeddingReuse(forLineTexts: lineTexts, previousFile: document.files[fileName])
            var embeddingsByLineText = reuse.reusableEmbeddingsByLineText
            if !reuse.lineTextsToEmbed.isEmpty {
                let newEmbeddings = try await client.embed(
                    texts: reuse.lineTextsToEmbed.map { Self.documentEmbeddingPrefix + $0 },
                    model: MemoryModelCatalog.embeddingModel
                )
                for (lineText, embedding) in zip(reuse.lineTextsToEmbed, newEmbeddings) {
                    embeddingsByLineText[lineText] = embedding
                }
            }
            let entries = lineTexts.compactMap { lineText in
                embeddingsByLineText[lineText].map { IndexedNoteEntry(lineText: lineText, embedding: $0) }
            }
            document.files[fileName] = IndexedNoteFile(modifiedAtUnixSeconds: fileOnDisk.modifiedAtUnixSeconds, entries: entries)
            print("🧠 Memory: indexed \(fileName) (\(reuse.lineTextsToEmbed.count) new line(s))")
            // Save per file: a long rebuild that hits the retrieval timeout
            // then keeps what it managed instead of starting over next time.
            try await saveIndexDocument(document)
        }

        try await saveIndexDocument(document)
        return document
    }

    private func refreshIndexIfStaleLogged() async {
        do {
            _ = try await refreshIndexIfStale()
        } catch {
            print("⚠️ Memory: index refresh failed: \(error)")
        }
    }

    private func loadIndexDocument() async -> MemoryIndexDocument? {
        if let indexDocument { return indexDocument }
        guard let storedDocument = await memoryStore.readIndexDocument(),
              storedDocument.isCompatible(withEmbeddingModel: MemoryModelCatalog.embeddingModel) else {
            return nil
        }
        indexDocument = storedDocument
        return storedDocument
    }

    private func saveIndexDocument(_ document: MemoryIndexDocument) async throws {
        indexDocument = document
        try await memoryStore.writeIndexDocument(document)
    }

    // MARK: - Private: Ollama

    struct OllamaURLError: LocalizedError {
        var errorDescription: String? { "the ollama base url in settings is not a valid url" }
    }

    /// Memory always talks to Ollama: the configured URL when Ollama is the
    /// chat provider, the default local one otherwise.
    private func makeNativeClient() throws -> OllamaNativeClient {
        let openAICompatibleBaseURL = appSettings.chatProviderKind == .ollama
            ? appSettings.chatBaseURL
            : ChatProviderKind.ollama.defaultBaseURL
        guard let nativeBaseURL = OllamaNativeEndpoints.nativeBaseURL(fromOpenAICompatibleBaseURL: openAICompatibleBaseURL) else {
            throw OllamaURLError()
        }
        return OllamaNativeClient(nativeBaseURL: nativeBaseURL)
    }
}

// MARK: - Timeout

private struct TimeoutError: LocalizedError {
    var errorDescription: String? { "timed out" }
}

/// Runs `operation` and throws `TimeoutError` if it hasn't finished in time.
private func withTimeout<Result: Sendable>(
    seconds: Double,
    operation: @escaping @MainActor () async throws -> Result
) async throws -> Result {
    try await withThrowingTaskGroup(of: Result.self) { group in
        group.addTask { try await operation() }
        group.addTask {
            try await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
            throw TimeoutError()
        }
        guard let firstResult = try await group.next() else { throw TimeoutError() }
        group.cancelAll()
        return firstResult
    }
}
