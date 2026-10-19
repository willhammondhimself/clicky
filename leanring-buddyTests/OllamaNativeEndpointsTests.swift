import Foundation
import Testing

#if canImport(leanring_buddy)
@testable import leanring_buddy
#else
@testable import LumenLogic
#endif

struct OllamaNativeEndpointsTests {

    // MARK: - Base URL derivation

    @Test func stripsVersionOnePathAndTrailingSlashes() {
        let nativeBaseURL = OllamaNativeEndpoints.nativeBaseURL(fromOpenAICompatibleBaseURL: "http://127.0.0.1:11434/v1/")
        #expect(nativeBaseURL?.absoluteString == "http://127.0.0.1:11434")
    }

    @Test func leavesABaseURLWithoutVersionOneAlone() {
        let nativeBaseURL = OllamaNativeEndpoints.nativeBaseURL(fromOpenAICompatibleBaseURL: "http://localhost:11434")
        #expect(nativeBaseURL?.absoluteString == "http://localhost:11434")
    }

    @Test func rejectsGarbage() {
        #expect(OllamaNativeEndpoints.nativeBaseURL(fromOpenAICompatibleBaseURL: "   ") == nil)
        #expect(OllamaNativeEndpoints.nativeBaseURL(fromOpenAICompatibleBaseURL: "not a url at all") == nil)
    }

    @Test func buildsTheFourEndpointURLs() throws {
        let nativeBaseURL = try #require(OllamaNativeEndpoints.nativeBaseURL(fromOpenAICompatibleBaseURL: "http://127.0.0.1:11434/v1"))
        #expect(OllamaNativeEndpoints.tagsURL(nativeBaseURL: nativeBaseURL).absoluteString == "http://127.0.0.1:11434/api/tags")
        #expect(OllamaNativeEndpoints.pullURL(nativeBaseURL: nativeBaseURL).absoluteString == "http://127.0.0.1:11434/api/pull")
        #expect(OllamaNativeEndpoints.embedURL(nativeBaseURL: nativeBaseURL).absoluteString == "http://127.0.0.1:11434/api/embed")
        #expect(OllamaNativeEndpoints.generateURL(nativeBaseURL: nativeBaseURL).absoluteString == "http://127.0.0.1:11434/api/generate")
        #expect(OllamaNativeEndpoints.chatURL(nativeBaseURL: nativeBaseURL).absoluteString == "http://127.0.0.1:11434/api/chat")
    }

    // MARK: - Model names

    @Test func normalizesABareModelNameToLatest() {
        #expect(OllamaNativeEndpoints.normalizedModelName("embeddinggemma") == "embeddinggemma:latest")
        #expect(OllamaNativeEndpoints.normalizedModelName("gemma4:e2b") == "gemma4:e2b")
        #expect(OllamaNativeEndpoints.normalizedModelName("  gemma4:e2b \n") == "gemma4:e2b")
    }

    @Test func parsesInstalledModelNamesFromTagsResponse() throws {
        let tagsResponse = Data("""
        {"models":[{"name":"embeddinggemma:latest","model":"embeddinggemma:latest","size":621}, {"name":"gemma4:26b","model":"gemma4:26b","size":1}]}
        """.utf8)
        let installedModelNames = try OllamaNativeEndpoints.installedModelNames(fromTagsResponse: tagsResponse)
        #expect(installedModelNames.contains("embeddinggemma:latest"))
        #expect(installedModelNames.contains("gemma4:26b"))
        #expect(installedModelNames.count == 2)
    }

