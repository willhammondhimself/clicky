import AVFoundation
import Foundation
import Testing

#if canImport(leanring_buddy)
@testable import leanring_buddy
#else
@testable import LumenLogic
#endif

/// Stands in for KokoroVoiceEngine: always ready, returns a short silent
/// buffer per sentence, and can hold specific calls open so a test can
/// interleave two replies.
@MainActor
final class FakeSentenceSynthesizer: KokoroSentenceSynthesizing {
    var loadState: KokoroModelLoadState = .ready
    private(set) var synthesizedSentences: [String] = []

    /// 1-based indexes of synthesize calls that block until `release(call:)`.
    var blockedCallIndexes: Set<Int> = []
    private var blockedContinuations: [Int: CheckedContinuation<Void, Never>] = [:]
    private var callCount = 0

    func prepareIfNeeded(preloadingVoice voice: String) async {}

    func synthesizeSentence(_ sentence: String, voice: String) async throws -> AVAudioPCMBuffer {
        callCount += 1
        let thisCall = callCount
        synthesizedSentences.append(sentence)
        if blockedCallIndexes.contains(thisCall) {
            await withCheckedContinuation { continuation in
                blockedContinuations[thisCall] = continuation
            }
        }
        let tenMillisecondsOfSilence = [Float](repeating: 0, count: 240)
        return SentenceAudioQueuePlayer.makeBuffer(samples: tenMillisecondsOfSilence, sampleRate: 24_000)!
    }

    func release(call callIndex: Int) {
        blockedContinuations.removeValue(forKey: callIndex)?.resume()
    }

    func releaseAll() {
        let continuations = blockedContinuations.values
        blockedContinuations = [:]
        continuations.forEach { $0.resume() }
    }
}

@MainActor
struct KokoroTTSClientTests {

    private let threeSentenceReply = "the first sentence is here. the second sentence is here. the third sentence is here."

    private func settle() async {
        try? await Task.sleep(nanoseconds: 60_000_000)
    }

    @Test func speakTextReturnsAfterTheFirstSentenceAndKeepsSynthesizingTheRest() async throws {
        let synthesizer = FakeSentenceSynthesizer()
        synthesizer.blockedCallIndexes = [2]
        let client = KokoroTTSClient(voice: "bm_george", appleFallbackVoiceIdentifier: "", voiceEngine: synthesizer)

        try await client.speakText(threeSentenceReply)
        #expect(synthesizer.synthesizedSentences.count >= 1)
        await settle()
        #expect(synthesizer.synthesizedSentences.count == 2)
        #expect(client.isPlaying == true)

        synthesizer.releaseAll()
        await settle()
        #expect(synthesizer.synthesizedSentences.count == 3)
    }

    @Test func aCancelledReplyDoesNotMarkTheNextReplyAsFinished() async throws {
        let synthesizer = FakeSentenceSynthesizer()
        // Reply 1: calls 1 (first sentence), 2 (blocked). Reply 2: calls 3, 4 (blocked).
        synthesizer.blockedCallIndexes = [2, 4]
        let client = KokoroTTSClient(voice: "bm_george", appleFallbackVoiceIdentifier: "", voiceEngine: synthesizer)

        try await client.speakText(threeSentenceReply)
        await settle()

        // The user presses the hotkey: reply 1 is abandoned while its second
        // sentence is still inside the synthesizer.
        client.stopPlayback()
        try await client.speakText(threeSentenceReply)
        await settle()
        #expect(client.isPlaying == true)

        // The abandoned synthesis finally returns. Reply 2 is still being
        // synthesized, so the client must still report playing.
        synthesizer.release(call: 2)
        await settle()
        #expect(client.isPlaying == true)

        synthesizer.releaseAll()
        await settle()
        await settle()
        #expect(client.isPlaying == false)
    }

    @Test func stopPlaybackReportsNotPlayingImmediately() async throws {
        let synthesizer = FakeSentenceSynthesizer()
        synthesizer.blockedCallIndexes = [2]
        let client = KokoroTTSClient(voice: "bm_george", appleFallbackVoiceIdentifier: "", voiceEngine: synthesizer)

        try await client.speakText(threeSentenceReply)
        client.stopPlayback()
        #expect(client.isPlaying == false)
        synthesizer.releaseAll()
    }
}
