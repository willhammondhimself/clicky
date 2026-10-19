//
//  PointingHoldSchedule.swift
//  leanring-buddy
//
//  When the companion stops pointing and flies back. It holds for 3 s after
//  the bubble finishes typing; a corrected target rect (the grounding model's
//  answer arrives 2.5-4 s into the reply) restarts that hold so the user sees
//  the corrected mark, but never past 8 s after the bubble. When the hold
//  ends while the grounding request is still running, the companion keeps
//  pointing until its answer (then a fresh hold) or the 8 s cap. Each scheduled
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

    /// What a fly-back timer does when it fires.
    enum HoldEndOutcome: Equatable {
        /// The hold was restarted, a new pointing began or this one ended.
        case stale
        /// Fade the mark and fly back.
        case flyBack
        /// The grounding model is still answering: keep pointing, and fly
        /// back at the cap (this timer) unless its answer arrives first.
        case waitForCorrection(FlyBack)
    }

    private var generation = 0
    private var bubbleFinishedAtSeconds: Double?
    private var scheduledFlyBackAtSeconds: Double?
    /// The 3 s hold ended while a grounding answer was still on its way, so
    /// the companion keeps pointing until the answer or the cap.
    private var isWaitingForCorrection = false

    /// A new flight toward a target began; earlier timers are stale.
    mutating func beginPointing() {
        generation += 1
        bubbleFinishedAtSeconds = nil
        scheduledFlyBackAtSeconds = nil
        isWaitingForCorrection = false
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
    /// (it will start from the bubble), or it would not end any later. While
    /// waiting for the correction, its arrival always restarts the hold (the
    /// cap timer would otherwise give it whatever time was left).
    mutating func targetRectChanged(atSeconds nowSeconds: Double) -> FlyBack? {
        guard let bubbleFinishedAtSeconds, let scheduledFlyBackAtSeconds else { return nil }
        let extendedFlyBackAtSeconds = min(
            nowSeconds + Self.holdSecondsAfterLatestTarget,
            bubbleFinishedAtSeconds + Self.maximumHoldSecondsPastBubble
        )
        if isWaitingForCorrection {
            isWaitingForCorrection = false
        } else {
            guard extendedFlyBackAtSeconds > scheduledFlyBackAtSeconds else { return nil }
        }
        generation += 1
        self.scheduledFlyBackAtSeconds = extendedFlyBackAtSeconds
        return FlyBack(generation: generation, delaySeconds: max(0, extendedFlyBackAtSeconds - nowSeconds))
    }

    /// A fly-back timer fired. With a grounding request still in flight the
    /// hold stays open until the cap: the answer takes 2.5-4 s after speech
    /// starts and usually lands after the 3 s hold, and dropping it would
    /// leave only the chat model's less accurate mark. The cap timer itself
    /// always flies back, so a slow or cold model can't park the companion.
    mutating func holdTimerFired(
        generation flyBackGeneration: Int,
        atSeconds nowSeconds: Double,
        isCorrectionPending: Bool
    ) -> HoldEndOutcome {
        guard isCurrent(flyBackGeneration) else { return .stale }
        guard isCorrectionPending,
              !isWaitingForCorrection,
              let bubbleFinishedAtSeconds else { return .flyBack }
        let capAtSeconds = bubbleFinishedAtSeconds + Self.maximumHoldSecondsPastBubble
        guard capAtSeconds > nowSeconds else { return .flyBack }
        generation += 1
        isWaitingForCorrection = true
        scheduledFlyBackAtSeconds = capAtSeconds
        return .waitForCorrection(FlyBack(generation: generation, delaySeconds: capAtSeconds - nowSeconds))
    }

    /// The grounding request ended (with or without moving the mark).
    /// Returns an immediate fly-back when the hold was only waiting for it;
    /// nil otherwise, keeping whatever hold is scheduled.
    mutating func correctionFinished(atSeconds nowSeconds: Double) -> FlyBack? {
        guard isWaitingForCorrection else { return nil }
        isWaitingForCorrection = false
        generation += 1
        scheduledFlyBackAtSeconds = nowSeconds
        return FlyBack(generation: generation, delaySeconds: 0)
    }

    /// The companion is flying back or was interrupted.
    mutating func endPointing() {
        beginPointing()
    }

    func isCurrent(_ flyBackGeneration: Int) -> Bool {
        flyBackGeneration == generation
    }
}
