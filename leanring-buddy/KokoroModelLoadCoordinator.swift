//
//  KokoroModelLoadCoordinator.swift
//  leanring-buddy
//
//  Serialises model loading so that however many callers ask at once (the
//  factory's warm-up at launch, a settings change, the first reply), the
//  load operation runs once per voice and everyone waits on the same
//  result. Kept free of FluidAudio so it can be unit-tested; the engine
//  supplies the actual load operation.
//
//  Failure rules: a failed load stays failed for the voice that failed
//  (nothing retries on its own), but asking for a different voice tries
//  again, and `retryLoad` tries the same voice again. "Unavailable" (this
//  macOS build) never loads.
//

import Combine
import Foundation

@MainActor
final class KokoroModelLoadCoordinator: ObservableObject {
    typealias LoadOperation = @MainActor (_ voice: String) async throws -> Void

    @Published private(set) var loadState: KokoroModelLoadState

    /// Voice packs already loaded by a successful operation.
    private(set) var preloadedVoices: Set<String> = []

    private let loadOperation: LoadOperation
    private var inFlightLoadTask: Task<Void, Never>?
    /// Which voice the sticky `failed` state refers to.
    private var failedVoice: String?
    /// Bumped per load so a finishing task only clears `inFlightLoadTask`
    /// when it is still the current one.
    private var loadGeneration = 0

    init(initialState: KokoroModelLoadState = .notLoaded, loadOperation: @escaping LoadOperation) {
        self.loadState = initialState
        self.loadOperation = loadOperation
    }

    func prepareIfNeeded(preloadingVoice voice: String) async {
        if case .unavailable = loadState { return }

        // Wait for any load already running. Loop rather than `if`: another
        // waiter may start a new load before we resume, and we must not
        // start a third one on top of it.
        while let runningLoadTask = inFlightLoadTask {
            await runningLoadTask.value
        }

        if case .ready = loadState, preloadedVoices.contains(voice) { return }
        if case .failed = loadState, failedVoice == voice { return }

        loadGeneration += 1
        let thisLoadGeneration = loadGeneration
        let loadOperation = loadOperation
        loadState = .loading

        let loadTask = Task { [weak self] in
            do {
                try await loadOperation(voice)
                guard let self else { return }
                self.preloadedVoices.insert(voice)
                self.failedVoice = nil
                self.loadState = .ready
            } catch {
                guard let self else { return }
                self.failedVoice = voice
                self.loadState = .failed(message: "couldn't load the kokoro voice model: \(error.localizedDescription)")
                print("⚠️ Kokoro load failed for \(voice): \(error)")
            }
            // Clear before any waiter resumes, and only if no newer load
            // has replaced this one.
            if let self, self.loadGeneration == thisLoadGeneration {
                self.inFlightLoadTask = nil
            }
        }
        inFlightLoadTask = loadTask
        await loadTask.value
    }

    /// Clears a `failed` state and tries again. Used by the Retry button.
    func retryLoad(preloadingVoice voice: String) async {
        if case .failed = loadState {
            loadState = .notLoaded
            failedVoice = nil
        }
        await prepareIfNeeded(preloadingVoice: voice)
    }
}
