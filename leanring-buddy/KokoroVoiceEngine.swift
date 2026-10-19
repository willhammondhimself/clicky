//
//  KokoroVoiceEngine.swift
//  leanring-buddy
//
//  Owns the single Kokoro model manager from FluidAudio. It is a singleton
//  because CompanionManager rebuilds its TTS client on every settings change
//  and the Kokoro models (~380 MB under Application Support plus ~40 MB of
//  pronunciation assets in FluidAudio's own cache, compiled for the Neural
//  Engine on first use) must load once per app run, not once per client.
//
//  First run downloads the models from Hugging Face and compiles them, which
//  takes tens of seconds; later runs load in about a second. The panel
//  observes `loadState` to show what is happening. Load sequencing (one load
//  at a time, sticky failures, retry) lives in KokoroModelLoadCoordinator.
//

import AVFoundation
import Combine
import FluidAudio
import Foundation

@MainActor
final class KokoroVoiceEngine: ObservableObject, KokoroSentenceSynthesizing {
    enum EngineError: LocalizedError {
        case modelNotReady
        case emptyAudio

        var errorDescription: String? {
            switch self {
            case .modelNotReady: return "The Kokoro voice model is not loaded."
            case .emptyAudio: return "Kokoro returned no audio for that sentence."
            }
        }
    }

    static let shared = KokoroVoiceEngine()

    /// The CoreML models and voice packs. FluidAudio keeps its English
    /// pronunciation assets (BART G2P + lexicon, ~40 MB) in its own default
    /// cache regardless of this setting.
    static let modelsDirectory: URL = ApplicationSupportFolderMigration.currentFolderURL
        .appendingPathComponent("Models", isDirectory: true)

    @Published private(set) var loadState: KokoroModelLoadState = .notLoaded

    private var loadCoordinator: KokoroModelLoadCoordinator!
    private var kokoroManager: KokoroAneManager?
    private var loadStateCancellable: AnyCancellable?

    private init() {
        let initialState: KokoroModelLoadState
        if let blockingReason = KokoroOperatingSystemSupport.blockingReason(for: ProcessInfo.processInfo.operatingSystemVersion) {
            initialState = .unavailable(reason: blockingReason)
        } else {
            initialState = .notLoaded
        }

        loadCoordinator = KokoroModelLoadCoordinator(initialState: initialState) { [weak self] voice in
            guard let self else { return }
            try await self.loadModelAndVoice(voice)
        }
        loadState = initialState
        loadStateCancellable = loadCoordinator.$loadState.sink { [weak self] newState in
            self?.loadState = newState
        }
    }

    // MARK: - Loading

    /// Downloads (first time), compiles and loads the models plus `voice`'s
    /// pack. Returns when done or failed; never throws. Safe to call from
    /// several places at once — see KokoroModelLoadCoordinator.
    func prepareIfNeeded(preloadingVoice voice: String) async {
        await loadCoordinator.prepareIfNeeded(preloadingVoice: voice)
    }

    /// Clears a `failed` state and tries again. Used by the Retry button.
    func retryLoad(preloadingVoice voice: String) async {
        await loadCoordinator.retryLoad(preloadingVoice: voice)
    }

    private func loadModelAndVoice(_ voice: String) async throws {
        let manager = kokoroManager ?? makeManager()
        kokoroManager = manager
        try await manager.initialize(preloadVoices: [voice])

        // The first synthesis pays for the pronunciation lexicon (178k
        // entries) and the Neural Engine kernel compile — around 9 s on
        // Will's M4 Pro. Spend it now, while nobody is waiting, instead of
        // on the first real reply.
        let warmUpStart = Date()
        _ = try await manager.synthesizeDetailed(text: "ready.", voice: voice)
        print("🔊 Kokoro: model ready, voice \(voice) loaded (warm-up synthesis \(String(format: "%.1f", Date().timeIntervalSince(warmUpStart))) s)")
    }

    // MARK: - Synthesis

    /// Text for one sentence → 24 kHz mono buffer. A voice that was not
    /// preloaded is fetched on demand by the library.
    func synthesizeSentence(_ sentence: String, voice: String) async throws -> AVAudioPCMBuffer {
        guard case .ready = loadState, let kokoroManager else {
            throw EngineError.modelNotReady
        }

        let synthesisResult = try await kokoroManager.synthesizeDetailed(text: sentence, voice: voice)
        guard let buffer = SentenceAudioQueuePlayer.makeBuffer(
            samples: synthesisResult.samples,
            sampleRate: Double(synthesisResult.sampleRate)
        ) else {
            throw EngineError.emptyAudio
        }
        return buffer
    }

    // MARK: - Manager

    private func makeManager() -> KokoroAneManager {
        let runtimeVersion: KokoroAneVersion = KokoroOperatingSystemSupport.supportsVersion3Runtime() ? .v3 : .legacy
        return KokoroAneManager(
            variant: .english,
            defaultVoice: KokoroVoiceCatalog.defaultVoice,
            directory: Self.modelsDirectory,
            version: runtimeVersion
        )
    }
}
