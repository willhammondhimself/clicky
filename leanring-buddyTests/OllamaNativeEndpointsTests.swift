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
