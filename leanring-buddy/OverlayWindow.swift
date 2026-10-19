//
//  OverlayWindow.swift
//  leanring-buddy
//
//  System-wide transparent overlay window for blue glowing cursor.
//  One OverlayWindow is created per screen so the cursor buddy
//  seamlessly follows the cursor across multiple monitors.
//

import AppKit
import AVFoundation
import SwiftUI

class OverlayWindow: NSWindow {
    init(screen: NSScreen) {
        // Create window covering entire screen
        super.init(
            contentRect: screen.frame,
            styleMask: .borderless,
            backing: .buffered,
            defer: false
        )

        // Make window transparent and non-interactive
        self.isOpaque = false
        self.backgroundColor = .clear
        self.level = .screenSaver  // Always on top, above submenus and popups
        self.ignoresMouseEvents = true  // Click-through
        self.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary]
        self.isReleasedWhenClosed = false
        self.hasShadow = false

        // Important: Allow the window to appear even when app is not active
        self.hidesOnDeactivate = false

        // Cover the entire screen
        self.setFrame(screen.frame, display: true)

        // Make sure it's on the right screen
        if let screenForWindow = NSScreen.screens.first(where: { $0.frame == screen.frame }) {
            self.setFrameOrigin(screenForWindow.frame.origin)
        }
    }

    // Prevent window from becoming key (no focus stealing)
    override var canBecomeKey: Bool {
        return false
    }

    override var canBecomeMain: Bool {
        return false
    }
}

// PreferenceKey for tracking bubble size
struct SizePreferenceKey: PreferenceKey {
    static var defaultValue: CGSize = .zero
    static func reduce(value: inout CGSize, nextValue: () -> CGSize) {
        value = nextValue()
    }
}

struct NavigationBubbleSizePreferenceKey: PreferenceKey {
    static var defaultValue: CGSize = .zero
    static func reduce(value: inout CGSize, nextValue: () -> CGSize) {
        value = nextValue()
    }
}

/// The buddy's behavioral mode. Controls whether it follows the cursor,
/// is flying toward a detected UI element, or is pointing at an element.
enum BuddyNavigationMode {
    /// Default — buddy follows the mouse cursor with spring animation
    case followingCursor
    /// Buddy is animating toward a detected UI element location
    case navigatingToTarget
    /// Buddy has arrived at the target and is pointing at it with a speech bubble
    case pointingAtTarget
}

// SwiftUI view for the on-screen companion. Each screen gets its own
// CompanionOverlayView. The view checks whether the cursor is currently on
// THIS screen and only shows the companion when it is. The selected skin
// (AppSettings.selectedSkin) draws the companion in every state, the mark
// around a pointing target, and the speech bubbles.
struct CompanionOverlayView: View {
    let screenFrame: CGRect
    let isFirstAppearance: Bool
    @ObservedObject var companionManager: CompanionManager
    @ObservedObject private var appSettings = AppSettings.shared

    @State private var cursorPosition: CGPoint
    @State private var isCursorOnThisScreen: Bool

    init(screenFrame: CGRect, isFirstAppearance: Bool, companionManager: CompanionManager) {
        self.screenFrame = screenFrame
        self.isFirstAppearance = isFirstAppearance
        self.companionManager = companionManager

        // Seed the cursor position from the current mouse location so the
        // buddy doesn't flash at (0,0) before onAppear fires.
        let mouseLocation = NSEvent.mouseLocation
        let localX = mouseLocation.x - screenFrame.origin.x
        let localY = screenFrame.height - (mouseLocation.y - screenFrame.origin.y)
        _cursorPosition = State(initialValue: CGPoint(x: localX + 35, y: localY + 25))
        _isCursorOnThisScreen = State(initialValue: screenFrame.contains(mouseLocation))
    }
    @State private var timer: Timer?
    @State private var welcomeText: String = ""
    @State private var showWelcome: Bool = true
    @State private var bubbleSize: CGSize = .zero
    @State private var bubbleOpacity: Double = 1.0
    @State private var cursorOpacity: Double = 0.0

    // MARK: - Buddy Navigation State

    /// The buddy's current behavioral mode (following cursor, navigating, or pointing).
    @State private var buddyNavigationMode: BuddyNavigationMode = .followingCursor

