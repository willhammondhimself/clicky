import Testing

#if canImport(leanring_buddy)
@testable import leanring_buddy
#else
@testable import LumenLogic
#endif

struct PointingBubbleTextTests {

    @Test func usesTheTrimmedLabel() {
        #expect(PointingBubbleText.bubbleText(elementLabel: " Export ", fallbackPhraseIndex: 0) == "Export")
    }

    @Test func noneOrBlankLabelUsesAPhrase() {
        for label in [nil, "", "   ", "none", "NONE"] as [String?] {
            #expect(PointingBubbleText.bubbleText(elementLabel: label, fallbackPhraseIndex: 0) == PointingBubbleText.fallbackPhrases[0], "\(String(describing: label))")
        }
    }

    @Test func phraseIndexWraps() {
        #expect(PointingBubbleText.bubbleText(elementLabel: nil, fallbackPhraseIndex: 5) == PointingBubbleText.fallbackPhrases[1])
    }
}
