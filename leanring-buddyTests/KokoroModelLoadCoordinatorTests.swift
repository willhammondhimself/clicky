import Foundation
import Testing

#if canImport(leanring_buddy)
@testable import leanring_buddy
#else
@testable import ClickyLogic
#endif

/// Lets a test hold an async operation open until it decides to release it.
@MainActor
final class LoadGate {
    private var waitingContinuations: [CheckedContinuation<Void, Never>] = []
    private(set) var isOpen = false

    func waitUntilOpened() async {
        if isOpen { return }
        await withCheckedContinuation { continuation in
            waitingContinuations.append(continuation)
        }
    }

    func open() {
        isOpen = true
        let continuations = waitingContinuations
        waitingContinuations = []
        continuations.forEach { $0.resume() }
    }
}

/// Records every voice the coordinator asked it to load, optionally blocking
/// on a gate and optionally failing for a given voice.
@MainActor
final class RecordingLoadOperation {
    private(set) var loadedVoices: [String] = []
    var gate: LoadGate?
    var failingVoice: String?

    struct LoadFailure: Error {}

    func load(_ voice: String) async throws {
        loadedVoices.append(voice)
        if let gate {
            await gate.waitUntilOpened()
        }
        if voice == failingVoice {
            throw LoadFailure()
        }
    }
}

@MainActor
struct KokoroModelLoadCoordinatorTests {

    private func makeCoordinator(
        initialState: KokoroModelLoadState = .notLoaded
    ) -> (KokoroModelLoadCoordinator, RecordingLoadOperation) {
        let operation = RecordingLoadOperation()
        let coordinator = KokoroModelLoadCoordinator(initialState: initialState) { voice in
            try await operation.load(voice)
        }
        return (coordinator, operation)
    }

    private func yieldToOtherTasks() async {
        try? await Task.sleep(nanoseconds: 20_000_000)
    }

    @Test func loadsOnceAndReportsReady() async {
        let (coordinator, operation) = makeCoordinator()
        await coordinator.prepareIfNeeded(preloadingVoice: "bm_george")
        #expect(coordinator.loadState == .ready)
        #expect(operation.loadedVoices == ["bm_george"])

        await coordinator.prepareIfNeeded(preloadingVoice: "bm_george")
        #expect(operation.loadedVoices == ["bm_george"])
    }

    @Test func reportsLoadingWhileTheOperationRuns() async {
        let (coordinator, operation) = makeCoordinator()
        let gate = LoadGate()
        operation.gate = gate

        let loadTask = Task { await coordinator.prepareIfNeeded(preloadingVoice: "bm_george") }
        await yieldToOtherTasks()
        #expect(coordinator.loadState == .loading)

        gate.open()
        await loadTask.value
        #expect(coordinator.loadState == .ready)
    }

    @Test func concurrentCallersForTheSameVoiceShareOneLoad() async {
        let (coordinator, operation) = makeCoordinator()
        let gate = LoadGate()
        operation.gate = gate

        let firstCaller = Task { await coordinator.prepareIfNeeded(preloadingVoice: "bm_george") }
        let secondCaller = Task { await coordinator.prepareIfNeeded(preloadingVoice: "bm_george") }
        let thirdCaller = Task { await coordinator.prepareIfNeeded(preloadingVoice: "bm_george") }
        await yieldToOtherTasks()
        gate.open()
        await firstCaller.value
        await secondCaller.value
        await thirdCaller.value

        #expect(operation.loadedVoices == ["bm_george"])
        #expect(coordinator.loadState == .ready)
    }

    @Test func aDifferentVoiceRequestedDuringALoadIsLoadedOnceAfterwards() async {
        let (coordinator, operation) = makeCoordinator()
        let gate = LoadGate()
        operation.gate = gate

        let firstVoiceCaller = Task { await coordinator.prepareIfNeeded(preloadingVoice: "bm_george") }
        await yieldToOtherTasks()
        // Two callers ask for the new voice while the first load is still running
        // (factory warm-up + the user's question).
        let secondVoiceCallerA = Task { await coordinator.prepareIfNeeded(preloadingVoice: "bm_fable") }
        let secondVoiceCallerB = Task { await coordinator.prepareIfNeeded(preloadingVoice: "bm_fable") }
        await yieldToOtherTasks()
        gate.open()
        await firstVoiceCaller.value
        await secondVoiceCallerA.value
        await secondVoiceCallerB.value

        #expect(operation.loadedVoices == ["bm_george", "bm_fable"])
        #expect(coordinator.loadState == .ready)
        #expect(coordinator.preloadedVoices == ["bm_george", "bm_fable"])
    }

    @Test func failureIsStickyForTheSameVoiceButADifferentVoiceIsTried() async {
        let (coordinator, operation) = makeCoordinator()
        operation.failingVoice = "zz_mystery"

        await coordinator.prepareIfNeeded(preloadingVoice: "zz_mystery")
        guard case .failed = coordinator.loadState else {
            Issue.record("expected failed, got \(coordinator.loadState)")
            return
        }

        await coordinator.prepareIfNeeded(preloadingVoice: "zz_mystery")
        #expect(operation.loadedVoices == ["zz_mystery"])

        await coordinator.prepareIfNeeded(preloadingVoice: "bm_george")
        #expect(operation.loadedVoices == ["zz_mystery", "bm_george"])
        #expect(coordinator.loadState == .ready)
    }

    @Test func retryLoadTriesTheFailedVoiceAgain() async {
        let (coordinator, operation) = makeCoordinator()
        operation.failingVoice = "bm_george"

        await coordinator.prepareIfNeeded(preloadingVoice: "bm_george")
        operation.failingVoice = nil
        await coordinator.retryLoad(preloadingVoice: "bm_george")

        #expect(operation.loadedVoices == ["bm_george", "bm_george"])
        #expect(coordinator.loadState == .ready)
    }

    @Test func unavailableNeverLoads() async {
        let (coordinator, operation) = makeCoordinator(initialState: .unavailable(reason: "test"))
        await coordinator.prepareIfNeeded(preloadingVoice: "bm_george")
        await coordinator.retryLoad(preloadingVoice: "bm_george")
        #expect(operation.loadedVoices.isEmpty)
        #expect(coordinator.loadState == .unavailable(reason: "test"))
    }
}
