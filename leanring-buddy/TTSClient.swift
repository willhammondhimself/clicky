//
//  TTSClient.swift
//  leanring-buddy
//
//  Common surface for text-to-speech backends so CompanionManager can swap
//  between Kokoro (on-device, default), Apple's on-device synthesizer, and
//  ElevenLabs (cloud).
//

import Foundation

@MainActor
protocol TTSClient: AnyObject {
    /// Starts speaking `text`. Returns once audio playback has begun (not
    /// when it finishes) so the caller can flip the UI into "responding".
    func speakText(_ text: String) async throws

    /// Whether audio is currently being played. Polled by the transient
    /// cursor-hide logic to wait for speech to end.
    var isPlaying: Bool { get }

    func stopPlayback()
}

enum TTSClientFactory {
    @MainActor
    static func makeClient(from appSettings: AppSettings) -> any TTSClient {
        switch appSettings.textToSpeechProviderKind {
        case .kokoro:
            // Start (or continue) loading the model now so the first reply
            // isn't stuck behind a cold load — same idea as OllamaModelWarmer.
            let kokoroVoice = appSettings.kokoroVoice
            Task {
                await KokoroVoiceEngine.shared.prepareIfNeeded(preloadingVoice: kokoroVoice)
            }
            return KokoroTTSClient(
                voice: kokoroVoice,
                appleFallbackVoiceIdentifier: appSettings.appleVoiceIdentifier
            )
        case .apple:
            return AppleSpeechTTSClient(voiceIdentifier: appSettings.appleVoiceIdentifier)
        case .elevenLabs:
            return ElevenLabsTTSClient(
                apiKey: SecretsStore.read(.elevenLabs),
                voiceID: appSettings.elevenLabsVoiceID
            )
        }
    }
}
