//
//  OpenAICompatibleChatClient.swift
//  leanring-buddy
//
//  Streaming vision chat against any server that speaks the OpenAI
//  `/chat/completions` API: OpenRouter, Ollama, LM Studio, vLLM, etc.
//  Images travel as base64 data-URI `image_url` parts, which all of those
//  accept.
//

import Foundation

final class OpenAICompatibleChatClient: ChatClient {
    private let chatCompletionsURL: URL
    private let apiKey: String?
    private let extraHeaders: [String: String]
    private let disablesModelThinking: Bool
    private let session: URLSession
    var model: String

    /// - Parameters:
    ///   - baseURL: e.g. `https://openrouter.ai/api/v1` or `http://localhost:11434/v1`.
    ///     `/chat/completions` is appended here.
    ///   - apiKey: sent as a Bearer token when present. Ollama needs none.
    ///   - disablesModelThinking: sends `reasoning_effort: "none"`. Needed for
    ///     Ollama, where models like gemma4 think by default and otherwise spend
    ///     the whole `max_tokens` budget reasoning and return empty text. Not
    ///     sent to other providers, some of which reject the value.
    init(
        baseURL: String,
        apiKey: String?,
        model: String,
        extraHeaders: [String: String] = [:],
        disablesModelThinking: Bool = false
    ) {
        let trimmedBaseURL = baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        let baseURLWithoutTrailingSlash = trimmedBaseURL.hasSuffix("/")
            ? String(trimmedBaseURL.dropLast())
            : trimmedBaseURL
        self.chatCompletionsURL = URL(string: baseURLWithoutTrailingSlash + "/chat/completions")
            ?? URL(string: "http://localhost:11434/v1/chat/completions")!
        self.apiKey = apiKey
        self.model = model
        self.extraHeaders = extraHeaders
        self.disablesModelThinking = disablesModelThinking

        // Same session tuning as ClaudeAPI: keep TLS tickets cached so large
        // image payloads don't hit cold-handshake failures, but never cache
        // responses on disk.
        let configuration = URLSessionConfiguration.default
        configuration.timeoutIntervalForRequest = 120
        configuration.timeoutIntervalForResource = 300
        configuration.waitsForConnectivity = true
        configuration.urlCache = nil
        configuration.httpCookieStorage = nil
        self.session = URLSession(configuration: configuration)
    }

    private func makeAPIRequest() -> URLRequest {
        var request = URLRequest(url: chatCompletionsURL)
        request.httpMethod = "POST"
        request.timeoutInterval = 120
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("text/event-stream", forHTTPHeaderField: "Accept")
        if let apiKey {
            request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        }
        for (headerName, headerValue) in extraHeaders {
            request.setValue(headerValue, forHTTPHeaderField: headerName)
        }
        return request
    }

    private func detectImageMediaType(for imageData: Data) -> String {
        let pngSignature: [UInt8] = [0x89, 0x50, 0x4E, 0x47]
        if imageData.count >= 4, [UInt8](imageData.prefix(4)) == pngSignature {
            return "image/png"
        }
        return "image/jpeg"
    }

    func analyzeImageStreaming(
        images: [(data: Data, label: String)],
        systemPrompt: String,
        conversationHistory: [(userPlaceholder: String, assistantResponse: String)],
        userPrompt: String,
        onTextChunk: @MainActor @Sendable (String) -> Void
    ) async throws -> (text: String, duration: TimeInterval) {
        let startTime = Date()

        var messages: [[String: Any]] = [
            ["role": "system", "content": systemPrompt]
        ]

        for (userPlaceholder, assistantResponse) in conversationHistory {
            messages.append(["role": "user", "content": userPlaceholder])
            messages.append(["role": "assistant", "content": assistantResponse])
        }

        var userContentParts: [[String: Any]] = []
        for image in images {
            let mediaType = detectImageMediaType(for: image.data)
            let dataURI = "data:\(mediaType);base64," + image.data.base64EncodedString()
            userContentParts.append([
                "type": "image_url",
                "image_url": ["url": dataURI]
            ])
            userContentParts.append([
                "type": "text",
                "text": image.label
            ])
        }
        userContentParts.append([
            "type": "text",
            "text": userPrompt
        ])
        messages.append(["role": "user", "content": userContentParts])

        var body: [String: Any] = [
            "model": model,
            "max_tokens": 1024,
            "stream": true,
            "messages": messages
        ]
        if disablesModelThinking {
            body["reasoning_effort"] = "none"
        }

        var request = makeAPIRequest()
        let bodyData = try JSONSerialization.data(withJSONObject: body)
        request.httpBody = bodyData
        let payloadMB = Double(bodyData.count) / 1_048_576.0
        print("🌐 Chat streaming request → \(chatCompletionsURL.host ?? "?") [\(model)]: \(String(format: "%.1f", payloadMB))MB, \(images.count) image(s)")

        let (byteStream, response) = try await session.bytes(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw NSError(
                domain: "OpenAICompatibleChatClient",
                code: -1,
                userInfo: [NSLocalizedDescriptionKey: "Invalid HTTP response"]
            )
        }

        guard (200...299).contains(httpResponse.statusCode) else {
            var errorBodyChunks: [String] = []
            for try await line in byteStream.lines {
                errorBodyChunks.append(line)
            }
            let errorBody = errorBodyChunks.joined(separator: "\n")
            throw NSError(
                domain: "OpenAICompatibleChatClient",
                code: httpResponse.statusCode,
                userInfo: [NSLocalizedDescriptionKey: "API Error (\(httpResponse.statusCode)): \(errorBody)"]
            )
        }

        // SSE: each event is "data: {json}", terminated by "data: [DONE]".
        // The text lives at choices[0].delta.content. Some servers (OpenRouter)
        // also emit ": OPENROUTER PROCESSING" keep-alive comments — skipped
        // because they lack the "data: " prefix.
        var accumulatedResponseText = ""

        for try await line in byteStream.lines {
            guard line.hasPrefix("data: ") else { continue }
            let jsonString = String(line.dropFirst(6))
            guard jsonString != "[DONE]" else { break }

            guard let jsonData = jsonString.data(using: .utf8),
                  let eventPayload = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any] else {
                continue
            }

            // Providers surface mid-stream failures as an "error" object
            // instead of an HTTP status, so check for it on every event.
            if let errorPayload = eventPayload["error"] as? [String: Any] {
                let errorMessage = errorPayload["message"] as? String ?? "\(errorPayload)"
                throw NSError(
                    domain: "OpenAICompatibleChatClient",
                    code: -2,
                    userInfo: [NSLocalizedDescriptionKey: "API stream error: \(errorMessage)"]
                )
            }

            guard let choices = eventPayload["choices"] as? [[String: Any]],
                  let firstChoice = choices.first,
                  let delta = firstChoice["delta"] as? [String: Any],
                  let textChunk = delta["content"] as? String,
                  !textChunk.isEmpty else {
                continue
            }

            accumulatedResponseText += textChunk
            let currentAccumulatedText = accumulatedResponseText
            await onTextChunk(currentAccumulatedText)
        }

        let duration = Date().timeIntervalSince(startTime)
        return (text: accumulatedResponseText, duration: duration)
    }
}
