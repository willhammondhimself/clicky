//
//  ElevenLabsTTSClient.swift
//  leanring-buddy
//
//  Fetches text-to-speech audio from ElevenLabs and plays it back through
//  the system audio output. Calls the API directly with a key from the
//  Keychain; opt-in via Settings → Text to Speech.
//

import AVFoundation
import Foundation

@MainActor
final class ElevenLabsTTSClient: TTSClient {
    private let textToSpeechURL: URL
    private let apiKey: String?
    private let session: URLSession

    /// The audio player for the current TTS playback. Kept alive so the
    /// audio finishes playing even if the caller doesn't hold a reference.
    private var audioPlayer: AVAudioPlayer?

    init(apiKey: String?, voiceID: String) {
        self.apiKey = apiKey
        let trimmedVoiceID = voiceID.trimmingCharacters(in: .whitespacesAndNewlines)
        let effectiveVoiceID = trimmedVoiceID.isEmpty ? AppSettings.defaultElevenLabsVoiceID : trimmedVoiceID
        self.textToSpeechURL = URL(string: "https://api.elevenlabs.io/v1/text-to-speech/\(effectiveVoiceID)")!

        let configuration = URLSessionConfiguration.default
        configuration.timeoutIntervalForRequest = 30
        configuration.timeoutIntervalForResource = 60
        self.session = URLSession(configuration: configuration)
    }

    /// Sends `text` to ElevenLabs TTS and plays the resulting audio.
    /// Throws on network or decoding errors. Cancellation-safe.
    func speakText(_ text: String) async throws {
        guard let apiKey else {
            throw NSError(domain: "ElevenLabsTTS", code: -2,
                          userInfo: [NSLocalizedDescriptionKey: "No ElevenLabs API key saved. Add one in Settings or switch Text to Speech to Apple."])
        }

        var request = URLRequest(url: textToSpeechURL)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("audio/mpeg", forHTTPHeaderField: "Accept")
        request.setValue(apiKey, forHTTPHeaderField: "xi-api-key")

        let body: [String: Any] = [
            "text": text,
            "model_id": "eleven_flash_v2_5",
            "voice_settings": [
                "stability": 0.5,
                "similarity_boost": 0.75
            ]
        ]

        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw NSError(domain: "ElevenLabsTTS", code: -1,
                          userInfo: [NSLocalizedDescriptionKey: "Invalid response"])
        }

        guard (200...299).contains(httpResponse.statusCode) else {
            let errorBody = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw NSError(domain: "ElevenLabsTTS", code: httpResponse.statusCode,
                          userInfo: [NSLocalizedDescriptionKey: "TTS API error (\(httpResponse.statusCode)): \(errorBody)"])
        }

        try Task.checkCancellation()

        let player = try AVAudioPlayer(data: data)
        self.audioPlayer = player
        player.play()
        print("🔊 ElevenLabs TTS: playing \(data.count / 1024)KB audio")
    }

    /// Whether TTS audio is currently playing back.
    var isPlaying: Bool {
        audioPlayer?.isPlaying ?? false
    }

    /// Stops any in-progress playback immediately.
    func stopPlayback() {
        audioPlayer?.stop()
        audioPlayer = nil
    }
}