    @Test func tagsResponseWithoutModelsArrayIsAnError() {
        #expect(throws: OllamaNativeEndpoints.ResponseError.self) {
            try OllamaNativeEndpoints.installedModelNames(fromTagsResponse: Data("{\"nope\":1}".utf8))
        }
    }

    // MARK: - Request bodies

    private func jsonObject(from body: Data) throws -> [String: Any] {
        try #require(JSONSerialization.jsonObject(with: body) as? [String: Any])
    }

    @Test func pullBodyNamesTheModelBothWaysAndStreams() throws {
        let body = try jsonObject(from: OllamaNativeEndpoints.pullRequestBody(modelName: "embeddinggemma"))
        #expect(body["model"] as? String == "embeddinggemma")
        #expect(body["name"] as? String == "embeddinggemma")
        #expect(body["stream"] as? Bool == true)
    }

    @Test func embedBodyCarriesAllTextsAndPinsTheModel() throws {
        let body = try jsonObject(from: OllamaNativeEndpoints.embedRequestBody(modelName: "embeddinggemma", texts: ["a", "b"]))
        #expect(body["model"] as? String == "embeddinggemma")
        #expect(body["input"] as? [String] == ["a", "b"])
        #expect(body["keep_alive"] as? Int == -1)
    }

    @Test func generateBodyIsNonStreamingWithThinkingOffAndLowTemperature() throws {
        let body = try jsonObject(from: OllamaNativeEndpoints.generateRequestBody(
            modelName: "gemma4:e2b",
            systemPrompt: "sys",
            userPrompt: "user",
            includesThinkFlag: true
        ))
        #expect(body["model"] as? String == "gemma4:e2b")
        #expect(body["system"] as? String == "sys")
        #expect(body["prompt"] as? String == "user")
        #expect(body["stream"] as? Bool == false)
        #expect(body["think"] as? Bool == false)
        #expect(body["keep_alive"] as? Int == -1)
        let options = try #require(body["options"] as? [String: Any])
        #expect((options["temperature"] as? Double) == 0.1)
        #expect(options["num_predict"] as? Int == 60)
    }

    @Test func generateBodyCanOmitTheThinkFlagForModelsThatRejectIt() throws {
        let body = try jsonObject(from: OllamaNativeEndpoints.generateRequestBody(
            modelName: "gemma4:e2b",
            systemPrompt: "sys",
            userPrompt: "user",
            includesThinkFlag: false
        ))
        #expect(body["think"] == nil)
    }

    @Test func imageChatBodyCarriesOneBase64ImageWithDeterministicShortOutput() throws {
        let jpegImageData = Data([0xFF, 0xD8, 0xFF, 0xE0, 0x00, 0x10])
        let body = try jsonObject(from: OllamaNativeEndpoints.imageChatRequestBody(
            modelName: "qwen3-vl:4b-instruct",
            systemPrompt: "sys",
            userText: "point at the element for: save button",
            jpegImageData: jpegImageData
        ))
        #expect(body["model"] as? String == "qwen3-vl:4b-instruct")
        #expect(body["stream"] as? Bool == false)
        #expect(body["think"] as? Bool == false)
        #expect(body["keep_alive"] as? Int == -1)

        let messages = try #require(body["messages"] as? [[String: Any]])
        #expect(messages.count == 2)
        #expect(messages[0]["role"] as? String == "system")
        #expect(messages[0]["content"] as? String == "sys")
        #expect(messages[0]["images"] == nil)
        #expect(messages[1]["role"] as? String == "user")
        #expect(messages[1]["content"] as? String == "point at the element for: save button")
        #expect(messages[1]["images"] as? [String] == [jpegImageData.base64EncodedString()])

        let options = try #require(body["options"] as? [String: Any])
        #expect(options["temperature"] as? Int == 0)
        #expect(options["num_predict"] as? Int == 40)
        // Ollama's default 32k context made the 4B model 8 GB resident.
        #expect(options["num_ctx"] as? Int == 4096)
    }

    @Test func parsesChatMessageContent() throws {
        let response = Data("""
        {"model":"qwen3-vl:4b-instruct","created_at":"2026-10-19T12:00:00Z","message":{"role":"assistant","content":"[POINT:512,87]"},"done":true}
        """.utf8)
        #expect(try OllamaNativeEndpoints.chatMessageContent(fromChatResponse: response) == "[POINT:512,87]")
    }

    @Test func chatResponseWithoutMessageContentIsAnError() {
        #expect(throws: OllamaNativeEndpoints.ResponseError.self) {
            try OllamaNativeEndpoints.chatMessageContent(fromChatResponse: Data("{\"done\":true}".utf8))
        }
        #expect(throws: OllamaNativeEndpoints.ResponseError.serverError(message: "model \"qwen3-vl:4b-instruct\" not found, try pulling it first")) {
            try OllamaNativeEndpoints.chatMessageContent(fromChatResponse: Data("{\"error\":\"model \\\"qwen3-vl:4b-instruct\\\" not found, try pulling it first\"}".utf8))
        }
    }

    // MARK: - Pull stream

    @Test func parsesPullProgressLines() {
        #expect(OllamaNativeEndpoints.pullProgressEvent(fromStreamLine: "{\"status\":\"pulling manifest\"}")
                == .progress(status: "pulling manifest", fractionCompleted: nil))
        #expect(OllamaNativeEndpoints.pullProgressEvent(fromStreamLine: "{\"status\":\"pulling abc\",\"digest\":\"sha256:abc\",\"total\":200,\"completed\":50}")
                == .progress(status: "pulling abc", fractionCompleted: 0.25))
        #expect(OllamaNativeEndpoints.pullProgressEvent(fromStreamLine: "{\"status\":\"success\"}") == .success)
        #expect(OllamaNativeEndpoints.pullProgressEvent(fromStreamLine: "{\"error\":\"pull model manifest: file does not exist\"}")
                == .failure(message: "pull model manifest: file does not exist"))
    }

    @Test func pullProgressClampsAndIgnoresBlankOrBrokenLines() {
        #expect(OllamaNativeEndpoints.pullProgressEvent(fromStreamLine: "") == nil)
        #expect(OllamaNativeEndpoints.pullProgressEvent(fromStreamLine: "   ") == nil)
        #expect(OllamaNativeEndpoints.pullProgressEvent(fromStreamLine: "{not json") == nil)
        #expect(OllamaNativeEndpoints.pullProgressEvent(fromStreamLine: "{\"status\":\"x\",\"total\":10,\"completed\":50}")
                == .progress(status: "x", fractionCompleted: 1.0))
        #expect(OllamaNativeEndpoints.pullProgressEvent(fromStreamLine: "{\"status\":\"x\",\"total\":0,\"completed\":0}")
                == .progress(status: "x", fractionCompleted: nil))
    }

    // MARK: - Embed / generate responses

    @Test func parsesEmbeddings() throws {
        let response = Data("{\"model\":\"embeddinggemma\",\"embeddings\":[[0.5,-0.25],[1,2]]}".utf8)
        let embeddings = try OllamaNativeEndpoints.embeddings(fromEmbedResponse: response)
        #expect(embeddings == [[0.5, -0.25], [1, 2]])
    }

    @Test func embedErrorObjectIsSurfacedAsServerError() {
        let response = Data("{\"error\":\"This server does not support embeddings.\"}".utf8)
        #expect(throws: OllamaNativeEndpoints.ResponseError.serverError(message: "This server does not support embeddings.")) {
            try OllamaNativeEndpoints.embeddings(fromEmbedResponse: response)
        }
    }

    @Test func parsesGeneratedText() throws {
        let response = Data("{\"model\":\"gemma4:e2b\",\"response\":\"asked about x\",\"done\":true}".utf8)
        #expect(try OllamaNativeEndpoints.generatedText(fromGenerateResponse: response) == "asked about x")
    }

    @Test func generateErrorObjectIsSurfacedAsServerError() {
        let response = Data("{\"error\":\"model not found\"}".utf8)
        #expect(throws: OllamaNativeEndpoints.ResponseError.serverError(message: "model not found")) {
            try OllamaNativeEndpoints.generatedText(fromGenerateResponse: response)
        }
    }
}
