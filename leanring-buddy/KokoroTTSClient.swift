//
//  KokoroTTSClient.swift
//  leanring-buddy
//
//  Text-to-speech through the on-device Kokoro model. Splits the reply into
//  sentences, synthesizes each through KokoroVoiceEngine and queues the
//  audio so playback starts after the first sentence (~80 ms) while the
//  rest are still being generated.
//
//  If the model cannot load (no network on first run, unsupported macOS
//  build) the reply is spoken with the Apple voice instead, so the user
//  always hears the answer.
//

import AVFoundation
import Foundation

@MainActor
final class KokoroTTSClient: TTSClient {
    private let voice: String
    private let voiceEngine: KokoroVoiceEngine
    private let queuePlayer = SentenceAudioQueuePlayer()
    private let appleFallbackClient: AppleSpeechTTSClient

    /// Synthesizes sentences two onward after `speakText` has returned.
    private var remainingSentencesTask: Task<Void, Never>?
    private var isSynthesizingRemainingSentences = false

    init(voice: String, appleFallbackVoiceIdentifier: String, voiceEngine: KokoroVoiceEngine = .shared) {
        self.voice = voice
        self.voiceEngine = voiceEngine
        self.appleFallbackClient = AppleSpeechTTSClient(voiceIdentifier: appleFallbackVoiceIdentifier)
    }

    // MARK: - TTSClient

    func speakText(_ text: String) async throws {
        stopPlayback()

        // On first run this is the model download + compile; the caller keeps
        // its spinner up until we return.
        await voiceEngine.prepareIfNeeded(preloadingVoice: voice)
        try Task.checkCancellation()

        switch voiceEngine.loadState {
        case .ready:
            break
        case .failed(let message):
            print("⚠️ Kokoro unavailable (\(message)); speaking with the Apple voice instead")
            try await appleFallbackClient.speakText(text)
            return
        case .unavailable(let reason):
            print("⚠️ \(reason)")
            try await appleFallbackClient.speakText(text)
            return
        case .notLoaded, .loading:
            // prepareIfNeeded only returns in a terminal state; treat anything
            // else as a failure rather than speaking nothing.
            print("⚠️ Kokoro in unexpected state \(voiceEngine.loadState); speaking with the Apple voice instead")
            try await appleFallbackClient.speakText(text)
            return
        }

        let sentences = SentenceSplitter.split(text)
        guard let firstSentence = sentences.first else { return }

        do {
            let firstBuffer = try await voiceEngine.synthesizeSentence(firstSentence, voice: voice)
            try Task.checkCancellation()
            try queuePlayer.enqueue(firstBuffer)
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            print("⚠️ Kokoro synthesis failed: \(error); speaking with the Apple voice instead")
            try await appleFallbackClient.speakText(text)
            return
        }

        print("🔊 Kokoro TTS: speaking \(sentences.count) sentence(s) with \(voice)")

        let remainingSentences = Array(sentences.dropFirst())
        guard !remainingSentences.isEmpty else { return }

        isSynthesizingRemainingSentences = true
        remainingSentencesTask = Task { [weak self] in
            guard let self else { return }
            defer { self.isSynthesizingRemainingSentences = false }

            for (sentenceIndex, sentence) in remainingSentences.enumerated() {
                guard !Task.isCancelled else { return }
                do {
                    let buffer = try await self.voiceEngine.synthesizeSentence(sentence, voice: self.voice)
                    guard !Task.isCancelled else { return }
                    try self.queuePlayer.enqueue(buffer)
                } catch {
                    guard !Task.isCancelled else { return }
                    print("⚠️ Kokoro synthesis failed mid-reply: \(error); finishing with the Apple voice")
                    let unspokenText = remainingSentences[sentenceIndex...].joined(separator: " ")
                    await self.finishWithAppleVoiceAfterQueueDrains(unspokenText)
                    return
                }
            }
        }
    }

    var isPlaying: Bool {
        queuePlayer.isPlaying || isSynthesizingRemainingSentences || appleFallbackClient.isPlaying
    }

    func stopPlayback() {
        remainingSentencesTask?.cancel()
        remainingSentencesTask = nil
        isSynthesizingRemainingSentences = false
        queuePlayer.stop()
        appleFallbackClient.stopPlayback()
    }

    // MARK: - Fallback

    /// Waits for the already-queued Kokoro audio to finish, then speaks the
    /// rest with the Apple voice so the two never overlap.
    private func finishWithAppleVoiceAfterQueueDrains(_ unspokenText: String) async {
        while queuePlayer.isPlaying && !Task.isCancelled {
            try? await Task.sleep(nanoseconds: 100_000_000)
        }
        guard !Task.isCancelled else { return }
        try? await appleFallbackClient.speakText(unspokenText)
    }
}
