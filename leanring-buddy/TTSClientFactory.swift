//
//  TTSClientFactory.swift
//  leanring-buddy
//
//  Builds the text-to-speech client for the current settings. Called by
//  CompanionManager at start and whenever a voice setting changes.
//

import Foundation

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
                appleFallbackVoiceIdentifier: appSettings.appleVoiceIdentifier,
                voiceEngine: KokoroVoiceEngine.shared
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
