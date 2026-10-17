import Foundation
import Testing

#if canImport(leanring_buddy)
@testable import leanring_buddy
#else
@testable import ClickyLogic
#endif

struct MemoryTranscriptCommandTests {

    @Test func rememberThatYieldsTheFact() {
        #expect(MemoryTranscriptCommand.rememberedFact(fromTranscript: "remember that I use zed") == "I use zed")
    }

    @Test func rememberThisWithPunctuationYieldsTheFact() {
        #expect(MemoryTranscriptCommand.rememberedFact(fromTranscript: "Remember this, my cat is mochi.") == "my cat is mochi")
        #expect(MemoryTranscriptCommand.rememberedFact(fromTranscript: "remember this: ship friday!") == "ship friday")
    }

    @Test func rememberToKeepsTheTo() {
        #expect(MemoryTranscriptCommand.rememberedFact(fromTranscript: "remember to ship the demo on friday") == "to ship the demo on friday")
    }

    @Test func bareRememberYieldsTheRest() {
        #expect(MemoryTranscriptCommand.rememberedFact(fromTranscript: "remember my advisor is alan") == "my advisor is alan")
    }

    @Test func allowsAHeyClickyPrefix() {
        #expect(MemoryTranscriptCommand.rememberedFact(fromTranscript: "hey clicky, remember that I use zed") == "I use zed")
        #expect(MemoryTranscriptCommand.rememberedFact(fromTranscript: "Clicky remember that I use zed") == "I use zed")
    }

    @Test func rememberNotAtTheStartIsNotACommand() {
        #expect(MemoryTranscriptCommand.rememberedFact(fromTranscript: "can you remember what I said about zed") == nil)
        #expect(MemoryTranscriptCommand.rememberedFact(fromTranscript: "do you remember my cat") == nil)
    }

    @Test func rememberWithNothingAfterItIsNotACommand() {
        #expect(MemoryTranscriptCommand.rememberedFact(fromTranscript: "remember this") == nil)
        #expect(MemoryTranscriptCommand.rememberedFact(fromTranscript: "remember that.") == nil)
        #expect(MemoryTranscriptCommand.rememberedFact(fromTranscript: "remember") == nil)
    }

    @Test func wordsStartingWithRememberAreNotCommands() {
        #expect(MemoryTranscriptCommand.rememberedFact(fromTranscript: "remembering is hard") == nil)
    }
}