    /// The element rect the skin's mark is drawn around while pointing, in
    /// this overlay's SwiftUI space and in global AppKit space (for the
    /// Instrument x/y readout). Nil when the pipeline gave no rect.
    @State private var pointingTargetRectInOverlay: CGRect?
    @State private var pointingTargetRectInAppKitGlobal: CGRect?
    @State private var pointingMarkOpacity: Double = 0.0

    /// When the companion flies back: 3 s after the bubble, restarted when
    /// the precise rect arrives late, capped at 8 s past the bubble. Stale
    /// fly-back timers check its generation and do nothing.
    @State private var pointingHoldSchedule = PointingHoldSchedule()

    /// Where the current bezier flight ends. State rather than a captured
    /// constant so the flight can be retargeted mid-air when the precise
    /// element rect arrives after the flight has started.
    @State private var navigationFlightDestination: CGPoint = .zero

    /// Speech bubble text shown when pointing at a detected element.
    @State private var navigationBubbleText: String = ""
    @State private var navigationBubbleOpacity: Double = 0.0
    @State private var navigationBubbleSize: CGSize = .zero

    /// The cursor position at the moment navigation started, used to detect
    /// if the user moves the cursor enough to cancel the navigation.
    @State private var cursorPositionWhenNavigationStarted: CGPoint = .zero

    /// Timer driving the frame-by-frame bezier arc flight animation.
    /// Invalidated when the flight completes, is canceled, or the view disappears.
    @State private var navigationAnimationTimer: Timer?

    /// Scale factor applied to the companion during flight. Grows to ~1.3x
    /// at the midpoint of the arc and shrinks back to 1.0x on landing, creating
    /// an energetic "swooping" feel.
    @State private var buddyFlightScale: CGFloat = 1.0

    /// Scale factor for the navigation speech bubble's pop-in entrance.
    /// Starts at 0.5 and springs to 1.0 when the first character appears.
    @State private var navigationBubbleScale: CGFloat = 1.0

    /// True when the buddy is flying BACK to the cursor after pointing.
    /// Only during the return flight can cursor movement cancel the animation.
    @State private var isReturningToCursor: Bool = false

    private let fullWelcomeMessage = "hey! i'm lumen"
    private static let replyBubbleMaximumWidth: CGFloat = 300

    /// The companion steps aside while the user types, leaves the mouse
    /// still, or uses a full-screen app; never during the first-run welcome.
    private var isCompanionAutoHiddenOnThisScreen: Bool {
        companionManager.isCompanionAutoHidden && !(showWelcome && !welcomeText.isEmpty)
    }

