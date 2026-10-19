//
//  MemoryModelProvisioningState.swift
//  leanring-buddy
//
//  Whether the Ollama model memory needs (embeddinggemma for retrieval) is
//  installed. Published by MemoryModelProvisioner and shown in the AI
//  Settings memory status row. Daily-note summaries use the chat model, so
//  they need nothing pulled here (see DailyNoteSummarizer.summaryModelName).
//

import Foundation

nonisolated enum MemoryModelProvisioningState: Equatable, Sendable {
    case notChecked
    case checking
    case pulling(modelName: String, fractionCompleted: Double?)
    case ready
    /// Ollama did not answer at all (not running, wrong URL).
    case ollamaUnreachable(message: String)
    /// Ollama answered but a pull failed (no network, unknown model name).
    case failed(message: String)
}

nonisolated enum MemoryModelCatalog {
    static let embeddingModel = "embeddinggemma"
    /// Only the embedding model. The old gemma4:e2b summariser was dropped:
    /// with the chat model and precise pointing's model it made four, Ollama
    /// keeps at most three loaded, and the evictions added ~0.8 s before
    /// every reply. Existing installs keep gemma4:e2b on disk; Lumen just
    /// stops using it.
    static let requiredModels = [embeddingModel]
}
