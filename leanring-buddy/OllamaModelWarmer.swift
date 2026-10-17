//
//  OllamaModelWarmer.swift
//  leanring-buddy
//
//  Preloads the selected Ollama model and pins it in memory. Without this,
//  Ollama unloads an idle model after a few minutes and the next question
//  pays a 10–20 s reload before it can answer — the opposite of "always on".
//
//  Uses Ollama's native /api/generate endpoint because the OpenAI-compatible
//  /v1 endpoint ignores `keep_alive`. Fire-and-forget; failures are logged
//  and otherwise ignored (the chat call will surface a real error if Ollama
//  is actually down).
//

import Foundation

enum OllamaModelWarmer {
    /// - Parameters:
    ///   - openAICompatibleBaseURL: the configured base URL, e.g. `http://localhost:11434/v1`.
    ///     The native endpoint lives one level up, so `/v1` is stripped.
    ///   - model: the Ollama model tag to load, e.g. `gemma4:26b`.
    static func preloadAndPin(openAICompatibleBaseURL: String, model: String) {
        let trimmedModel = model.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedModel.isEmpty,
              let nativeBaseURL = OllamaNativeEndpoints.nativeBaseURL(fromOpenAICompatibleBaseURL: openAICompatibleBaseURL) else {
            return
        }
        let generateURL = OllamaNativeEndpoints.generateURL(nativeBaseURL: nativeBaseURL)

        var request = URLRequest(url: generateURL)
        request.httpMethod = "POST"
        request.timeoutInterval = 120
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        // No prompt + keep_alive -1 means "load this model and keep it loaded
        // until Ollama exits". An empty prompt returns immediately once loaded.
        let body: [String: Any] = ["model": trimmedModel, "keep_alive": -1]
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)

        Task.detached(priority: .utility) {
            do {
                let (_, response) = try await URLSession.shared.data(for: request)
                let statusCode = (response as? HTTPURLResponse)?.statusCode ?? -1
                if (200...299).contains(statusCode) {
                    print("🔥 Ollama: \(trimmedModel) loaded and pinned")
                } else {
                    print("⚠️ Ollama warm-up for \(trimmedModel) returned HTTP \(statusCode)")
                }
            } catch {
                print("⚠️ Ollama warm-up failed (is Ollama running?): \(error.localizedDescription)")
            }
        }
    }
}
