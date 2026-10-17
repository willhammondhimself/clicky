//
//  MemoryModelProvisioner.swift
//  leanring-buddy
//
//  Checks which of the memory models Ollama has and pulls the missing ones,
//  one at a time, publishing progress for the status row. Mirrors
//  KokoroModelLoadCoordinator: a single in-flight run that every caller
//  awaits, sticky failure until `retry()`. Free of networking (the two
//  operations are injected) so it is unit-tested with fakes.
//

import Combine
import Foundation

@MainActor
final class MemoryModelProvisioner: ObservableObject {
    /// Returns the installed model names in `OllamaNativeEndpoints.normalizedModelName` form.
    typealias ListInstalledModelsOperation = @MainActor () async throws -> Set<String>
    typealias PullProgressHandler = @MainActor (_ fractionCompleted: Double?) -> Void
    typealias PullModelOperation = @MainActor (_ modelName: String, _ onProgress: PullProgressHandler) async throws -> Void

    @Published private(set) var provisioningState: MemoryModelProvisioningState = .notChecked

    var isReady: Bool {
        if case .ready = provisioningState { return true }
        return false
    }

    private let requiredModels: [String]
    private let listInstalledModels: ListInstalledModelsOperation
    private let pullModel: PullModelOperation
    private var inFlightRunTask: Task<Void, Never>?
    private var runGeneration = 0

    init(
        requiredModels: [String],
        listInstalledModels: @escaping ListInstalledModelsOperation,
        pullModel: @escaping PullModelOperation
    ) {
        self.requiredModels = requiredModels
        self.listInstalledModels = listInstalledModels
        self.pullModel = pullModel
    }

    /// Lists and pulls as needed. Returns when the state is terminal. Does
    /// nothing after a failure (see `retry`) or once ready.
    func prepareIfNeeded() async {
        while let runningTask = inFlightRunTask {
            await runningTask.value
        }

        switch provisioningState {
        case .ready, .ollamaUnreachable, .failed:
            return
        case .notChecked, .checking, .pulling:
            break
        }

        runGeneration += 1
        let thisRunGeneration = runGeneration
        provisioningState = .checking

        let runTask = Task { [weak self] in
            guard let self else { return }
            await self.listAndPullMissingModels()
            if self.runGeneration == thisRunGeneration {
                self.inFlightRunTask = nil
            }
        }
        inFlightRunTask = runTask
        await runTask.value
    }

    /// Clears a failure and runs again. Used by the Retry button.
    func retry() async {
        switch provisioningState {
        case .ollamaUnreachable, .failed:
            provisioningState = .notChecked
        default:
            break
        }
        await prepareIfNeeded()
    }

    private func listAndPullMissingModels() async {
        let installedModelNames: Set<String>
        do {
            installedModelNames = try await listInstalledModels()
        } catch {
            provisioningState = .ollamaUnreachable(message: "couldn't reach ollama: \(error.localizedDescription)")
            print("⚠️ Memory models: Ollama unreachable: \(error)")
            return
        }

        let missingModels = requiredModels.filter {
            !installedModelNames.contains(OllamaNativeEndpoints.normalizedModelName($0))
        }

        for modelName in missingModels {
            provisioningState = .pulling(modelName: modelName, fractionCompleted: nil)
            print("⬇️ Memory models: pulling \(modelName)")
            do {
                try await pullModel(modelName) { [weak self] fractionCompleted in
                    self?.provisioningState = .pulling(modelName: modelName, fractionCompleted: fractionCompleted)
                }
            } catch {
                provisioningState = .failed(message: "couldn't download \(modelName): \(error.localizedDescription)")
                print("⚠️ Memory models: pull of \(modelName) failed: \(error)")
                return
            }
        }

        provisioningState = .ready
        print("🧠 Memory models ready (\(requiredModels.joined(separator: ", ")))")
    }
}