    var body: some View {
        ZStack {
            // Nearly transparent background (helps with compositing)
            Color.black.opacity(0.001)

            // The skin's mark around the pointing target, drawn under the
            // bubbles and the companion so they never hide it.
            if buddyNavigationMode == .pointingAtTarget,
               let pointingTargetRectInOverlay,
               let pointingTargetRectInAppKitGlobal {
                SkinPointingMarkView(
                    skin: appSettings.selectedSkin,
                    targetRectInOverlay: pointingTargetRectInOverlay,
                    targetRectInAppKitGlobal: pointingTargetRectInAppKitGlobal
                )
                .opacity(pointingMarkOpacity)
                .animation(.easeOut(duration: 0.3), value: pointingMarkOpacity)
            }

            // Welcome speech bubble (first launch only)
            if isCursorOnThisScreen && showWelcome && !welcomeText.isEmpty {
                SkinBubbleView(skin: appSettings.selectedSkin, text: welcomeText)
                    .fixedSize()
                    .overlay(
                        GeometryReader { geo in
                            Color.clear
                                .preference(key: SizePreferenceKey.self, value: geo.size)
                        }
                    )
                    .opacity(bubbleOpacity)
                    .position(x: cursorPosition.x + 10 + (bubbleSize.width / 2), y: cursorPosition.y + 18)
                    .animation(.spring(response: 0.2, dampingFraction: 0.6, blendDuration: 0), value: cursorPosition)
                    .animation(.easeOut(duration: 0.5), value: bubbleOpacity)
                    .onPreferenceChange(SizePreferenceKey.self) { newSize in
                        bubbleSize = newSize
                    }
            }

            // Onboarding prompt — "press control + option and introduce yourself" after the welcome
            if isCursorOnThisScreen && companionManager.showOnboardingPrompt && !companionManager.onboardingPromptText.isEmpty {
                SkinBubbleView(skin: appSettings.selectedSkin, text: companionManager.onboardingPromptText)
                    .fixedSize()
                    .overlay(
                        GeometryReader { geo in
                            Color.clear
                                .preference(key: SizePreferenceKey.self, value: geo.size)
                        }
                    )
                    .opacity(companionManager.onboardingPromptOpacity)
                    .position(x: cursorPosition.x + 10 + (bubbleSize.width / 2), y: cursorPosition.y + 18)
                    .animation(.spring(response: 0.2, dampingFraction: 0.6, blendDuration: 0), value: cursorPosition)
                    .animation(.easeOut(duration: 0.4), value: companionManager.onboardingPromptOpacity)
                    .onPreferenceChange(SizePreferenceKey.self) { newSize in
                        bubbleSize = newSize
                    }
            }

            // The reply as text beside the companion (Voice + text or Text
            // only), revealed a little ahead of the voice. Hidden while the
            // companion is away pointing, where the pointing bubble talks.
            if isCursorOnThisScreen,
               buddyNavigationMode == .followingCursor,
               let replyBubbleText = companionManager.replyBubbleText {
                TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { timelineContext in
                    let revealedCharacterCount = ReplyTextTiming.revealedCharacterCount(
                        secondsSinceShown: timelineContext.date.timeIntervalSince(companionManager.replyBubbleShownAt),
                        totalCharacterCount: replyBubbleText.count
                    )
                    SkinBubbleView(skin: appSettings.selectedSkin, text: String(replyBubbleText.prefix(revealedCharacterCount)))
                        .frame(maxWidth: Self.replyBubbleMaximumWidth, alignment: .leading)
                        .fixedSize(horizontal: false, vertical: true)
                        .opacity(revealedCharacterCount == 0 ? 0 : 1)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .offset(
                    x: min(cursorPosition.x + 10, screenFrame.width - Self.replyBubbleMaximumWidth - 16),
                    y: cursorPosition.y + 12
                )
                .transition(.opacity)
                .allowsHitTesting(false)
            }

            // Navigation pointer bubble — shown when the companion arrives at a
            // detected element. Pops in with a scale-bounce (0.5x → 1.0x spring).
            if buddyNavigationMode == .pointingAtTarget && !navigationBubbleText.isEmpty {
                SkinBubbleView(skin: appSettings.selectedSkin, text: navigationBubbleText)
                    .fixedSize()
                    .overlay(
                        GeometryReader { geo in
                            Color.clear
                                .preference(key: NavigationBubbleSizePreferenceKey.self, value: geo.size)
                        }
                    )
                    .scaleEffect(navigationBubbleScale)
                    .opacity(navigationBubbleOpacity)
                    .position(PointingGeometry.pointingBubbleCenter(
                        companionPoint: cursorPosition,
                        bubbleSize: navigationBubbleSize,
                        targetRectInOverlay: pointingTargetRectInOverlay
                    ))
                    .animation(.spring(response: 0.2, dampingFraction: 0.6, blendDuration: 0), value: cursorPosition)
                    .animation(.spring(response: 0.4, dampingFraction: 0.6), value: navigationBubbleScale)
                    .animation(.easeOut(duration: 0.5), value: navigationBubbleOpacity)
                    .onPreferenceChange(NavigationBubbleSizePreferenceKey.self) { newSize in
                        navigationBubbleSize = newSize
                    }
            }

            // The companion, drawn by the selected skin in whichever state the
            // voice pipeline and the pointing flight put it in.
            //
            // During cursor following: fast spring animation for snappy tracking.
            // During navigation: NO implicit animation — the frame-by-frame bezier
            // timer controls position directly at 60fps for a smooth arc flight.
            SkinCompanionView(
                skin: appSettings.selectedSkin,
                visualState: companionVisualState,
                microphoneAudioPowerLevel: companionManager.currentAudioPowerLevel,
                isVisible: buddyIsVisibleOnThisScreen && !isCompanionAutoHiddenOnThisScreen && cursorOpacity > 0
            )
            .scaleEffect(buddyFlightScale)
            .opacity(buddyIsVisibleOnThisScreen && !isCompanionAutoHiddenOnThisScreen ? cursorOpacity : 0)
            .animation(.easeOut(duration: 0.25), value: isCompanionAutoHiddenOnThisScreen)
            .position(cursorPosition)
            .animation(
                buddyNavigationMode == .followingCursor
                    ? .spring(response: 0.2, dampingFraction: 0.6, blendDuration: 0)
                    : nil,
                value: cursorPosition
            )

        }
        .frame(width: screenFrame.width, height: screenFrame.height)
        .ignoresSafeArea()
        .onAppear {
            // Set initial cursor position immediately before starting animation
            let mouseLocation = NSEvent.mouseLocation
            isCursorOnThisScreen = screenFrame.contains(mouseLocation)

            let swiftUIPosition = convertScreenPointToSwiftUICoordinates(mouseLocation)
            self.cursorPosition = CGPoint(x: swiftUIPosition.x + 35, y: swiftUIPosition.y + 25)

            startTrackingCursor()

            // Only show welcome message on first appearance (app start)
            // and only if the cursor starts on this screen
            if isFirstAppearance && isCursorOnThisScreen {
                withAnimation(.easeIn(duration: 2.0)) {
                    self.cursorOpacity = 1.0
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                    self.bubbleOpacity = 0.0
                    startWelcomeAnimation()
                }
            } else {
                self.cursorOpacity = 1.0
            }
        }
        .onDisappear {
            timer?.invalidate()
            navigationAnimationTimer?.invalidate()
        }
        .onChange(of: companionManager.detectedElementScreenLocation) { newLocation in
            // When a UI element location is detected, navigate the buddy to
            // that position so it points at the element.
            guard let screenLocation = newLocation,
                  let displayFrame = companionManager.detectedElementDisplayFrame else {
                return
            }

            // Only navigate if the target is on THIS screen
            guard screenFrame.contains(CGPoint(x: displayFrame.midX, y: displayFrame.midY))
                  || displayFrame == screenFrame else {
                return
            }

            startNavigatingToElement(screenLocation: screenLocation)
        }
        .onChange(of: companionManager.detectedElementTargetRect) { newTargetRect in
            // Only the overlay already flying to or pointing at the element
            // reacts; the return flight is left alone.
            guard let newTargetRect,
                  buddyNavigationMode != .followingCursor,
                  !isReturningToCursor else { return }
            retargetPointing(toTargetRectInAppKitGlobal: newTargetRect)
        }
        .onChange(of: companionManager.isPreciseGroundingInFlight) { isGroundingInFlight in
            // A hold kept open for the grounding answer ends at once when the
            // request finishes without moving the mark.
            guard !isGroundingInFlight,
                  buddyNavigationMode == .pointingAtTarget,
                  !isReturningToCursor else { return }
            if let flyBack = pointingHoldSchedule.correctionFinished(atSeconds: ProcessInfo.processInfo.systemUptime) {
                scheduleFlyBackToCursor(flyBack)
            }
        }
    }

    /// Which animation the skin's companion shows right now.
    private var companionVisualState: CompanionVisualState {
        CompanionVisualState.resolve(
            isListening: companionManager.voiceState == .listening,
            isProcessing: companionManager.voiceState == .processing,
            isResponding: companionManager.voiceState == .responding,
            isFlyingToOrFromTarget: buddyNavigationMode == .navigatingToTarget || isReturningToCursor
        )
    }

    /// Whether the companion should be visible on this screen.
    /// True when cursor is on this screen during normal following, or
    /// when navigating/pointing at a target on this screen. When another
    /// screen is navigating (detectedElementScreenLocation is set but this
    /// screen isn't the one animating), hide the cursor so only one buddy
    /// is ever visible at a time.
    private var buddyIsVisibleOnThisScreen: Bool {
        switch buddyNavigationMode {
        case .followingCursor:
            // If another screen's CompanionOverlayView is navigating to an element,
            // hide the cursor on this screen to prevent a duplicate buddy
            if companionManager.detectedElementScreenLocation != nil {
                return false
            }
            return isCursorOnThisScreen
        case .navigatingToTarget, .pointingAtTarget:
            return true
        }
    }

    // MARK: - Cursor Tracking

    private func startTrackingCursor() {
        timer = Timer.scheduledTimer(withTimeInterval: 0.016, repeats: true) { _ in
            let mouseLocation = NSEvent.mouseLocation
            self.isCursorOnThisScreen = self.screenFrame.contains(mouseLocation)

            // During forward flight or pointing, the buddy is NOT interrupted by
            // mouse movement — it completes its full animation and return flight.
            // Only during the RETURN flight do we allow cursor movement to cancel
            // (so the buddy snaps to following if the user moves while it's flying back).
            if self.buddyNavigationMode == .navigatingToTarget && self.isReturningToCursor {
                let currentMouseInSwiftUI = self.convertScreenPointToSwiftUICoordinates(mouseLocation)
                let distanceFromNavigationStart = hypot(
                    currentMouseInSwiftUI.x - self.cursorPositionWhenNavigationStarted.x,
                    currentMouseInSwiftUI.y - self.cursorPositionWhenNavigationStarted.y
                )
                if distanceFromNavigationStart > 100 {
                    cancelNavigationAndResumeFollowing()
                }
                return
            }

            // During forward navigation or pointing, just skip cursor tracking
            if self.buddyNavigationMode != .followingCursor {
                return
            }

            // Normal cursor following
            let swiftUIPosition = self.convertScreenPointToSwiftUICoordinates(mouseLocation)
            let buddyX = swiftUIPosition.x + 35
            let buddyY = swiftUIPosition.y + 25
            self.cursorPosition = CGPoint(x: buddyX, y: buddyY)
        }
    }

    /// Converts a macOS screen point (AppKit, bottom-left origin) to SwiftUI
    /// coordinates (top-left origin) relative to this screen's overlay window.
    private func convertScreenPointToSwiftUICoordinates(_ screenPoint: CGPoint) -> CGPoint {
        let x = screenPoint.x - screenFrame.origin.x
        let y = (screenFrame.origin.y + screenFrame.height) - screenPoint.y
        return CGPoint(x: x, y: y)
    }

    // MARK: - Element Navigation

    /// Starts animating the buddy toward a detected UI element location.
    private func startNavigatingToElement(screenLocation: CGPoint) {
        // Don't interrupt welcome animation
        guard !showWelcome || welcomeText.isEmpty else { return }

        // A fly-back timer from an earlier pointing must not end this one.
        pointingHoldSchedule.beginPointing()

        let flightDestination: CGPoint
        if let targetRectInAppKitGlobal = companionManager.detectedElementTargetRect {
            flightDestination = applyPointingTargetRect(targetRectInAppKitGlobal)
        } else {
            // No rect: sit beside the point —
            // 8px to the right, 12px below — clamped to the screen.
            let targetInSwiftUI = convertScreenPointToSwiftUICoordinates(screenLocation)
            pointingTargetRectInOverlay = nil
            pointingTargetRectInAppKitGlobal = nil
            flightDestination = CGPoint(
                x: max(20, min(targetInSwiftUI.x + 8, screenFrame.width - 20)),
                y: max(20, min(targetInSwiftUI.y + 12, screenFrame.height - 20))
            )
        }

        // Record the current cursor position so we can detect if the user
        // moves the mouse enough to cancel the return flight
        let mouseLocation = NSEvent.mouseLocation
        cursorPositionWhenNavigationStarted = convertScreenPointToSwiftUICoordinates(mouseLocation)

        // Enter navigation mode — stop cursor following
        buddyNavigationMode = .navigatingToTarget
        isReturningToCursor = false

        animateBezierFlightArc(to: flightDestination) {
            guard self.buddyNavigationMode == .navigatingToTarget else { return }
            self.startPointingAtElement()
        }
    }

    /// Stores the rect the skin's mark hugs and returns where the companion
    /// parks: just outside the rect, so it never covers what it points at.
    private func applyPointingTargetRect(_ targetRectInAppKitGlobal: CGRect) -> CGPoint {
        let targetRectInOverlay = PointingGeometry.overlayLocalRect(
            fromAppKitGlobalRect: targetRectInAppKitGlobal,
            screenFrame: screenFrame
        )
        pointingTargetRectInOverlay = targetRectInOverlay
        pointingTargetRectInAppKitGlobal = targetRectInAppKitGlobal
        return PointingGeometry.companionParkingPoint(
            forTargetRectInOverlay: targetRectInOverlay,
            overlaySize: screenFrame.size,
            companionRadius: 10,
            gap: 6
        )
    }

    /// The precise element rect arrived after the flight began (speech never
    /// waits for the Accessibility lookup). Mid-flight, the flight bends onto
    /// the new parking point; once parked, the companion hops there and the
    /// mark redraws around the element. The grounded rect can arrive 3-4 s
    /// into the reply, so the hold restarts to give the corrected mark its
    /// full 3 s (within the schedule's cap).
    private func retargetPointing(toTargetRectInAppKitGlobal targetRectInAppKitGlobal: CGRect) {
        let updatedParkingPoint = applyPointingTargetRect(targetRectInAppKitGlobal)
        switch buddyNavigationMode {
        case .navigatingToTarget:
            navigationFlightDestination = updatedParkingPoint
        case .pointingAtTarget:
            animateBezierFlightArc(to: updatedParkingPoint) {}
            if let extendedFlyBack = pointingHoldSchedule.targetRectChanged(atSeconds: ProcessInfo.processInfo.systemUptime) {
                // The fade may already have started in the last half second
                // of the old hold; bring the mark and bubble back.
                pointingMarkOpacity = 1.0
                navigationBubbleOpacity = 1.0
                scheduleFlyBackToCursor(extendedFlyBack)
            }
        case .followingCursor:
            break
        }
    }

    /// Animates the buddy along a quadratic bezier arc from its current position
    /// to the specified destination, scaling up at the midpoint for a
    /// "swooping" feel. Skins never rotate the companion.
    private func animateBezierFlightArc(
        to destination: CGPoint,
        onComplete: @escaping () -> Void
    ) {
        navigationAnimationTimer?.invalidate()

        let startPosition = cursorPosition
        let endPosition = destination
        navigationFlightDestination = destination

        let deltaX = endPosition.x - startPosition.x
        let deltaY = endPosition.y - startPosition.y
        let distance = hypot(deltaX, deltaY)

        // Flight duration scales with distance: short hops are quick, long
        // flights are more dramatic. Clamped to 0.6s–1.4s.
        let flightDurationSeconds = min(max(distance / 800.0, 0.6), 1.4)
        let frameInterval: Double = 1.0 / 60.0
        let totalFrames = Int(flightDurationSeconds / frameInterval)
        var currentFrame = 0

        // Control point for the quadratic bezier arc. Offset the midpoint
        // upward (negative Y in SwiftUI) so the buddy flies in a parabolic arc.
        let midPoint = CGPoint(
            x: (startPosition.x + endPosition.x) / 2.0,
            y: (startPosition.y + endPosition.y) / 2.0
        )
        let arcHeight = min(distance * 0.2, 80.0)
        let controlPoint = CGPoint(x: midPoint.x, y: midPoint.y - arcHeight)

        navigationAnimationTimer = Timer.scheduledTimer(withTimeInterval: frameInterval, repeats: true) { _ in
            currentFrame += 1

            if currentFrame > totalFrames {
                self.navigationAnimationTimer?.invalidate()
                self.navigationAnimationTimer = nil
                self.cursorPosition = self.navigationFlightDestination
                self.buddyFlightScale = 1.0
                onComplete()
                return
            }

            // Linear progress 0→1 over the flight duration
            let linearProgress = Double(currentFrame) / Double(totalFrames)

            // Smoothstep easeInOut: 3t² - 2t³ (Hermite interpolation)
            let t = linearProgress * linearProgress * (3.0 - 2.0 * linearProgress)

            // Quadratic bezier: B(t) = (1-t)²·P0 + 2(1-t)t·P1 + t²·P2
            let oneMinusT = 1.0 - t
            // The end point is read every frame: it moves if the flight is
            // retargeted onto the precise element rect.
            let currentEndPosition = self.navigationFlightDestination
            let bezierX = oneMinusT * oneMinusT * startPosition.x
                        + 2.0 * oneMinusT * t * controlPoint.x
                        + t * t * currentEndPosition.x
            let bezierY = oneMinusT * oneMinusT * startPosition.y
                        + 2.0 * oneMinusT * t * controlPoint.y
                        + t * t * currentEndPosition.y

            self.cursorPosition = CGPoint(x: bezierX, y: bezierY)

            // Scale pulse: sin curve peaks at midpoint of the flight.
            // Buddy grows to ~1.3x at the apex, then shrinks back to 1.0x on landing.
            let scalePulse = sin(linearProgress * .pi)
            self.buddyFlightScale = 1.0 + scalePulse * 0.3
        }
    }

    /// Transitions to pointing mode — shows a speech bubble with a bouncy
    /// scale-in entrance and variable-speed character streaming.
    private func startPointingAtElement() {
        buddyNavigationMode = .pointingAtTarget
        pointingMarkOpacity = 1.0

        // Reset navigation bubble state — start small for the scale-bounce entrance
        navigationBubbleText = ""
        navigationBubbleOpacity = 1.0
        navigationBubbleSize = .zero
        navigationBubbleScale = 0.5

        // The pipeline sets the element's name (or a short phrase) as the
        // bubble text; fall back to a phrase if anything left it empty.
        let pointerPhrase = companionManager.detectedElementBubbleText
            ?? PointingBubbleText.fallbackPhrases.randomElement()
            ?? "right here"

        streamNavigationBubbleCharacter(phrase: pointerPhrase, characterIndex: 0) {
            // All characters streamed — hold for 3 seconds, then fly back
            let flyBack = self.pointingHoldSchedule.bubbleFinishedStreaming(atSeconds: ProcessInfo.processInfo.systemUptime)
            self.scheduleFlyBackToCursor(flyBack)
        }
    }

    /// Fades the mark and bubble when the hold ends, then flies back. Does
    /// nothing if the hold was restarted, a new pointing began or this one
    /// already ended (the schedule's generation moved on). While the
    /// grounding model is still answering, keeps pointing until the
    /// schedule's cap instead.
    private func scheduleFlyBackToCursor(_ flyBack: PointingHoldSchedule.FlyBack) {
        DispatchQueue.main.asyncAfter(deadline: .now() + flyBack.delaySeconds) {
            guard self.buddyNavigationMode == .pointingAtTarget else { return }
            let holdEndOutcome = self.pointingHoldSchedule.holdTimerFired(
                generation: flyBack.generation,
                atSeconds: ProcessInfo.processInfo.systemUptime,
                isCorrectionPending: self.companionManager.isPreciseGroundingInFlight
            )
            switch holdEndOutcome {
            case .stale:
                return
            case .waitForCorrection(let capFlyBack):
                self.scheduleFlyBackToCursor(capFlyBack)
                return
            case .flyBack:
                break
            }
            self.navigationBubbleOpacity = 0.0
            self.pointingMarkOpacity = 0.0
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                guard self.pointingHoldSchedule.isCurrent(flyBack.generation),
                      self.buddyNavigationMode == .pointingAtTarget else { return }
                self.startFlyingBackToCursor()
            }
        }
    }

