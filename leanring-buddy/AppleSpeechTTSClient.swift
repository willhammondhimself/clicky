//
//  AppleSpeechTTSClient.swift
//  leanring-buddy
//
//  On-device text-to-speech via AVSpeechSynthesizer. Free, offline, and the
//  default so Clicky talks on a fresh install with no accounts. Quality
//  depends on which voice is installed — download an "Enhanced" or
//  "Premium" voice in System Settings → Accessibility → Spoken Content.
//

import AVFoundation
import Foundation

@MainActor
final class AppleSpeechTTSClient: NSObject, TTSClient {
    private let speechSynthesizer = AVSpeechSynthesizer()
    private let voiceIdentifier: String

    /// Set when speech begins and cleared when it finishes or is cancelled.
    /// `AVSpeechSynthesizer.isSpeaking` is also consulted, but tracking it
    /// ourselves covers the brief window between `speak()` and audio start.
    private var isCurrentlySpeaking = false

    /// - Parameter voiceIdentifier: `AVSpeechSynthesisVoice.identifier`, or
    ///   empty to use the system default voice for the current language.
    init(voiceIdentifier: String) {
        self.voiceIdentifier = voiceIdentifier
        super.init()
        speechSynthesizer.delegate = self
    }

    func speakText(_ text: String) async throws {
        stopPlayback()

        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = resolveVoice()
        // Slightly faster than the default keeps short answers snappy without
        // sounding rushed; matches the "direct and dense" system prompt.
        utterance.rate = AVSpeechUtteranceDefaultSpeechRate * 1.05

        isCurrentlySpeaking = true
        speechSynthesizer.speak(utterance)
        print("🔊 Apple TTS: speaking with \(utterance.voice?.name ?? "default voice")")
    }

    var isPlaying: Bool {
        isCurrentlySpeaking || speechSynthesizer.isSpeaking
    }

    func stopPlayback() {
        if speechSynthesizer.isSpeaking {
            speechSynthesizer.stopSpeaking(at: .immediate)
        }
        isCurrentlySpeaking = false
    }

    private func resolveVoice() -> AVSpeechSynthesisVoice? {
        if !voiceIdentifier.isEmpty, let chosenVoice = AVSpeechSynthesisVoice(identifier: voiceIdentifier) {
            return chosenVoice
        }
        let currentLanguageCode = AVSpeechSynthesisVoice.currentLanguageCode()
        return AVSpeechSynthesisVoice(language: currentLanguageCode)
            ?? AVSpeechSynthesisVoice(language: "en-US")
    }
}

extension AppleSpeechTTSClient: AVSpeechSynthesizerDelegate {
    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        Task { @MainActor in
            self.isCurrentlySpeaking = false
        }
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        Task { @MainActor in
            self.isCurrentlySpeaking = false
        }
    }
}
