import Foundation
import Testing

#if canImport(leanring_buddy)
@testable import leanring_buddy
#else
@testable import LumenLogic
#endif

/// Fake Ollama: a fixed set of installed models, a list that may fail, pulls
/// that may fail or block on a gate.
@MainActor
final class FakeOllamaModelSource {
    struct ListFailure: Error {}
    struct PullFailure: Error {}

    var installedModelNames: Set<String>
    var listFails = false
    var failingPullModelName: String?
    /// Simulates a pull stream that ends cleanly without installing anything.
    var pullsSilentlyDoNothing = false
    var pullGate: LoadGate?
    private(set) var listCallCount = 0
    private(set) var pulledModelNames: [String] = []

    init(installedModelNames: Set<String>) {
        self.installedModelNames = installedModelNames
    }

    func listInstalledModels() async throws -> Set<String> {
        listCallCount += 1
        if listFails { throw ListFailure() }
        return installedModelNames
    }

    func pullModel(_ modelName: String, onProgress: @MainActor (Double?) -> Void) async throws {
        pulledModelNames.append(modelName)
        onProgress(0.25)
        if let pullGate {
            await pullGate.waitUntilOpened()
        }
        if modelName == failingPullModelName { throw PullFailure() }
        onProgress(1.0)
        if !pullsSilentlyDoNothing {
            installedModelNames.insert(OllamaNativeEndpoints.normalizedModelName(modelName))
        }
    }
}

@MainActor
struct MemoryModelProvisionerTests {

    private let requiredModels = ["embeddinggemma", "gemma4:e2b"]

    private func makeProvisioner(
        installed: Set<String>,
        unreachableRetryInterval: TimeInterval = 30
    ) -> (MemoryModelProvisioner, FakeOllamaModelSource) {
        let source = FakeOllamaModelSource(installedModelNames: installed)
        let provisioner = MemoryModelProvisioner(
            requiredModels: requiredModels,
            unreachableRetryInterval: unreachableRetryInterval,
            listInstalledModels: { try await source.listInstalledModels() },
            pullModel: { modelName, onProgress in try await source.pullModel(modelName, onProgress: onProgress) }
        )
        return (provisioner, source)
    }

    @Test func readyRequiresTheModelsToBeListedAfterPulling() async {
        let (provisioner, source) = makeProvisioner(installed: ["embeddinggemma:latest"])
        source.pullsSilentlyDoNothing = true
        await provisioner.prepareIfNeeded()
        guard case .failed = provisioner.provisioningState else {
            Issue.record("expected failed when a pulled model is still missing, got \(provisioner.provisioningState)")
            return
        }
        #expect(source.listCallCount == 2)
    }

    @Test func unreachableIsCheckedAgainOnceTheRetryIntervalHasPassed() async {
        let (provisioner, source) = makeProvisioner(installed: ["embeddinggemma:latest", "gemma4:e2b"], unreachableRetryInterval: 0)
        source.listFails = true
        await provisioner.prepareIfNeeded()
        guard case .ollamaUnreachable = provisioner.provisioningState else {
            Issue.record("expected ollamaUnreachable, got \(provisioner.provisioningState)")
            return
        }

        // Ollama comes up later (launch-at-login case): the next prepare re-checks.
        source.listFails = false
        await provisioner.prepareIfNeeded()
        #expect(source.listCallCount == 2)
        #expect(provisioner.provisioningState == .ready)
    }

    private func yieldToOtherTasks() async {
        try? await Task.sleep(nanoseconds: 20_000_000)
    }

    /// Polls instead of a fixed sleep: under a parallel test run the main
    /// actor can be busy for longer than one yield.
    private func waitUntil(_ condition: @MainActor () -> Bool) async {
        for _ in 0..<100 where !condition() {
            try? await Task.sleep(nanoseconds: 10_000_000)
        }
    }

    @Test func everythingInstalledMeansReadyWithoutPulling() async {
        let (provisioner, source) = makeProvisioner(installed: ["embeddinggemma:latest", "gemma4:e2b", "gemma4:26b"])
        await provisioner.prepareIfNeeded()
        #expect(provisioner.provisioningState == .ready)
        #expect(provisioner.isReady)
        #expect(source.pulledModelNames.isEmpty)

        await provisioner.prepareIfNeeded()
        #expect(source.listCallCount == 1)
    }

    @Test func onlyTheMissingModelIsPulledAndProgressIsReported() async {
        let (provisioner, source) = makeProvisioner(installed: ["embeddinggemma:latest"])
        let gate = LoadGate()
        source.pullGate = gate

        let prepareTask = Task { await provisioner.prepareIfNeeded() }
        await waitUntil { source.pulledModelNames.count == 1 }
        #expect(provisioner.provisioningState == .pulling(modelName: "gemma4:e2b", fractionCompleted: 0.25))
        #expect(!provisioner.isReady)

        gate.open()
        await prepareTask.value
        #expect(source.pulledModelNames == ["gemma4:e2b"])
        #expect(provisioner.provisioningState == .ready)
    }

    @Test func missingModelsArePulledSequentiallyInRequiredOrder() async {
        let (provisioner, source) = makeProvisioner(installed: [])
        await provisioner.prepareIfNeeded()
        #expect(source.pulledModelNames == ["embeddinggemma", "gemma4:e2b"])
        #expect(provisioner.provisioningState == .ready)
    }

    @Test func listFailureMeansOllamaIsUnreachableAndIsSticky() async {
        let (provisioner, source) = makeProvisioner(installed: [])
        source.listFails = true
        await provisioner.prepareIfNeeded()
        guard case .ollamaUnreachable = provisioner.provisioningState else {
            Issue.record("expected ollamaUnreachable, got \(provisioner.provisioningState)")
            return
        }
        await provisioner.prepareIfNeeded()
        #expect(source.listCallCount == 1)
    }

    @Test func pullFailureMeansFailedAndRetryTriesAgain() async {
        let (provisioner, source) = makeProvisioner(installed: ["embeddinggemma:latest"])
        source.failingPullModelName = "gemma4:e2b"
        await provisioner.prepareIfNeeded()
        guard case .failed = provisioner.provisioningState else {
            Issue.record("expected failed, got \(provisioner.provisioningState)")
            return
        }

        source.failingPullModelName = nil
        await provisioner.retry()
        #expect(source.pulledModelNames == ["gemma4:e2b", "gemma4:e2b"])
        #expect(provisioner.provisioningState == .ready)
    }

    @Test func concurrentCallersShareOneRun() async {
        let (provisioner, source) = makeProvisioner(installed: [])
        let gate = LoadGate()
        source.pullGate = gate

        let firstCaller = Task { await provisioner.prepareIfNeeded() }
        let secondCaller = Task { await provisioner.prepareIfNeeded() }
        await waitUntil { source.pulledModelNames.count == 1 }
        gate.open()
        await firstCaller.value
        await secondCaller.value

        // One run: the initial list plus the post-pull verification, not one per caller.
        #expect(source.listCallCount == 2)
        #expect(source.pulledModelNames == ["embeddinggemma", "gemma4:e2b"])
        #expect(provisioner.provisioningState == .ready)
    }
}
