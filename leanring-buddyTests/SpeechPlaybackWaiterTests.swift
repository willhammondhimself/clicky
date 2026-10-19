import Testing

#if canImport(leanring_buddy)
@testable import leanring_buddy
#else
@testable import LumenLogic
#endif

@MainActor
struct SpeechPlaybackWaiterTests {

    @Test func returnsOncePlaybackStops() async throws {
        var remainingPlayingPolls = 3
        var pollCount = 0
        try await SpeechPlaybackWaiter.waitUntilPlaybackEnds(pollInterval: .milliseconds(1), maximumWait: .seconds(5)) {
            pollCount += 1
            remainingPlayingPolls -= 1
            return remainingPlayingPolls >= 0
        }
        #expect(pollCount == 4)
    }

    @Test func returnsImmediatelyWhenNothingIsPlaying() async throws {
        var pollCount = 0
        try await SpeechPlaybackWaiter.waitUntilPlaybackEnds(pollInterval: .milliseconds(1), maximumWait: .seconds(5)) {
            pollCount += 1
            return false
        }
        #expect(pollCount == 1)
    }

    @Test func stopsWaitingAtTheDeadline() async throws {
        let clock = ContinuousClock()
        let start = clock.now
        try await SpeechPlaybackWaiter.waitUntilPlaybackEnds(pollInterval: .milliseconds(5), maximumWait: .milliseconds(60)) { true }
        #expect(clock.now - start < .seconds(2))
    }

    @Test func throwsWhenCancelled() async {
        let waitTask = Task { @MainActor in
            try await SpeechPlaybackWaiter.waitUntilPlaybackEnds(pollInterval: .milliseconds(5), maximumWait: .seconds(30)) { true }
        }
        try? await Task.sleep(for: .milliseconds(30))
        waitTask.cancel()
        await #expect(throws: CancellationError.self) {
            try await waitTask.value
        }
    }
}
