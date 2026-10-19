//
//  PointingHoldSchedule.swift
//  leanring-buddy
//
//  When the companion stops pointing and flies back. It holds for 3 s after
//  the bubble finishes typing; a corrected target rect (the grounding model's
//  answer arrives 2.5-4 s into the reply) restarts that hold so the user sees
//  the corrected mark, but never past 8 s after the bubble. Each scheduled
//  fly-back carries a generation; a timer whose generation is no longer
//  current (the hold was restarted, a new pointing began, or this one ended)
//  does nothing.
//

nonisolated struct PointingHoldSchedule {
    static let holdSecondsAfterLatestTarget: Double = 3
    static let maximumHoldSecondsPastBubble: Double = 8

    struct FlyBack: Equatable {
        let generation: Int
        let delaySeconds: Double
    }

    private var generation = 0
    private var bubbleFinishedAtSeconds: Double?
    private var scheduledFlyBackAtSeconds: Double?

    /// A new flight toward a target began; earlier timers are stale.
    mutating func beginPointing() {
        generation += 1
        bubbleFinishedAtSeconds = nil
        scheduledFlyBackAtSeconds = nil
    }

    /// Starts the hold. `nowSeconds` is any monotonic clock (system uptime).
    mutating func bubbleFinishedStreaming(atSeconds nowSeconds: Double) -> FlyBack {
        generation += 1
        bubbleFinishedAtSeconds = nowSeconds
        scheduledFlyBackAtSeconds = nowSeconds + Self.holdSecondsAfterLatestTarget
        return FlyBack(generation: generation, delaySeconds: Self.holdSecondsAfterLatestTarget)
    }

    /// The target rect moved while pointing. Returns the new fly-back to
    /// schedule, or nil to keep the current one: the hold hasn't started yet
    /// (it will start from the bubble), or it would not end any later.
    mutating func targetRectChanged(atSeconds nowSeconds: Double) -> FlyBack? {
        guard let bubbleFinishedAtSeconds, let scheduledFlyBackAtSeconds else { return nil }
        let extendedFlyBackAtSeconds = min(
            nowSeconds + Self.holdSecondsAfterLatestTarget,
            bubbleFinishedAtSeconds + Self.maximumHoldSecondsPastBubble
        )
        guard extendedFlyBackAtSeconds > scheduledFlyBackAtSeconds else { return nil }
        generation += 1
        self.scheduledFlyBackAtSeconds = extendedFlyBackAtSeconds
        return FlyBack(generation: generation, delaySeconds: extendedFlyBackAtSeconds - nowSeconds)
    }

    /// The companion is flying back or was interrupted.
    mutating func endPointing() {
        beginPointing()
    }

    func isCurrent(_ flyBackGeneration: Int) -> Bool {
        flyBackGeneration == generation
    }
}
