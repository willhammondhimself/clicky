//
//  PointingGroundingService.swift
//  leanring-buddy
//
//  Precise pointing's link to Ollama: makes sure the grounding model
//  (PointingGroundingRequest.modelName, ~3.3 GB) is installed, pulling it at
//  launch when missing with its own MemoryModelProvisioner instance (the
//  memory models are never mixed in), and asks it where an element is in a
//  screenshot. The panel shows `provisioningState` with Retry, like memory.
//
//  CompanionManager calls `locateGridPoint` only after a reply's speech has
//  started; the caller catches every error, nothing reaches the reply.
//

import Combine
import CoreGraphics
import Foundation

@MainActor
final class PointingGroundingService: ObservableObject {
    static let shared = PointingGroundingService()

    @Published private(set) var provisioningState: MemoryModelProvisioningState = .notChecked

    private let appSettings: AppSettings
    private var modelProvisioner: MemoryModelProvisioner!
    private var cancellables: Set<AnyCancellable> = []

    private convenience init() {
        self.init(appSettings: AppSettings.shared)
    }

    init(appSettings: AppSettings) {
        self.appSettings = appSettings

        modelProvisioner = MemoryModelProvisioner(
            requiredModels: PointingGroundingRequest.requiredModels,
            logLabel: "Pointing model",
            listInstalledModels: { [weak self] in
                guard let self else { return [] }
                return try await self.makeNativeClient().listInstalledModelNames()
            },
            pullModel: { [weak self] modelName, onProgress in
                guard let self else { return }
                try await self.makeNativeClient().pullModel(named: modelName, onProgress: onProgress)
            }
        )
        modelProvisioner.$provisioningState
            .sink { [weak self] newState in self?.provisioningState = newState }
            .store(in: &cancellables)

        appSettings.$isPrecisePointingEnabled
            .dropFirst()
            .removeDuplicates()
            .sink { [weak self] isEnabled in
                if isEnabled { self?.prepareAtLaunch() }
            }
            .store(in: &cancellables)
    }

    /// Checks for the grounding model and pulls it in the background when
    /// precise pointing is on. Safe to call again.
    func prepareAtLaunch() {
        guard appSettings.isPrecisePointingEnabled else { return }
        Task { [weak self] in
            await self?.modelProvisioner.prepareIfNeeded()
        }
    }

    func retryProvisioning() {
        Task { [weak self] in
            await self?.modelProvisioner.retry()
        }
    }

    /// Whether a grounding request may go out now: precise pointing is on
    /// and the model is installed. While Ollama was unreachable (it may have
    /// come up since launch) this starts a re-check, which the provisioner
    /// throttles, and answers false for this reply.
    func isReadyToGround() -> Bool {
        guard appSettings.isPrecisePointingEnabled else { return false }
        if case .ollamaUnreachable = modelProvisioner.provisioningState {
            prepareAtLaunch()
        }
        return modelProvisioner.isReady
    }

    /// Where the grounding model puts `elementLabel` in the screenshot, on
    /// the 0-1000 grid, or nil when its reply holds no usable point. Throws
    /// on transport or server errors.
    func locateGridPoint(forLabel elementLabel: String, jpegImageData: Data) async throws -> CGPoint? {
        let modelReply = try await makeNativeClient().locateElement(
            model: PointingGroundingRequest.modelName,
            systemPrompt: PointingGroundingRequest.systemPrompt,
            userText: PointingGroundingRequest.userText(forLabel: elementLabel),
            jpegImageData: jpegImageData
        )
        guard let gridPoint = PointingGroundingRequest.gridPoint(fromModelReply: modelReply) else {
            print("⚠️ Precise pointing: no usable point in \"\(modelReply.prefix(80))\"")
            return nil
        }
        return gridPoint
    }

    // MARK: - Private

    struct OllamaURLError: LocalizedError {
        var errorDescription: String? { "the ollama base url in settings is not a valid url" }
    }

    /// Same rule as memory: the configured URL when Ollama is the chat
    /// provider, the default local one otherwise.
    private func makeNativeClient() throws -> OllamaNativeClient {
        let openAICompatibleBaseURL = appSettings.chatProviderKind == .ollama
            ? appSettings.chatBaseURL
            : ChatProviderKind.ollama.defaultBaseURL
        guard let nativeBaseURL = OllamaNativeEndpoints.nativeBaseURL(fromOpenAICompatibleBaseURL: openAICompatibleBaseURL) else {
            throw OllamaURLError()
        }
        return OllamaNativeClient(nativeBaseURL: nativeBaseURL)
    }
}
