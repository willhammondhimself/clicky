//
//  ChatClient.swift
//  leanring-buddy
//
//  Common surface for the vision-chat backends (Anthropic Messages API and
//  any OpenAI-compatible endpoint such as OpenRouter or Ollama) so
//  CompanionManager doesn't care which one is configured.
//

import Foundation

protocol ChatClient: AnyObject {
    var model: String { get set }

    /// Sends labeled screenshots + the user's transcript and streams the reply.
    /// `onTextChunk` receives the accumulated text so far on every delta.
    func analyzeImageStreaming(
        images: [(data: Data, label: String)],
        systemPrompt: String,
        conversationHistory: [(userPlaceholder: String, assistantResponse: String)],
        userPrompt: String,
        onTextChunk: @MainActor @Sendable (String) -> Void
    ) async throws -> (text: String, duration: TimeInterval)
}

extension ChatClient {
    /// Convenience overload for callers with no prior conversation (e.g. the
    /// onboarding demo). Protocols can't declare default arguments.
    func analyzeImageStreaming(
        images: [(data: Data, label: String)],
        systemPrompt: String,
        userPrompt: String,
        onTextChunk: @MainActor @Sendable (String) -> Void
    ) async throws -> (text: String, duration: TimeInterval) {
        try await analyzeImageStreaming(
            images: images,
            systemPrompt: systemPrompt,
            conversationHistory: [],
            userPrompt: userPrompt,
            onTextChunk: onTextChunk
        )
    }
}

/// Builds the right client for the current settings. Called whenever the
/// provider, base URL, or model changes.
enum ChatClientFactory {
    @MainActor
    static func makeClient(from appSettings: AppSettings) -> any ChatClient {
        let providerKind = appSettings.chatProviderKind
        let apiKey = providerKind.secretKey.flatMap(SecretsStore.read)

        switch providerKind {
        case .anthropicDirect:
            return ClaudeAPI(apiKey: apiKey, model: appSettings.chatModel)

        case .openRouter, .ollama, .custom:
            if providerKind == .ollama {
                // Load the model now and keep it resident so the first
                // question isn't stuck behind a cold model load.
                OllamaModelWarmer.preloadAndPin(
                    openAICompatibleBaseURL: appSettings.chatBaseURL,
                    model: appSettings.chatModel
                )
            }

            // OpenRouter asks for these so usage shows up under your app name
            // in their dashboard. Harmless for other providers, so only set
            // them where they mean something.
            var extraHeaders: [String: String] = [:]
            if providerKind == .openRouter {
                extraHeaders["HTTP-Referer"] = "https://github.com/willhammondhimself/clicky"
                extraHeaders["X-Title"] = "Lumen"
            }
            return OpenAICompatibleChatClient(
                baseURL: appSettings.chatBaseURL,
                apiKey: apiKey,
                model: appSettings.chatModel,
                extraHeaders: extraHeaders,
                // Local models (gemma4, qwen3…) think by default and would
                // otherwise return empty replies; see the client's doc comment.
                disablesModelThinking: providerKind == .ollama
            )
        }
    }
}
