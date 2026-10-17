//
//  MemoryModelProvisioningState.swift
//  leanring-buddy
//
//  Whether the two Ollama models memory needs (embeddinggemma for retrieval,
//  gemma4:e2b for daily-note summaries) are installed. Published by
//  MemoryModelProvisioner and shown in the AI Settings memory status row.
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
    static let summarizerModel = "gemma4:e2b"
    /// Pulled in this order on first launch: the small one first so retrieval
    /// starts working while the summariser is still downloading.
    static let requiredModels = [embeddingModel, summarizerModel]
}
