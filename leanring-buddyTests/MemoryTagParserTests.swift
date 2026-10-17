import Foundation
import Testing

#if canImport(leanring_buddy)
@testable import leanring_buddy
#else
@testable import ClickyLogic
#endif

struct MemoryTagParserTests {

    @Test func textWithoutTagsIsUnchanged() {
        let result = MemoryTagParser.parse("the save button is top right. [POINT:120,40:save:screen1]")
        #expect(result.textWithoutMemoryTags == "the save button is top right. [POINT:120,40:save:screen1]")
        #expect(result.rememberedFacts.isEmpty)
        #expect(result.forgetRequests.isEmpty)
    }

    @Test func extractsASingleRememberTagAtTheEnd() {
        let result = MemoryTagParser.parse("mochi, great name. noted. [REMEMBER:About me:has a cat called mochi]")
        #expect(result.textWithoutMemoryTags == "mochi, great name. noted.")
        #expect(result.rememberedFacts == [RememberedFact(sectionName: "About me", factText: "has a cat called mochi")])
    }

    @Test func removesATagInTheMiddleLeavingSingleSpaces() {
        let result = MemoryTagParser.parse("noted [REMEMBER:Tools:uses zed] and the file menu is top left.")
        #expect(result.textWithoutMemoryTags == "noted and the file menu is top left.")
    }

    @Test func extractsSeveralRememberTagsAndAForgetTag() {
        let result = MemoryTagParser.parse("done. [REMEMBER:Tools:uses zed] [REMEMBER:Notes:ships friday] [FORGET:has a cat called mochi]")
        #expect(result.textWithoutMemoryTags == "done.")
        #expect(result.rememberedFacts.map(\.factText) == ["uses zed", "ships friday"])
        #expect(result.forgetRequests == ["has a cat called mochi"])
    }

    @Test func memoryTagsBeforeAndAfterThePointTagLeaveThePointTagAtTheEnd() {
        let result = MemoryTagParser.parse("on it. [REMEMBER:Notes:ships friday] [POINT:none] [FORGET:old thing]")
        #expect(result.textWithoutMemoryTags == "on it. [POINT:none]")
        #expect(result.textWithoutMemoryTags.hasSuffix("[POINT:none]"))
    }

    @Test func acceptsLowercaseAndSpacedVariants() {
        let result = MemoryTagParser.parse("ok. [ remember : tools : uses zed ] [ forget : the cat ]")
        #expect(result.textWithoutMemoryTags == "ok.")
        #expect(result.rememberedFacts == [RememberedFact(sectionName: "tools", factText: "uses zed")])
        #expect(result.forgetRequests == ["the cat"])
    }

    @Test func keepsColonsInsideTheFact() {
        let result = MemoryTagParser.parse("[REMEMBER:Notes:meeting at 10:30 with alan: bring slides]")
        #expect(result.rememberedFacts == [RememberedFact(sectionName: "Notes", factText: "meeting at 10:30 with alan: bring slides")])
    }

    @Test func rememberWithoutASectionUsesAnEmptySectionName() {
        let result = MemoryTagParser.parse("sure. [REMEMBER:likes tea]")
        #expect(result.textWithoutMemoryTags == "sure.")
        #expect(result.rememberedFacts == [RememberedFact(sectionName: "", factText: "likes tea")])
    }

    @Test func aColonInASectionlessFactIsNotTakenAsASection() {
        let result = MemoryTagParser.parse("[REMEMBER:meeting at 10:30 with alan]")
        #expect(result.rememberedFacts == [RememberedFact(sectionName: "", factText: "meeting at 10:30 with alan")])
        let sectioned = MemoryTagParser.parse("[REMEMBER:notes:meeting at 10:30 with alan]")
        #expect(sectioned.rememberedFacts == [RememberedFact(sectionName: "notes", factText: "meeting at 10:30 with alan")])
    }

    @Test func newlinesInsideAFactBecomeSpaces() {
        let result = MemoryTagParser.parse("ok. [REMEMBER:Tools:uses zed\nand vim] [FORGET:the\ncat]")
        #expect(result.rememberedFacts == [RememberedFact(sectionName: "Tools", factText: "uses zed and vim")])
        #expect(result.forgetRequests == ["the cat"])
    }

    @Test func unterminatedTagIsCutToTheEndOfTheText() {
        let result = MemoryTagParser.parse("noted. [REMEMBER:Tools:uses zed")
        #expect(result.textWithoutMemoryTags == "noted.")
        #expect(result.rememberedFacts == [RememberedFact(sectionName: "Tools", factText: "uses zed")])
    }

    @Test func emptyFactsAndEmptyForgetsAreDropped() {
        let result = MemoryTagParser.parse("ok [REMEMBER:Tools: ] [FORGET: ] fine")
        #expect(result.textWithoutMemoryTags == "ok fine")
        #expect(result.rememberedFacts.isEmpty)
        #expect(result.forgetRequests.isEmpty)
    }
}