    /// Streams the navigation bubble text one character at a time with variable
    /// delays (30–60ms) for a natural "speaking" rhythm.
    private func streamNavigationBubbleCharacter(
        phrase: String,
        characterIndex: Int,
        onComplete: @escaping () -> Void
    ) {
        guard buddyNavigationMode == .pointingAtTarget else { return }
        guard characterIndex < phrase.count else {
            onComplete()
            return
        }

        let charIndex = phrase.index(phrase.startIndex, offsetBy: characterIndex)
        navigationBubbleText.append(phrase[charIndex])

        // On the first character, trigger the scale-bounce entrance
        if characterIndex == 0 {
            navigationBubbleScale = 1.0
        }

        let characterDelay = Double.random(in: 0.03...0.06)
        DispatchQueue.main.asyncAfter(deadline: .now() + characterDelay) {
            self.streamNavigationBubbleCharacter(
                phrase: phrase,
                characterIndex: characterIndex + 1,
                onComplete: onComplete
            )
        }
    }

    /// Flies the buddy back to the current cursor position after pointing is done.
    private func startFlyingBackToCursor() {
        let mouseLocation = NSEvent.mouseLocation
        let cursorInSwiftUI = convertScreenPointToSwiftUICoordinates(mouseLocation)
        let cursorWithTrackingOffset = CGPoint(x: cursorInSwiftUI.x + 35, y: cursorInSwiftUI.y + 25)

        cursorPositionWhenNavigationStarted = cursorInSwiftUI

        buddyNavigationMode = .navigatingToTarget
        isReturningToCursor = true
        companionManager.pointingReturnFlightStarted()

        animateBezierFlightArc(to: cursorWithTrackingOffset) {
            self.finishNavigationAndResumeFollowing()
        }
    }

