//
//  SpeechPlaybackWaiter.swift
//  leanring-buddy
//
//  speakText returns as soon as audio starts (Kokoro queues the first
//  sentence and keeps synthesizing), so the pipeline waits here until the
//  reply has finished playing before leaving the speaking state. Polls the
//  TTS client's isPlaying, honours task cancellation (the user pressing the
//  hotkey again), and gives up at a deadline so a stuck player can never
//  leave the companion speaking forever.
//

import Foundation

nonisolated enum SpeechPlaybackWaiter {
    @MainActor
    static func waitUntilPlaybackEnds(
        pollInterval: Duration = .milliseconds(150),
        maximumWait: Duration = .seconds(180),
        isPlaying: () -> Bool
    ) async throws {
        let clock = ContinuousClock()
        let deadline = clock.now + maximumWait
        while isPlaying() {
            try Task.checkCancellation()
            if clock.now >= deadline { return }
            try await Task.sleep(for: pollInterval)
        }
    }
}
