//
//  TTSClient.swift
//  leanring-buddy
//
//  Common surface for text-to-speech backends so CompanionManager can swap
//  between Kokoro (on-device, default), Apple's on-device synthesizer, and
//  ElevenLabs (cloud). The factory that picks one lives in
//  TTSClientFactory.swift so this file stays free of settings/Keychain
//  dependencies and can be compiled in the terminal test harness.
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
