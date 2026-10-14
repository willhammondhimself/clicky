//
//  KokoroVoiceEngine.swift
//  leanring-buddy
//
//  Owns the single Kokoro model manager from FluidAudio. It is a singleton
//  because CompanionManager rebuilds its TTS client on every settings change
//  and the Kokoro models (~300 MB, compiled for the Neural Engine on first
//  use) must load once per app run, not once per client.
//
//  First run downloads the models from Hugging Face and compiles them, which
//  takes tens of seconds; later runs load in well under a second. The panel
//  observes `loadState` to show what is happening.
//

import AVFoundation
import Combine
import FluidAudio
import Foundation

@MainActor
final class KokoroVoiceEngine: ObservableObject {
    enum LoadState: Equatable {
        case notLoaded
        case loading
        case ready
        case failed(message: String)
        /// This macOS build cannot run Kokoro safely; see KokoroOperatingSystemSupport.
        case unavailable(reason: String)
    }

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

    /// Everything Kokoro downloads lives here so it is easy to find and delete.
    static let modelsDirectory: URL = FileManager.default
        .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("Clicky/Models", isDirectory: true)

    @Published private(set) var loadState: LoadState

    private var kokoroManager: KokoroAneManager?
    private var inFlightLoadTask: Task<Void, Never>?
    /// Voice packs already fetched and converted, so switching back to one is instant.
    private var preloadedVoices: Set<String> = []

    private init() {
        if let blockingReason = KokoroOperatingSystemSupport.blockingReason(for: ProcessInfo.processInfo.operatingSystemVersion) {
            loadState = .unavailable(reason: blockingReason)
        } else {
            loadState = .notLoaded
        }
    }

    // MARK: - Loading

    /// Downloads (first time), compiles and loads the models plus `voice`'s
    /// pack. Returns when done or failed; never throws. Safe to call
    /// repeatedly — a load already in flight is awaited, and a voice already
    /// preloaded returns immediately.
    func prepareIfNeeded(preloadingVoice voice: String) async {
        if case .unavailable = loadState { return }

        if let inFlightLoadTask {
            await inFlightLoadTask.value
        }

        if case .ready = loadState, preloadedVoices.contains(voice) { return }
        if case .failed = loadState { return }

        let manager = kokoroManager ?? makeManager()
        kokoroManager = manager
        loadState = .loading

        let loadTask = Task { [weak self] in
            do {
                try await manager.initialize(preloadVoices: [voice])
                // The first synthesis pays for the pronunciation lexicon
                // (178k entries) and the Neural Engine kernel compile —
                // around 9 s on Will's M4 Pro. Spend it now, while nobody is
                // waiting, instead of on the first real reply.
                let warmUpStart = Date()
                _ = try await manager.synthesizeDetailed(text: "ready.", voice: voice)
                self?.preloadedVoices.insert(voice)
                self?.loadState = .ready
                print("🔊 Kokoro: model ready, voice \(voice) loaded (warm-up synthesis \(String(format: "%.1f", Date().timeIntervalSince(warmUpStart))) s)")
            } catch {
                self?.loadState = .failed(message: "couldn't load the kokoro voice model: \(error.localizedDescription)")
                print("⚠️ Kokoro load failed: \(error)")
            }
        }
        inFlightLoadTask = loadTask
        await loadTask.value
        inFlightLoadTask = nil
    }

    /// Clears a `failed` state and tries again. Used by the Retry button.
    func retryLoad(preloadingVoice voice: String) async {
        if case .failed = loadState {
            loadState = .notLoaded
        }
        await prepareIfNeeded(preloadingVoice: voice)
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
