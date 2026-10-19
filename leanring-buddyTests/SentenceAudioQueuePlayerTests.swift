import AVFoundation
import Testing

#if canImport(leanring_buddy)
@testable import leanring_buddy
#else
@testable import LumenLogic
#endif

/// The player is main-actor isolated and the Xcode test target has no
/// default isolation, so the suite runs on the main actor explicitly.
@MainActor
struct SentenceAudioQueuePlayerTests {

    private func silentBuffer(seconds: Double) -> AVAudioPCMBuffer {
        let sampleCount = Int(seconds * SentenceAudioQueuePlayer.sampleRate)
        return SentenceAudioQueuePlayer.makeBuffer(
            samples: [Float](repeating: 0, count: sampleCount),
            sampleRate: SentenceAudioQueuePlayer.sampleRate
        )!
    }

    private func waitUntilNotPlaying(_ player: SentenceAudioQueuePlayer, timeoutSeconds: Double) async -> Bool {
        let deadline = Date().addingTimeInterval(timeoutSeconds)
        while player.isPlaying && Date() < deadline {
            try? await Task.sleep(nanoseconds: 50_000_000)
        }
        return !player.isPlaying
    }

    @Test func makeBufferCopiesSamplesAtTheRequestedRate() {
        let buffer = SentenceAudioQueuePlayer.makeBuffer(samples: [0.25, -0.25, 0.5], sampleRate: 24_000)
        #expect(buffer != nil)
        #expect(buffer?.frameLength == 3)
        #expect(buffer?.format.sampleRate == 24_000)
        #expect(buffer?.format.channelCount == 1)
        #expect(buffer?.floatChannelData?[0][2] == 0.5)
    }

    @Test func makeBufferReturnsNilForEmptySamples() {
        #expect(SentenceAudioQueuePlayer.makeBuffer(samples: [], sampleRate: 24_000) == nil)
    }

    @Test func isPlayingTracksQueuedBuffersUntilTheyFinish() async throws {
        let player = SentenceAudioQueuePlayer()
        #expect(player.isPlaying == false)

        try player.enqueue(silentBuffer(seconds: 0.1))
        try player.enqueue(silentBuffer(seconds: 0.1))
        #expect(player.isPlaying == true)

        let finished = await waitUntilNotPlaying(player, timeoutSeconds: 3)
        #expect(finished == true)
    }

    @Test func stopDiscardsPendingCompletions() async throws {
        let player = SentenceAudioQueuePlayer()
        try player.enqueue(silentBuffer(seconds: 1.0))
        #expect(player.isPlaying == true)

        player.stop()
        #expect(player.isPlaying == false)

        // Late completion callbacks from the stopped buffer must not disturb
        // a new queue.
        try player.enqueue(silentBuffer(seconds: 0.2))
        #expect(player.isPlaying == true)
        let finished = await waitUntilNotPlaying(player, timeoutSeconds: 3)
        #expect(finished == true)
        #expect(player.isPlaying == false)
    }
}