    /// Cancels an in-progress navigation because the user moved the cursor.
    private func cancelNavigationAndResumeFollowing() {
        navigationAnimationTimer?.invalidate()
        navigationAnimationTimer = nil
        navigationBubbleText = ""
        navigationBubbleOpacity = 0.0
        navigationBubbleScale = 1.0
        buddyFlightScale = 1.0
        finishNavigationAndResumeFollowing()
    }

    /// Returns the buddy to normal cursor-following mode after navigation completes.
    private func finishNavigationAndResumeFollowing() {
        navigationAnimationTimer?.invalidate()
        navigationAnimationTimer = nil
        pointingHoldSchedule.endPointing()
        buddyNavigationMode = .followingCursor
        isReturningToCursor = false
        buddyFlightScale = 1.0
        pointingMarkOpacity = 0.0
        pointingTargetRectInOverlay = nil
        pointingTargetRectInAppKitGlobal = nil
        navigationBubbleText = ""
        navigationBubbleOpacity = 0.0
        navigationBubbleScale = 1.0
        companionManager.clearDetectedElementLocation()
    }

    // MARK: - Welcome Animation

    private func startWelcomeAnimation() {
        withAnimation(.easeIn(duration: 0.4)) {
            self.bubbleOpacity = 1.0
        }

        var currentIndex = 0
        Timer.scheduledTimer(withTimeInterval: 0.03, repeats: true) { timer in
            guard currentIndex < self.fullWelcomeMessage.count else {
                timer.invalidate()
                // Hold the text for 2 seconds, then fade it out
                DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                    self.bubbleOpacity = 0.0
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
                    self.showWelcome = false
                    // Then invite the user to talk.
                    self.companionManager.startOnboardingPromptStream()
                }
                return
            }

            let index = self.fullWelcomeMessage.index(self.fullWelcomeMessage.startIndex, offsetBy: currentIndex)
            self.welcomeText.append(self.fullWelcomeMessage[index])
            currentIndex += 1
        }
    }
}

