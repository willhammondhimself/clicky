//
//  OllamaNativeClient.swift
//  leanring-buddy
//
//  Thin URLSession wrapper over Ollama's native API for the memory feature:
//  list installed models, pull one with progress, embed texts, generate a
//  short completion. URL building and parsing live in OllamaNativeEndpoints
//  (unit-tested); this file is only the I/O.
//

import Foundation

final class OllamaNativeClient {
    struct HTTPStatusError: LocalizedError {
        let statusCode: Int
        let responseBody: String

        var errorDescription: String? { "ollama returned HTTP \(statusCode): \(responseBody.prefix(200))" }
    }

    let nativeBaseURL: URL
    private let urlSession = URLSession.shared

    init(nativeBaseURL: URL) {
        self.nativeBaseURL = nativeBaseURL
    }

    /// Names in `OllamaNativeEndpoints.normalizedModelName` form. Throws on
    /// connection failure, which the provisioner reports as "unreachable".
    func listInstalledModelNames() async throws -> Set<String> {
        var request = URLRequest(url: OllamaNativeEndpoints.tagsURL(nativeBaseURL: nativeBaseURL))
        request.timeoutInterval = 5
        let responseData = try await perform(request)
        return try OllamaNativeEndpoints.installedModelNames(fromTagsResponse: responseData)
    }

    /// Streams /api/pull, reporting the current layer's fraction. Returns on
    /// the `success` line; throws on an `error` line or transport failure.
    func pullModel(named modelName: String, onProgress: @MainActor (Double?) -> Void) async throws {
        var request = URLRequest(url: OllamaNativeEndpoints.pullURL(nativeBaseURL: nativeBaseURL))
        request.httpMethod = "POST"
        request.timeoutInterval = 3600
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = OllamaNativeEndpoints.pullRequestBody(modelName: modelName)

        let (byteStream, response) = try await urlSession.bytes(for: request)
        let statusCode = (response as? HTTPURLResponse)?.statusCode ?? -1
        guard (200...299).contains(statusCode) else {
            throw HTTPStatusError(statusCode: statusCode, responseBody: "")
        }

        for try await streamLine in byteStream.lines {
            guard let event = OllamaNativeEndpoints.pullProgressEvent(fromStreamLine: streamLine) else { continue }
            switch event {
            case .progress(_, let fractionCompleted):
                await onProgress(fractionCompleted)
            case .success:
                await onProgress(1.0)
                return
            case .failure(let message):
                throw OllamaNativeEndpoints.ResponseError.serverError(message: message)
            }
        }
    }

    func embed(texts: [String], model modelName: String) async throws -> [[Float]] {
        guard !texts.isEmpty else { return [] }
        var request = URLRequest(url: OllamaNativeEndpoints.embedURL(nativeBaseURL: nativeBaseURL))
        request.httpMethod = "POST"
        request.timeoutInterval = 15
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = OllamaNativeEndpoints.embedRequestBody(modelName: modelName, texts: texts)
        let responseData = try await perform(request)
        return try OllamaNativeEndpoints.embeddings(fromEmbedResponse: responseData)
    }

    /// Non-streaming completion with thinking off. Some models reject the
    /// `think` key with HTTP 400; one retry without it covers those.
    func generate(model modelName: String, systemPrompt: String, userPrompt: String) async throws -> String {
        do {
            return try await generateOnce(model: modelName, systemPrompt: systemPrompt, userPrompt: userPrompt, includesThinkFlag: true)
        } catch let statusError as HTTPStatusError where statusError.statusCode == 400 {
            return try await generateOnce(model: modelName, systemPrompt: systemPrompt, userPrompt: userPrompt, includesThinkFlag: false)
        }
    }

    // MARK: - Private

    private func generateOnce(model modelName: String, systemPrompt: String, userPrompt: String, includesThinkFlag: Bool) async throws -> String {
        var request = URLRequest(url: OllamaNativeEndpoints.generateURL(nativeBaseURL: nativeBaseURL))
        request.httpMethod = "POST"
        request.timeoutInterval = 60
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = OllamaNativeEndpoints.generateRequestBody(
            modelName: modelName,
            systemPrompt: systemPrompt,
            userPrompt: userPrompt,
            includesThinkFlag: includesThinkFlag
        )
        let responseData = try await perform(request)
        return try OllamaNativeEndpoints.generatedText(fromGenerateResponse: responseData)
    }

    private func perform(_ request: URLRequest) async throws -> Data {
        let (responseData, response) = try await urlSession.data(for: request)
        let statusCode = (response as? HTTPURLResponse)?.statusCode ?? -1
        guard (200...299).contains(statusCode) else {
            throw HTTPStatusError(statusCode: statusCode, responseBody: String(decoding: responseData, as: UTF8.self))
        }
        return responseData
    }
}
