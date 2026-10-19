import Testing

#if canImport(leanring_buddy)
@testable import leanring_buddy
#else
@testable import LumenLogic
#endif

struct CompanionVisualStateTests {

    @Test func flyingWinsOverEverything() {
        #expect(CompanionVisualState.resolve(isListening: true, isProcessing: true, isResponding: true, isFlyingToOrFromTarget: true) == .flying)
    }

    @Test func listeningWinsOverThinking() {
        #expect(CompanionVisualState.resolve(isListening: true, isProcessing: true, isResponding: false, isFlyingToOrFromTarget: false) == .listening)
    }

    @Test func thinkingWhileProcessing() {
        #expect(CompanionVisualState.resolve(isListening: false, isProcessing: true, isResponding: true, isFlyingToOrFromTarget: false) == .thinking)
    }

    @Test func speakingWhileResponding() {
        #expect(CompanionVisualState.resolve(isListening: false, isProcessing: false, isResponding: true, isFlyingToOrFromTarget: false) == .speaking)
    }

    @Test func idleWhenNothingIsHappening() {
        #expect(CompanionVisualState.resolve(isListening: false, isProcessing: false, isResponding: false, isFlyingToOrFromTarget: false) == .idle)
    }
}