// Manager for overlay windows — creates one per screen so the cursor
// buddy seamlessly follows the cursor across multiple monitors.
@MainActor
class OverlayWindowManager {
    private var overlayWindows: [OverlayWindow] = []
    var hasShownOverlayBefore = false

    func showOverlay(onScreens screens: [NSScreen], companionManager: CompanionManager) {
        // Hide any existing overlays
        hideOverlay()

        // Track if this is the first time showing overlay (welcome message)
        let isFirstAppearance = !hasShownOverlayBefore
        hasShownOverlayBefore = true

        // Create one overlay window per screen
        for screen in screens {
            let window = OverlayWindow(screen: screen)

            let contentView = CompanionOverlayView(
                screenFrame: screen.frame,
                isFirstAppearance: isFirstAppearance,
                companionManager: companionManager
            )

            let hostingView = NSHostingView(rootView: contentView)
            hostingView.frame = screen.frame
            window.contentView = hostingView

            overlayWindows.append(window)
            window.orderFrontRegardless()
        }
    }

    func hideOverlay() {
        for window in overlayWindows {
            window.orderOut(nil)
            window.contentView = nil
        }
        overlayWindows.removeAll()
    }

    /// Fades out overlay windows over `duration` seconds, then removes them.
    func fadeOutAndHideOverlay(duration: TimeInterval = 0.4) {
        let windowsToFade = overlayWindows
        overlayWindows.removeAll()

        NSAnimationContext.runAnimationGroup({ context in
            context.duration = duration
            context.timingFunction = CAMediaTimingFunction(name: .easeIn)
            for window in windowsToFade {
                window.animator().alphaValue = 0
            }
        }, completionHandler: {
            for window in windowsToFade {
                window.orderOut(nil)
                window.contentView = nil
            }
        })
    }

    func isShowingOverlay() -> Bool {
        return !overlayWindows.isEmpty
    }
}
