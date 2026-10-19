import Testing

#if canImport(leanring_buddy)
@testable import leanring_buddy
#else
@testable import LumenLogic
#endif

struct SentenceSplitterTests {

    @Test func splitsOnTerminalPunctuationFollowedBySpace() {
        let chunks = SentenceSplitter.split("the run button is top left. click it to start the build! want me to point again?")
        #expect(chunks == [
            "the run button is top left.",
            "click it to start the build!",
            "want me to point again?",
        ])
    }

    @Test func splitsOnNewlines() {
        let chunks = SentenceSplitter.split("first line of the answer here\nsecond line of the answer here")
        #expect(chunks == ["first line of the answer here", "second line of the answer here"])
    }

    @Test func mergesShortFragmentIntoFollowingChunk() {
        let chunks = SentenceSplitter.split("ok. the save button is in the top right of the window.")
        #expect(chunks == ["ok. the save button is in the top right of the window."])
    }

    @Test func mergesTrailingShortFragmentIntoPreviousChunk() {
        let chunks = SentenceSplitter.split("the save button is in the top right of the window. done.")
        #expect(chunks == ["the save button is in the top right of the window. done."])
    }

    @Test func keepsAbbreviationWithFollowingText() {
        // "e.g." is under 20 characters, so it is merged forward instead of
        // becoming its own 80 ms synthesis call.
        let chunks = SentenceSplitter.split("e.g. the toolbar at the top has the button you need.")
        #expect(chunks == ["e.g. the toolbar at the top has the button you need."])
    }

    @Test func doesNotSplitDecimalNumbers() {
        let chunks = SentenceSplitter.split("the fee is 3.5 percent of the total, which is shown on the right side.")
        #expect(chunks.count == 1)
    }

    @Test func treatsEllipsisAsOneBoundary() {
        let chunks = SentenceSplitter.split("hmm... i think the button you want is the blue one in the corner. click it now to continue.")
        #expect(chunks == [
            "hmm... i think the button you want is the blue one in the corner.",
            "click it now to continue.",
        ])
    }

    @Test func keepsClosingQuoteWithSentence() {
        let chunks = SentenceSplitter.split("it says \"build succeeded.\" now press the run button at the top.")
        #expect(chunks == ["it says \"build succeeded.\"", "now press the run button at the top."])
    }

    @Test func splitsOverlongChunkAtLastCommaBeforeLimit() {
        let longClause = String(repeating: "word ", count: 50).trimmingCharacters(in: .whitespaces) // 249 chars
        let text = "\(longClause), \(longClause)."
        let chunks = SentenceSplitter.split(text)
        #expect(chunks.count == 2)
        #expect(chunks[0].hasSuffix(","))
        #expect(chunks[1].hasSuffix("."))
    }

    @Test func keepsUnpunctuatedRunOnAsSingleChunk() {
        let runOn = String(repeating: "word ", count: 80).trimmingCharacters(in: .whitespaces) // 399 chars, no commas
        let chunks = SentenceSplitter.split(runOn)
        #expect(chunks == [runOn])
    }

    @Test func returnsEmptyForWhitespaceOnlyInput() {
        #expect(SentenceSplitter.split("   \n  ") == [])
        #expect(SentenceSplitter.split("") == [])
    }

    @Test func trimsSurroundingWhitespace() {
        let chunks = SentenceSplitter.split("   the answer is on the left side of the screen.   ")
        #expect(chunks == ["the answer is on the left side of the screen."])
    }
}
