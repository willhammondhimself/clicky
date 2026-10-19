//
//  OllamaNativeEndpoints.swift
//  leanring-buddy
//
//  Pure helpers for Ollama's native HTTP API (/api/tags, /api/pull,
//  /api/embed, /api/generate, /api/chat): URL derivation, request bodies and response
//  parsing. No networking here so the whole file is unit-tested in the
//  terminal harness; OllamaNativeClient does the URLSession calls.
//
//  The configured chat base URL is the OpenAI-compatible one
//  (`http://127.0.0.1:11434/v1`); the native API lives one level up.
//

import Foundation

nonisolated enum OllamaNativeEndpoints {
    enum ResponseError: Error, Equatable {
        case malformedResponse(description: String)
        case serverError(message: String)
    }

    enum PullProgressEvent: Equatable, Sendable {
        case progress(status: String, fractionCompleted: Double?)
        case success
        case failure(message: String)
    }

    // MARK: - URLs

    /// `http://127.0.0.1:11434/v1/` → `http://127.0.0.1:11434`. Nil when the
    /// string is not a URL with a host.
    static func nativeBaseURL(fromOpenAICompatibleBaseURL openAICompatibleBaseURL: String) -> URL? {
        var baseString = openAICompatibleBaseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        while baseString.hasSuffix("/") {
            baseString.removeLast()
        }
        if baseString.hasSuffix("/v1") {
            baseString.removeLast(3)
        }
        guard let url = URL(string: baseString), url.host != nil else { return nil }
        return url
    }

    static func tagsURL(nativeBaseURL: URL) -> URL {
        nativeBaseURL.appendingPathComponent("api/tags")
    }

    static func pullURL(nativeBaseURL: URL) -> URL {
        nativeBaseURL.appendingPathComponent("api/pull")
    }

    static func embedURL(nativeBaseURL: URL) -> URL {
        nativeBaseURL.appendingPathComponent("api/embed")
    }

    static func generateURL(nativeBaseURL: URL) -> URL {
        nativeBaseURL.appendingPathComponent("api/generate")
    }

    static func chatURL(nativeBaseURL: URL) -> URL {
        nativeBaseURL.appendingPathComponent("api/chat")
    }

    // MARK: - Model names

    /// Ollama lists a model pulled as `embeddinggemma` under
    /// `embeddinggemma:latest`; compare both sides in that form.
    static func normalizedModelName(_ modelName: String) -> String {
        let trimmedModelName = modelName.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmedModelName.contains(":") ? trimmedModelName : trimmedModelName + ":latest"
    }

    static func installedModelNames(fromTagsResponse responseData: Data) throws -> Set<String> {
        let topLevel = try jsonDictionary(from: responseData)
        guard let models = topLevel["models"] as? [[String: Any]] else {
            throw ResponseError.malformedResponse(description: "tags response has no models array")
        }
        let modelNames = models.compactMap { $0["name"] as? String }.map(normalizedModelName)
        return Set(modelNames)
    }

    // MARK: - Request bodies

    /// Both `model` (current) and `name` (older servers) so every Ollama
    /// version accepts it.
    static func pullRequestBody(modelName: String) -> Data {
        encodeBody(["model": modelName, "name": modelName, "stream": true])
    }

    static func embedRequestBody(modelName: String, texts: [String]) -> Data {
        encodeBody(["model": modelName, "input": texts, "keep_alive": -1])
    }

    /// Non-streaming, thinking disabled, low temperature, short output: the
    /// shape used for the daily-note summariser. `includesThinkFlag` is false
    /// on the retry after a model rejects the `think` key with HTTP 400.
    /// No `num_ctx`: the summariser is the already-loaded chat model, and a
    /// context that differs from the one it was loaded with makes Ollama
    /// reload it.
    static func generateRequestBody(
        modelName: String,
        systemPrompt: String,
        userPrompt: String,
        includesThinkFlag: Bool
    ) -> Data {
        var body: [String: Any] = [
            "model": modelName,
            "system": systemPrompt,
            "prompt": userPrompt,
            "stream": false,
            "keep_alive": -1,
            "options": ["temperature": 0.1, "num_predict": 60],
        ]
        if includesThinkFlag {
            body["think"] = false
        }
        return encodeBody(body)
    }

    /// One screenshot and one question for a vision model on /api/chat, the
    /// shape precise pointing was benchmarked with: non-streaming, thinking
    /// off, deterministic, a few tokens out. `num_ctx` 4096 keeps the model's
    /// resident size down (Ollama's default 32k context made the 4B model 8 GB).
    static func imageChatRequestBody(
        modelName: String,
        systemPrompt: String,
        userText: String,
        jpegImageData: Data
    ) -> Data {
        encodeBody([
            "model": modelName,
            "messages": [
                ["role": "system", "content": systemPrompt],
                ["role": "user", "content": userText, "images": [jpegImageData.base64EncodedString()]],
            ],
            "stream": false,
            "think": false,
            "keep_alive": -1,
            "options": ["temperature": 0, "num_predict": 40, "num_ctx": imageChatContextLength],
        ])
    }

    private static let imageChatContextLength = 4096

    /// Loads the image-chat model and pins it, without asking anything (an
    /// empty messages array only loads). Same `num_ctx` as
    /// `imageChatRequestBody`: Ollama reloads a model whose context changes,
    /// so a preload with its default context would be thrown away by the
    /// first real request.
    static func imageChatModelLoadRequestBody(modelName: String) -> Data {
        encodeBody([
            "model": modelName,
            "messages": [[String: Any]](),
            "stream": false,
            "keep_alive": -1,
            "options": ["num_ctx": imageChatContextLength],
        ])
    }

    /// Unloads a model from memory without deleting it from disk: /api/generate
    /// with no prompt and keep_alive 0. Ollama answers `done_reason: unload`
    /// at once, and for a model that isn't loaded it does nothing (it does
    /// not load it first; checked on 0.34.4). A missing model is HTTP 404.
    static func unloadRequestBody(modelName: String) -> Data {
        encodeBody(["model": modelName, "keep_alive": 0, "stream": false])
    }

    // MARK: - Pull stream

    /// One newline-delimited JSON line of the /api/pull stream. Nil for blank
    /// or unparseable lines (the stream is best-effort progress reporting).
    static func pullProgressEvent(fromStreamLine streamLine: String) -> PullProgressEvent? {
        let trimmedLine = streamLine.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedLine.isEmpty,
              let lineObject = try? JSONSerialization.jsonObject(with: Data(trimmedLine.utf8)) as? [String: Any] else {
            return nil
        }
        if let errorMessage = lineObject["error"] as? String {
            return .failure(message: errorMessage)
        }
        guard let status = lineObject["status"] as? String else { return nil }
        if status == "success" {
            return .success
        }

        var fractionCompleted: Double?
        if let totalBytes = lineObject["total"] as? Double,
           let completedBytes = lineObject["completed"] as? Double,
           totalBytes > 0 {
            fractionCompleted = min(1.0, max(0.0, completedBytes / totalBytes))
        }
        return .progress(status: status, fractionCompleted: fractionCompleted)
    }

    // MARK: - Embed / generate responses

    static func embeddings(fromEmbedResponse responseData: Data) throws -> [[Float]] {
        let topLevel = try jsonDictionary(from: responseData)
        try throwIfServerError(topLevel)
        guard let embeddings = topLevel["embeddings"] as? [[Double]] else {
            throw ResponseError.malformedResponse(description: "embed response has no embeddings array")
        }
        return embeddings.map { $0.map(Float.init) }
    }

    static func generatedText(fromGenerateResponse responseData: Data) throws -> String {
        let topLevel = try jsonDictionary(from: responseData)
        try throwIfServerError(topLevel)
        guard let generatedText = topLevel["response"] as? String else {
            throw ResponseError.malformedResponse(description: "generate response has no response field")
        }
        return generatedText
    }

    static func chatMessageContent(fromChatResponse responseData: Data) throws -> String {
        let topLevel = try jsonDictionary(from: responseData)
        try throwIfServerError(topLevel)
        guard let message = topLevel["message"] as? [String: Any],
              let messageContent = message["content"] as? String else {
            throw ResponseError.malformedResponse(description: "chat response has no message content")
        }
        return messageContent
    }

    // MARK: - Private

    private static func jsonDictionary(from responseData: Data) throws -> [String: Any] {
        guard let topLevel = try? JSONSerialization.jsonObject(with: responseData) as? [String: Any] else {
            throw ResponseError.malformedResponse(description: "response is not a JSON object")
        }
        return topLevel
    }

    private static func throwIfServerError(_ topLevel: [String: Any]) throws {
        if let errorMessage = topLevel["error"] as? String {
            throw ResponseError.serverError(message: errorMessage)
        }
    }

    private static func encodeBody(_ body: [String: Any]) -> Data {
        // The bodies are built from literals above, so serialisation cannot fail.
        (try? JSONSerialization.data(withJSONObject: body)) ?? Data()
    }
}
