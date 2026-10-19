import Foundation
import Testing

#if canImport(leanring_buddy)
@testable import leanring_buddy
#else
@testable import LumenLogic
#endif

struct DailyNoteSummarizerTests {

    @Test func userPromptCarriesTheAppQuestionAndReply() {
        let prompt = DailyNoteSummarizer.userPrompt(question: "how do i save", spokenReply: "cmd s, top left.", applicationName: "Xcode")
        #expect(prompt.contains("Xcode"))
        #expect(prompt.contains("how do i save"))
        #expect(prompt.contains("cmd s, top left."))
        #expect(!DailyNoteSummarizer.systemPrompt.isEmpty)
    }

    @Test func sanitizedSummaryTakesTheFirstNonEmptyLineAndStripsDecoration() {
        #expect(DailyNoteSummarizer.sanitizedSummary(fromModelOutput: "\n\n- \"asked how to save\"\nsecond line") == "asked how to save")
        #expect(DailyNoteSummarizer.sanitizedSummary(fromModelOutput: "* asked [REMEMBER:x:y] how · to save") == "asked how - to save")
        #expect(DailyNoteSummarizer.sanitizedSummary(fromModelOutput: "Summary: asked how to save") == "asked how to save")
    }

    @Test func sanitizedSummaryIsCappedAndNilWhenEmpty() {
        let longOutput = String(repeating: "a", count: 500)
        #expect(DailyNoteSummarizer.sanitizedSummary(fromModelOutput: longOutput)?.count == DailyNoteSummarizer.maximumSummaryLength)
        #expect(DailyNoteSummarizer.sanitizedSummary(fromModelOutput: "   \n  ") == nil)
        #expect(DailyNoteSummarizer.sanitizedSummary(fromModelOutput: "[REMEMBER:a:b]") == nil)
    }

    // The summary is written by the chat model itself when it is a local
    // Ollama model: Ollama keeps at most 3 models loaded, so a separate
    // summariser model would evict embeddinggemma before the next reply.
    @Test func summaryModelIsTheOllamaChatModelTrimmed() {
        #expect(DailyNoteSummarizer.summaryModelName(isChatProviderOllama: true, chatModelName: "gemma4:26b") == "gemma4:26b")
        #expect(DailyNoteSummarizer.summaryModelName(isChatProviderOllama: true, chatModelName: "  qwen3.6:35b \n") == "qwen3.6:35b")
    }

    @Test func noSummaryModelWhenTheOllamaChatModelNameIsBlank() {
        #expect(DailyNoteSummarizer.summaryModelName(isChatProviderOllama: true, chatModelName: "") == nil)
        #expect(DailyNoteSummarizer.summaryModelName(isChatProviderOllama: true, chatModelName: "  \n ") == nil)
    }

    @Test func noSummaryModelForCloudChatProvidersSoNoExtraLocalModelLoads() {
        #expect(DailyNoteSummarizer.summaryModelName(isChatProviderOllama: false, chatModelName: "claude-haiku-5-5") == nil)
        #expect(DailyNoteSummarizer.summaryModelName(isChatProviderOllama: false, chatModelName: "gemma4:26b") == nil)
        #expect(DailyNoteSummarizer.summaryModelName(isChatProviderOllama: false, chatModelName: "") == nil)
    }

    @Test func rawFallbackJoinsTheQuestionAndFirstSentence() {
        #expect(DailyNoteSummarizer.rawFallbackSummary(question: "how do i save", spokenReply: "cmd s, top left. then close.") == "how do i save → cmd s, top left.")
        #expect(DailyNoteSummarizer.rawFallbackSummary(question: "how do i save", spokenReply: "   ") == "how do i save")
        #expect(DailyNoteSummarizer.rawFallbackSummary(question: "a · b\nc", spokenReply: "") == "a - b c")
    }
}
