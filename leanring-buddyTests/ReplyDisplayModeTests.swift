import Testing

#if canImport(leanring_buddy)
@testable import leanring_buddy
#else
@testable import LumenLogic
#endif

struct ReplyDisplayModeTests {

    @Test func defaultIsVoiceAndText() {
        #expect(ReplyDisplayMode.defaultMode == .voiceAndText)
    }

    @Test func rawValuesAreStableForPersistence() {
        #expect(ReplyDisplayMode.allCases.map(\.rawValue) == ["voiceAndText", "voiceOnly", "textOnly"])
    }

    @Test func displayNames() {
        #expect(ReplyDisplayMode.allCases.map(\.displayName) == ["Voice + text", "Voice only", "Text only"])
    }

    @Test func eachModeSpeaksAndShowsTextAsNamed() {
        #expect(ReplyDisplayMode.voiceAndText.speaksReply && ReplyDisplayMode.voiceAndText.showsReplyText)
        #expect(ReplyDisplayMode.voiceOnly.speaksReply && !ReplyDisplayMode.voiceOnly.showsReplyText)
        #expect(!ReplyDisplayMode.textOnly.speaksReply && ReplyDisplayMode.textOnly.showsReplyText)
    }

    @Test func textRevealsAtFortyCharactersPerSecondAndStopsAtTheEnd() {
        #expect(ReplyTextTiming.revealedCharacterCount(secondsSinceShown: 0, totalCharacterCount: 100) == 0)
        #expect(ReplyTextTiming.revealedCharacterCount(secondsSinceShown: 0.5, totalCharacterCount: 100) == 20)
        #expect(ReplyTextTiming.revealedCharacterCount(secondsSinceShown: 10, totalCharacterCount: 100) == 100)
        #expect(ReplyTextTiming.revealedCharacterCount(secondsSinceShown: -1, totalCharacterCount: 100) == 0)
    }

    @Test func textOnlyRepliesStayLongEnoughToRead() {
        // Reading pace of about 15 characters a second plus a moment to look
        // over, never shorter than 3 s and never longer than 20 s.
        #expect(ReplyTextTiming.textOnlyHoldSeconds(characterCount: 10) == 3)
        #expect(ReplyTextTiming.textOnlyHoldSeconds(characterCount: 150) == 12)
        #expect(ReplyTextTiming.textOnlyHoldSeconds(characterCount: 1_000) == 20)
    }

    @Test func spokenRepliesLingerThreeSecondsAfterTheVoiceStops() {
        #expect(ReplyTextTiming.secondsShownAfterSpeechEnds == 3)
    }
}
