//
//  CompanionManager.swift
//  leanring-buddy
//
//  Central state manager for the companion voice mode. Owns the push-to-talk
//  pipeline (dictation manager + global shortcut monitor + overlay) and
//  exposes observable voice state for the panel UI.
//

import AVFoundation
import Combine
import Foundation
import ScreenCaptureKit
import SwiftUI

enum CompanionVoiceState {
    case idle
    case listening
    case processing
    case responding
}

@MainActor
final class CompanionManager: ObservableObject {
    @Published private(set) var voiceState: CompanionVoiceState = .idle
    @Published private(set) var lastTranscript: String?
    @Published private(set) var currentAudioPowerLevel: CGFloat = 0
    @Published private(set) var hasAccessibilityPermission = false
    @Published private(set) var hasScreenRecordingPermission = false
    @Published private(set) var hasMicrophonePermission = false
    @Published private(set) var hasScreenContentPermission = false

    /// Screen location (global AppKit coords) of a detected UI element the
    /// buddy should fly to and point at. Parsed from Claude's response;
    /// observed by CompanionOverlayView to trigger the flight animation.
    @Published var detectedElementScreenLocation: CGPoint?
    /// The display frame (global AppKit coords) of the screen the detected
    /// element is on, so CompanionOverlayView knows which screen overlay should animate.
    @Published var detectedElementDisplayFrame: CGRect?
    /// The rect (global AppKit coords) the skin's pointing mark is drawn
    /// around. Set to a small box centred on the point before the location,
    /// then replaced by the Accessibility element's bounds when the lookup
    /// (which runs while the reply is spoken) finds one.
    @Published var detectedElementTargetRect: CGRect?
    /// Drops Accessibility lookups that finish after their pointing ended.
    private var pointingRequestCounter = PointingRequestCounter()

    /// The reply shown as text beside the companion (Voice + text or Text
    /// only), and when it appeared so the overlay can reveal it gradually.
    @Published private(set) var replyBubbleText: String?
    @Published private(set) var replyBubbleShownAt = Date()
    private var replyBubbleHideTask: Task<Void, Never>?

    /// True while the companion should get out of the way: the user is
    /// typing, the mouse is still, or a full-screen app is in front.
    @Published private(set) var isCompanionAutoHidden = false
    private let companionAutoHideMonitor = CompanionAutoHideMonitor()
    /// Asks Electron apps to build their Accessibility tree as they come to
    /// the front, so pointing can hug real elements in them.
    private let accessibilityTreeActivator = AccessibilityTreeActivator()
    /// Custom speech bubble text for the pointing animation. When set,
    /// CompanionOverlayView uses this instead of a random pointer phrase.
    @Published var detectedElementBubbleText: String?

    // MARK: - Onboarding Prompt Bubble

    /// Text streamed character-by-character next to the companion after the first-run welcome.
    @Published var onboardingPromptText: String = ""
    @Published var onboardingPromptOpacity: Double = 0.0
    @Published var showOnboardingPrompt: Bool = false




    let buddyDictationManager = BuddyDictationManager()
    let globalPushToTalkShortcutMonitor = GlobalPushToTalkShortcutMonitor()
    let overlayWindowManager = OverlayWindowManager()
    // Response text is now displayed inline on the cursor overlay via
    // streamingResponseText, so no separate response overlay manager is needed.

    /// Where provider / model / voice choices live. Observed so the clients
    /// below are rebuilt whenever the user changes something in Settings.
    let appSettings = AppSettings.shared

    /// Vision-chat backend (OpenRouter, Ollama, Anthropic, or custom). Calls
    /// the API directly with a key from the Keychain — no proxy.
    private var chatClient: any ChatClient = ChatClientFactory.makeClient(from: AppSettings.shared)

    /// Text-to-speech backend (Kokoro on-device by default; Apple and ElevenLabs selectable).
    private var textToSpeechClient: any TTSClient = TTSClientFactory.makeClient(from: AppSettings.shared)

    /// Profile + daily notes on disk, injected into the system prompt.
    private let memoryManager = MemoryManager.shared

    private var settingsObservationCancellables: Set<AnyCancellable> = []

    /// Recreates the chat and TTS clients from the current settings. Called
    /// automatically on settings changes and by the panel after a key is saved
    /// (keys live in the Keychain, so settings publishers don't see them change).
    func rebuildClientsFromSettings() {
        textToSpeechClient.stopPlayback()
        chatClient = ChatClientFactory.makeClient(from: appSettings)
        textToSpeechClient = TTSClientFactory.makeClient(from: appSettings)
        print("🔧 Clients rebuilt — chat: \(appSettings.chatProviderKind.displayName) [\(appSettings.chatModel)], tts: \(appSettings.textToSpeechProviderKind.displayName)")
    }

    /// Text fields publish on every keystroke, so changes are debounced before
    /// tearing down and recreating the network clients.
    private func bindSettingsObservation() {
        let chatSettingsChanged = Publishers.Merge3(
            appSettings.$chatProviderKind.map { _ in () },
            appSettings.$chatBaseURL.map { _ in () },
            appSettings.$chatModel.map { _ in () }
        )
        let voiceSettingsChanged = Publishers.Merge4(
            appSettings.$textToSpeechProviderKind.map { _ in () },
            appSettings.$appleVoiceIdentifier.map { _ in () },
            appSettings.$elevenLabsVoiceID.map { _ in () },
            appSettings.$kokoroVoice.map { _ in () }
        )

        Publishers.Merge(chatSettingsChanged, voiceSettingsChanged)
            .dropFirst(7) // skip the initial value each of the seven publishers emits on subscribe
            .debounce(for: .milliseconds(400), scheduler: DispatchQueue.main)
            .sink { [weak self] in
                self?.rebuildClientsFromSettings()
            }
            .store(in: &settingsObservationCancellables)

        appSettings.$speechToTextProviderKind
            .dropFirst()
            .removeDuplicates()
            .sink { [weak self] _ in
                self?.buddyDictationManager.reloadTranscriptionProviderFromSettings()
            }
            .store(in: &settingsObservationCancellables)
    }

    /// Conversation history so Claude remembers prior exchanges within a session.
    /// Each entry is the user's transcript and Claude's response.
    private var conversationHistory: [(userTranscript: String, assistantResponse: String)] = []

    /// The currently running AI response task, if any. Cancelled when the user
    /// speaks again so a new response can begin immediately.
    private var currentResponseTask: Task<Void, Never>?

    private var shortcutTransitionCancellable: AnyCancellable?
    private var voiceStateCancellable: AnyCancellable?
    private var audioPowerCancellable: AnyCancellable?
    private var accessibilityCheckTimer: Timer?
    private var pendingKeyboardShortcutStartTask: Task<Void, Never>?
    /// Scheduled hide for transient cursor mode — cancelled if the user
    /// speaks again before the delay elapses.
    private var transientHideTask: Task<Void, Never>?

    /// True when all three required permissions (accessibility, screen recording,
    /// microphone) are granted. Used by the panel to show a single "all good" state.
    var allPermissionsGranted: Bool {
        hasAccessibilityPermission && hasScreenRecordingPermission && hasMicrophonePermission && hasScreenContentPermission
    }

    /// Whether the companion overlay is currently visible on screen.
    /// Used by the panel to show accurate status text ("Active" vs "Ready").
    @Published private(set) var isOverlayVisible: Bool = false

    /// User preference for whether the Lumen cursor should be shown.
    /// When toggled off, the overlay is hidden and push-to-talk is disabled.
    /// Persisted to UserDefaults so the choice survives app restarts.
    @Published var isLumenCursorEnabled: Bool = UserDefaults.standard.object(forKey: "isLumenCursorEnabled") == nil
        ? true
        : UserDefaults.standard.bool(forKey: "isLumenCursorEnabled")

    func setLumenCursorEnabled(_ enabled: Bool) {
        isLumenCursorEnabled = enabled
        UserDefaults.standard.set(enabled, forKey: "isLumenCursorEnabled")
        transientHideTask?.cancel()
        transientHideTask = nil

        if enabled {
            overlayWindowManager.hasShownOverlayBefore = true
            overlayWindowManager.showOverlay(onScreens: NSScreen.screens, companionManager: self)
            isOverlayVisible = true
        } else {
            overlayWindowManager.hideOverlay()
            isOverlayVisible = false
        }
    }

    /// Whether the user has completed onboarding at least once. Persisted
    /// to UserDefaults so the Start button only appears on first launch.
    var hasCompletedOnboarding: Bool {
        get { UserDefaults.standard.bool(forKey: "hasCompletedOnboarding") }
        set { UserDefaults.standard.set(newValue, forKey: "hasCompletedOnboarding") }
    }

    func start() {
        refreshAllPermissions()
        print("🔑 Lumen start — accessibility: \(hasAccessibilityPermission), screen: \(hasScreenRecordingPermission), mic: \(hasMicrophonePermission), screenContent: \(hasScreenContentPermission), onboarded: \(hasCompletedOnboarding)")
        startPermissionPolling()
        bindVoiceStateObservation()
        bindAudioPowerLevel()
        bindShortcutTransitions()
        bindSettingsObservation()
        memoryManager.prepareAtLaunch()
        startCompanionAutoHide()
        accessibilityTreeActivator.start()

        // If the user already completed onboarding AND all permissions are
        // still granted, show the cursor overlay immediately. If permissions
        // were revoked (e.g. signing change), don't show the cursor — the
        // panel will show the permissions UI instead.
        if hasCompletedOnboarding && allPermissionsGranted && isLumenCursorEnabled {
            overlayWindowManager.hasShownOverlayBefore = true
            overlayWindowManager.showOverlay(onScreens: NSScreen.screens, companionManager: self)
            isOverlayVisible = true
        }
    }

    /// The interim first run (a proper Lumen onboarding is designed later):
    /// dismisses the panel and shows the overlay for the first time, which
    /// types the skinned welcome and then the "press control + option" prompt.
    func triggerOnboarding() {
        // Post notification so the panel manager can dismiss the panel
        NotificationCenter.default.post(name: .lumenDismissPanel, object: nil)

        // Mark onboarding as completed so the Start button won't appear
        // again on future launches — the cursor will auto-show instead
        hasCompletedOnboarding = true

        LumenAnalytics.trackOnboardingStarted()

        // Show the overlay for the first time — isFirstAppearance triggers
        // the welcome animation and then the prompt bubble
        overlayWindowManager.showOverlay(onScreens: NSScreen.screens, companionManager: self)
        isOverlayVisible = true
    }

    // MARK: - Reply Text Bubble

    private func showReplyBubble(_ replyText: String) {
        replyBubbleHideTask?.cancel()
        replyBubbleShownAt = Date()
        replyBubbleText = replyText
    }

    private func hideReplyBubble(afterSeconds delaySeconds: Double) {
        replyBubbleHideTask?.cancel()
        replyBubbleHideTask = Task {
            try? await Task.sleep(for: .seconds(delaySeconds))
            guard !Task.isCancelled else { return }
            withAnimation(.easeOut(duration: 0.3)) {
                replyBubbleText = nil
            }
        }
    }

    private func clearReplyBubble() {
        replyBubbleHideTask?.cancel()
        replyBubbleText = nil
    }

    // MARK: - Companion Auto-Hide

    private func startCompanionAutoHide() {
        companionAutoHideMonitor.isLumenBusy = { [weak self] in
            guard let self else { return false }
            return self.voiceState != .idle
                || self.detectedElementScreenLocation != nil
                || self.replyBubbleText != nil
                || self.showOnboardingPrompt
        }
        companionAutoHideMonitor.onShouldHideChange = { [weak self] shouldHide in
            self?.isCompanionAutoHidden = shouldHide
        }
        companionAutoHideMonitor.start()
    }

    func clearDetectedElementLocation() {
        pointingRequestCounter.invalidateCurrentRequest()
        detectedElementScreenLocation = nil
        detectedElementDisplayFrame = nil
        detectedElementTargetRect = nil
        detectedElementBubbleText = nil
    }

    func stop() {
        globalPushToTalkShortcutMonitor.stop()
        buddyDictationManager.cancelCurrentDictation()
        overlayWindowManager.hideOverlay()
        transientHideTask?.cancel()

        currentResponseTask?.cancel()
        currentResponseTask = nil
        shortcutTransitionCancellable?.cancel()
        voiceStateCancellable?.cancel()
        audioPowerCancellable?.cancel()
        accessibilityCheckTimer?.invalidate()
        accessibilityCheckTimer = nil
    }

    func refreshAllPermissions() {
        let previouslyHadAccessibility = hasAccessibilityPermission
        let previouslyHadScreenRecording = hasScreenRecordingPermission
        let previouslyHadMicrophone = hasMicrophonePermission
        let previouslyHadAll = allPermissionsGranted

        let currentlyHasAccessibility = WindowPositionManager.hasAccessibilityPermission()
        hasAccessibilityPermission = currentlyHasAccessibility

        if currentlyHasAccessibility {
            globalPushToTalkShortcutMonitor.start()
        } else {
            globalPushToTalkShortcutMonitor.stop()
        }

        hasScreenRecordingPermission = WindowPositionManager.hasScreenRecordingPermission()

        let micAuthStatus = AVCaptureDevice.authorizationStatus(for: .audio)
        hasMicrophonePermission = micAuthStatus == .authorized

        // Debug: log permission state on changes
        if previouslyHadAccessibility != hasAccessibilityPermission
            || previouslyHadScreenRecording != hasScreenRecordingPermission
            || previouslyHadMicrophone != hasMicrophonePermission {
            print("🔑 Permissions — accessibility: \(hasAccessibilityPermission), screen: \(hasScreenRecordingPermission), mic: \(hasMicrophonePermission), screenContent: \(hasScreenContentPermission)")
        }

        // Track individual permission grants as they happen
        if !previouslyHadAccessibility && hasAccessibilityPermission {
            LumenAnalytics.trackPermissionGranted(permission: "accessibility")
        }
        if !previouslyHadScreenRecording && hasScreenRecordingPermission {
            LumenAnalytics.trackPermissionGranted(permission: "screen_recording")
        }
        if !previouslyHadMicrophone && hasMicrophonePermission {
            LumenAnalytics.trackPermissionGranted(permission: "microphone")
        }
        // Screen content permission is persisted — once the user has approved the
        // SCShareableContent picker, we don't need to re-check it.
        if !hasScreenContentPermission {
            hasScreenContentPermission = UserDefaults.standard.bool(forKey: "hasScreenContentPermission")
        }

        if !previouslyHadAll && allPermissionsGranted {
            LumenAnalytics.trackAllPermissionsGranted()
        }
    }

    /// Triggers the macOS screen content picker by performing a dummy
    /// screenshot capture. Once the user approves, we persist the grant
    /// so they're never asked again during onboarding.
    @Published private(set) var isRequestingScreenContent = false

    func requestScreenContentPermission() {
        guard !isRequestingScreenContent else { return }
        isRequestingScreenContent = true
        Task {
            do {
                let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
                guard let display = content.displays.first else {
                    await MainActor.run { isRequestingScreenContent = false }
                    return
                }
                let filter = SCContentFilter(display: display, excludingWindows: [])
                let config = SCStreamConfiguration()
                config.width = 320
                config.height = 240
                let image = try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config)
                // Verify the capture actually returned real content — a 0x0 or
                // fully-empty image means the user denied the prompt.
                let didCapture = image.width > 0 && image.height > 0
                print("🔑 Screen content capture result — width: \(image.width), height: \(image.height), didCapture: \(didCapture)")
                await MainActor.run {
                    isRequestingScreenContent = false
                    guard didCapture else { return }
                    hasScreenContentPermission = true
                    UserDefaults.standard.set(true, forKey: "hasScreenContentPermission")
                    LumenAnalytics.trackPermissionGranted(permission: "screen_content")

                    // If onboarding was already completed, show the cursor overlay now
                    if hasCompletedOnboarding && allPermissionsGranted && !isOverlayVisible && isLumenCursorEnabled {
                        overlayWindowManager.hasShownOverlayBefore = true
                        overlayWindowManager.showOverlay(onScreens: NSScreen.screens, companionManager: self)
                        isOverlayVisible = true
                    }
                }
            } catch {
                print("⚠️ Screen content permission request failed: \(error)")
                await MainActor.run { isRequestingScreenContent = false }
            }
        }
    }

    // MARK: - Private

    /// Triggers the system microphone prompt if the user has never been asked.
    /// Once granted/denied the status sticks and polling picks it up.
    private func promptForMicrophoneIfNotDetermined() {
        guard AVCaptureDevice.authorizationStatus(for: .audio) == .notDetermined else { return }
        AVCaptureDevice.requestAccess(for: .audio) { [weak self] granted in
            Task { @MainActor [weak self] in
                self?.hasMicrophonePermission = granted
            }
        }
    }

    /// Polls all permissions frequently so the UI updates live after the
    /// user grants them in System Settings. Screen Recording is the exception —
    /// macOS requires an app restart for that one to take effect.
    private func startPermissionPolling() {
        accessibilityCheckTimer = Timer.scheduledTimer(withTimeInterval: 1.5, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.refreshAllPermissions()
            }
        }
    }

    private func bindAudioPowerLevel() {
        audioPowerCancellable = buddyDictationManager.$currentAudioPowerLevel
            .receive(on: DispatchQueue.main)
            .sink { [weak self] powerLevel in
                self?.currentAudioPowerLevel = powerLevel
            }
    }

    private func bindVoiceStateObservation() {
        voiceStateCancellable = buddyDictationManager.$isRecordingFromKeyboardShortcut
            .combineLatest(
                buddyDictationManager.$isFinalizingTranscript,
                buddyDictationManager.$isPreparingToRecord
            )
            .receive(on: DispatchQueue.main)
            .sink { [weak self] isRecording, isFinalizing, isPreparing in
                guard let self else { return }
                // Don't override .responding — the AI response pipeline
                // manages that state directly until streaming finishes.
                guard self.voiceState != .responding else { return }

                if isFinalizing {
                    self.voiceState = .processing
                } else if isRecording {
                    self.voiceState = .listening
                } else if isPreparing {
                    self.voiceState = .processing
                } else {
                    self.voiceState = .idle
                    // If the user pressed and released the hotkey without
                    // saying anything, no response task runs — schedule the
                    // transient hide here so the overlay doesn't get stuck.
                    // Only do this when no response is in flight, otherwise
                    // the brief idle gap between recording and processing
                    // would prematurely hide the overlay.
                    if self.currentResponseTask == nil {
                        self.scheduleTransientHideIfNeeded()
                    }
                }
            }
    }

    private func bindShortcutTransitions() {
        shortcutTransitionCancellable = globalPushToTalkShortcutMonitor
            .shortcutTransitionPublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] transition in
                self?.handleShortcutTransition(transition)
            }
    }

    private func handleShortcutTransition(_ transition: BuddyPushToTalkShortcut.ShortcutTransition) {
        switch transition {
        case .pressed:
            guard !buddyDictationManager.isDictationInProgress else { return }


            // Cancel any pending transient hide so the overlay stays visible
            transientHideTask?.cancel()
            transientHideTask = nil

            // If the cursor is hidden, bring it back transiently for this interaction
            if !isLumenCursorEnabled && !isOverlayVisible {
                overlayWindowManager.hasShownOverlayBefore = true
                overlayWindowManager.showOverlay(onScreens: NSScreen.screens, companionManager: self)
                isOverlayVisible = true
            }

            // Dismiss the menu bar panel so it doesn't cover the screen
            NotificationCenter.default.post(name: .lumenDismissPanel, object: nil)

            // Cancel any in-progress response and TTS from a previous utterance
            currentResponseTask?.cancel()
            textToSpeechClient.stopPlayback()
            clearDetectedElementLocation()
            clearReplyBubble()

            // Dismiss the onboarding prompt if it's showing
            if showOnboardingPrompt {
                withAnimation(.easeOut(duration: 0.3)) {
                    onboardingPromptOpacity = 0.0
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                    self.showOnboardingPrompt = false
                    self.onboardingPromptText = ""
                }
            }
    

            LumenAnalytics.trackPushToTalkStarted()

            pendingKeyboardShortcutStartTask?.cancel()
            pendingKeyboardShortcutStartTask = Task {
                await buddyDictationManager.startPushToTalkFromKeyboardShortcut(
                    currentDraftText: "",
                    updateDraftText: { _ in
                        // Partial transcripts are hidden (waveform-only UI)
                    },
                    submitDraftText: { [weak self] finalTranscript in
                        self?.lastTranscript = finalTranscript
                        print("🗣️ Companion received transcript: \(finalTranscript)")
                        LumenAnalytics.trackUserMessageSent(transcript: finalTranscript)
                        self?.sendTranscriptToClaudeWithScreenshot(transcript: finalTranscript)
                    }
                )
            }
        case .released:
            // Cancel the pending start task in case the user released the shortcut
            // before the async startPushToTalk had a chance to begin recording.
            // Without this, a quick press-and-release drops the release event and
            // leaves the waveform overlay stuck on screen indefinitely.
            LumenAnalytics.trackPushToTalkReleased()
            pendingKeyboardShortcutStartTask?.cancel()
            pendingKeyboardShortcutStartTask = nil
            buddyDictationManager.stopPushToTalkFromKeyboardShortcut()
        case .none:
            break
        }
    }

    // MARK: - Companion Prompt

    private static let companionVoiceResponseSystemPrompt = """
    you're lumen, a friendly always-on companion that lives in the user's menu bar. the user just spoke to you via push-to-talk and you can see their screen(s). your reply will be spoken aloud via text-to-speech, so write the way you'd actually talk. this is an ongoing conversation — you remember everything they've said before.

    rules:
    - default to one or two sentences. be direct and dense. BUT if the user asks you to explain more, go deeper, or elaborate, then go all out — give a thorough, detailed explanation with no length limit.
    - all lowercase, casual, warm. no emojis.
    - write for the ear, not the eye. short sentences. no lists, bullet points, markdown, or formatting — just natural speech.
    - don't use abbreviations or symbols that sound weird read aloud. write "for example" not "e.g.", spell out small numbers.
    - if the user's question relates to what's on their screen, reference specific things you see.
    - if the screenshot doesn't seem relevant to their question, just answer the question directly.
    - you can help with anything — coding, writing, general knowledge, brainstorming.
    - never say "simply" or "just".
    - don't read out code verbatim. describe what the code does or what needs to change conversationally.
    - focus on giving a thorough, useful explanation. don't end with simple yes/no questions like "want me to explain more?" or "should i show you?" — those are dead ends that force the user to just say yes.
    - instead, when it fits naturally, end by planting a seed — mention something bigger or more ambitious they could try, a related concept that goes deeper, or a next-level technique that builds on what you just explained. make it something worth coming back for, not a question they'd just nod to. it's okay to not end with anything extra if the answer is complete on its own.
    - if you receive multiple screen images, the one labeled "primary focus" is where the cursor is — prioritize that one but reference others if relevant.

    element pointing:
    you can point at things on the user's screen: your companion flies there and marks the element. use it whenever pointing would genuinely help the user — if they're asking how to do something, looking for a menu, trying to find a button, or need help navigating an app, point at the relevant element. err on the side of pointing rather than not pointing, because it makes your help way more useful and concrete.

    don't point at things when it would be pointless — like if the user asks a general knowledge question, or the conversation has nothing to do with what's on screen, or you'd just be pointing at something obvious they're already looking at. but if there's a specific UI element, menu, button, or area on screen that's relevant to what you're helping with, point at it.

    when you point, append a coordinate tag at the very end of your response, AFTER your spoken text. give coordinates on a 0-1000 grid laid over the screenshot: 0,0 is the top-left corner and 1000,1000 is the bottom-right corner, whatever the image's pixel size. x increases rightward, y increases downward.

    format: [POINT:x,y:label] where x,y are integers from 0 to 1000 on that grid, and label is a short 1-3 word description of the element (like "search bar" or "save button"). if the element is on the cursor's screen you can omit the screen number. if the element is on a DIFFERENT screen, append :screenN where N is the screen number from the image label (e.g. :screen2). this is important — without the screen number, the cursor will point at the wrong place.

    if pointing wouldn't help, append [POINT:none].

    examples:
    - user asks how to color grade in final cut: "you'll want to open the color inspector — it's right up in the top right area of the toolbar. click that and you'll get all the color wheels and curves. [POINT:859,51:color inspector]"
    - user asks what html is: "html stands for hypertext markup language, it's basically the skeleton of every web page. curious how it connects to the css you're looking at? [POINT:none]"
    - user asks how to commit in xcode: "see that source control menu up top? click that and hit commit, or you can use command option c as a shortcut. [POINT:223,13:source control]"
    - element is on screen 2 (not where cursor is): "that's over on your other monitor — see the terminal window? [POINT:313,361:terminal:screen2]"
    """

    /// Appended to the prompt above only while memory is on. The dynamic
    /// profile/notes block from MemoryManager follows it.
    private static let companionMemoryInstructionsSystemPrompt = """
    memory:
    you have a long-term memory about the user. it appears below under "what you know about the user" and "recent notes". use it to be personal and specific and recall things naturally when they're relevant, the way a friend would. never read your memory out unprompted, never list what you know, and never mention that you have a memory file, notes, or a profile. if they ask what you remember about something, answer from memory in your own words.

    saving memories: when the user tells you something worth keeping (a fact about them, a project, a tool they use, a preference, or anything they say "remember that…" about), add a tag to your reply: [REMEMBER:Section:fact] where Section is one of About me, Projects, Tools, Preferences, Notes and fact is one short sentence about the user in third person. the tag is removed before your reply is spoken, so also acknowledge it in words. one tag per fact; several tags are fine. don't save things you only see on screen unless the user asked you to remember them, and never save passwords, keys, or other secrets.

    forgetting: when the user asks you to forget something, add [FORGET:text] where text is the fact as closely as you remember it. the app removes the matching line and will add what was forgotten to your reply, so don't describe what you forgot yourself.

    put memory tags right before the point tag, at the end of your reply.

    examples:
    - user: "remember that my cat is called mochi" → "mochi, great name. noted. [REMEMBER:About me:has a cat called mochi] [POINT:none]"
    - user: "i've switched from vscode to zed by the way" → "nice, zed's quick. i'll keep that in mind. [REMEMBER:Tools:uses zed as their editor, switched from vscode] [POINT:none]"
    - user: "remember to ship the demo on friday" → "on it. [REMEMBER:Notes:wants to ship the demo on friday] [POINT:none]"
    - user: "forget what i said about the cat" → "sure, dropping that. [FORGET:has a cat called mochi] [POINT:none]"
    - user: "what's my cat called again?" → "mochi, unless there's been a rename. [POINT:none]"
    """

    /// The base prompt, plus the memory instructions and the current memory
    /// block when memory is on.
    private static func makeCompanionSystemPrompt(memoryPromptBlock: String?, isMemoryEnabled: Bool) -> String {
        guard isMemoryEnabled else { return companionVoiceResponseSystemPrompt }
        var prompt = companionVoiceResponseSystemPrompt + "\n\n" + companionMemoryInstructionsSystemPrompt
        if let memoryPromptBlock, !memoryPromptBlock.isEmpty {
            prompt += "\n\n" + memoryPromptBlock
        }
        return prompt
    }

    // MARK: - AI Response Pipeline

    /// Captures a screenshot, sends it along with the transcript to the
    /// configured chat model, and plays the response aloud via the configured
    /// TTS client. The cursor stays in the spinner/processing state until TTS
    /// audio begins playing. The response may include a [POINT:x,y:label] tag
    /// which triggers the buddy to fly to that element on screen.
    private func sendTranscriptToClaudeWithScreenshot(transcript: String) {
        currentResponseTask?.cancel()
        textToSpeechClient.stopPlayback()

        // Read before any await: the panel and overlay never activate, so the
        // frontmost app is the one the user was actually working in.
        let frontmostApplicationName = NSWorkspace.shared.frontmostApplication?.localizedName ?? "unknown app"

        currentResponseTask = Task {
            // Stay in processing (spinner) state — no streaming text displayed
            voiceState = .processing

            do {
                // Memory retrieval (an embedding call to Ollama) runs alongside
                // the screenshot so it adds no latency of its own.
                let memoryPromptBlockTask = Task { await memoryManager.memoryPromptBlock(forQuestion: transcript) }

                // Capture all connected screens so the AI has full context
                let screenCaptures = try await CompanionScreenCaptureUtility.captureAllScreensAsJPEG()

                guard !Task.isCancelled else {
                    memoryPromptBlockTask.cancel()
                    return
                }
                let memoryPromptBlock = await memoryPromptBlockTask.value

                // Build image labels with the actual screenshot pixel dimensions
                // so Claude's coordinate space matches the image it sees. We
                // scale from screenshot pixels to display points ourselves.
                // No pixel size in the label: [POINT] uses a 0-1000 grid, and a
                // pixel size invites the model to answer in pixels instead.
                let labeledImages = screenCaptures.map { capture in
                    (data: capture.imageData, label: capture.label)
                }

                // Pass conversation history so Claude remembers prior exchanges
                let historyForAPI = conversationHistory.map { entry in
                    (userPlaceholder: entry.userTranscript, assistantResponse: entry.assistantResponse)
                }

                let (fullResponseText, _) = try await chatClient.analyzeImageStreaming(
                    images: labeledImages,
                    systemPrompt: Self.makeCompanionSystemPrompt(
                        memoryPromptBlock: memoryPromptBlock,
                        isMemoryEnabled: memoryManager.isMemoryEnabled
                    ),
                    conversationHistory: historyForAPI,
                    userPrompt: transcript,
                    onTextChunk: { _ in
                        // No streaming text display — spinner stays until TTS plays
                    }
                )

                guard !Task.isCancelled else { return }

                // Memory tags first (they can be anywhere), then the [POINT:...]
                // tag, whose parser needs it to be the last thing in the text.
                let memoryTagParseResult = MemoryTagParser.parse(fullResponseText)
                let parseResult = Self.parsePointingCoordinates(from: memoryTagParseResult.textWithoutMemoryTags)
                var spokenText = parseResult.spokenText

                // Write remembered facts / forget lines now; a [FORGET] adds
                // "forgot: …" to what gets spoken.
                let memoryWriteOutcome = await memoryManager.applyMemoryTags(memoryTagParseResult, transcript: transcript)
                // The user may have pressed the hotkey again during that await.
                try Task.checkCancellation()
                if let spokenConfirmation = memoryWriteOutcome.spokenConfirmation {
                    spokenText = spokenText.isEmpty ? spokenConfirmation : spokenText + " " + spokenConfirmation
                }

                // Handle element pointing if the model returned coordinates.
                // The overlay shows the companion in flight whatever the voice
                // state is (CompanionVisualState.flying wins), so the voice
                // state is left alone here.
                // Pick the screen capture matching Claude's screen number,
                // falling back to the cursor screen if not specified.
                let targetScreenCapture: CompanionScreenCapture? = {
                    if let screenNumber = parseResult.screenNumber,
                       screenNumber >= 1 && screenNumber <= screenCaptures.count {
                        return screenCaptures[screenNumber - 1]
                    }
                    return screenCaptures.first(where: { $0.isCursorScreen })
                }()

                if let pointCoordinate = parseResult.coordinate,
                   let targetScreenCapture {
                    // The model's coordinates are on a 0-1000 grid over the
                    // screenshot (see PointingGeometry.pointingGridSize). Scale
                    // to the display's points (e.g. 1512x982), then convert to
                    // AppKit global coords.
                    let displayWidth = CGFloat(targetScreenCapture.displayWidthInPoints)
                    let displayHeight = CGFloat(targetScreenCapture.displayHeightInPoints)
                    let displayFrame = targetScreenCapture.displayFrame

                    let displayLocalPoint = PointingGeometry.displayLocalPoint(
                        fromGridPoint: pointCoordinate,
                        displaySize: CGSize(width: displayWidth, height: displayHeight)
                    )

                    // Convert from top-left origin (screenshot) to bottom-left origin (AppKit)
                    let appKitY = displayHeight - displayLocalPoint.y

                    // Convert display-local coords to global screen coords
                    let globalLocation = CGPoint(
                        x: displayLocalPoint.x + displayFrame.origin.x,
                        y: appKitY + displayFrame.origin.y
                    )

                    // Start the flight now, toward a small box around the point,
                    // so speech never waits on Accessibility. The rect and bubble
                    // text are set before the location, because setting the
                    // location starts the flight.
                    let pointingRequestNumber = pointingRequestCounter.beginRequest()
                    detectedElementTargetRect = ElementBoundsSelection.fallbackResolution(
                        appKitGlobalPoint: globalLocation,
                        displayFrame: displayFrame
                    ).rectInAppKitGlobal
                    detectedElementBubbleText = PointingBubbleText.bubbleText(
                        elementLabel: parseResult.elementLabel,
                        fallbackPhraseIndex: Int.random(in: 0..<PointingBubbleText.fallbackPhrases.count)
                    )
                    detectedElementScreenLocation = globalLocation
                    detectedElementDisplayFrame = displayFrame

                    // Then snap the mark to the real element under the point
                    // while the reply is already being spoken. The overlay
                    // retargets the flight (or the parked companion) when the
                    // rect changes. The lookup is not tied to this reply's task,
                    // so the request number drops a result that arrives after
                    // this pointing ended or a new push-to-talk began.
                    let lookupStartedAt = ContinuousClock.now
                    Task {
                        let targetRectResolution = await AccessibilityElementBoundsResolver.resolveTargetRect(
                            atAppKitGlobalPoint: globalLocation,
                            displayFrame: displayFrame,
                            pointingLabel: parseResult.elementLabel
                        )
                        let lookupDuration = ContinuousClock.now - lookupStartedAt
                        guard self.pointingRequestCounter.isCurrent(pointingRequestNumber) else {
                            print("🎯 Target rect dropped (pointing already ended) after \(lookupDuration)")
                            return
                        }
                        print("🎯 Target rect: \(targetRectResolution.source) \(targetRectResolution.rectInAppKitGlobal) after \(lookupDuration)")
                        if targetRectResolution.source != .fallbackBox {
                            self.detectedElementTargetRect = targetRectResolution.rectInAppKitGlobal
                        }
                    }

                    LumenAnalytics.trackElementPointed(elementLabel: parseResult.elementLabel)
                    print("🎯 Element pointing: (\(Int(pointCoordinate.x)), \(Int(pointCoordinate.y))) → \"\(parseResult.elementLabel ?? "element")\"")
                } else {
                    print("🎯 Element pointing: \(parseResult.elementLabel ?? "no element")")
                }

                // Save this exchange to conversation history (with the point tag
                // stripped so it doesn't confuse future context)
                conversationHistory.append((
                    userTranscript: transcript,
                    assistantResponse: spokenText
                ))

                // Keep only the last 10 exchanges to avoid unbounded context growth
                if conversationHistory.count > 10 {
                    conversationHistory.removeFirst(conversationHistory.count - 10)
                }

                print("🧠 Conversation history: \(conversationHistory.count) exchanges")

                LumenAnalytics.trackAIResponseReceived(response: spokenText)

                let replyDisplayMode = appSettings.replyDisplayMode
                let hasReplyText = !spokenText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                if replyDisplayMode.showsReplyText && hasReplyText {
                    showReplyBubble(spokenText)
                }

                // Play the response via TTS. Keep the spinner (processing state)
                // until the audio actually starts playing, then switch to responding.
                // Text only: no voice; the companion shows its speaking state
                // while the text is on screen.
                if !replyDisplayMode.speaksReply && hasReplyText {
                    voiceState = .responding
                } else if hasReplyText {
                    do {
                        try await textToSpeechClient.speakText(spokenText)
                        // speakText returns once audio is playing
                        voiceState = .responding
                    } catch is CancellationError {
                        // The user spoke again while the voice was loading or
                        // synthesizing: not a TTS failure, and not an exchange
                        // worth logging. Let the outer handler end the task.
                        throw CancellationError()
                    } catch {
                        LumenAnalytics.trackTTSError(error: error.localizedDescription)
                        print("⚠️ TTS error: \(error)")
                        speakErrorFallback("i couldn't play that reply out loud. check the text to speech settings.")
                    }
                }

                guard !Task.isCancelled else { return }

                // Audio is already playing; the daily-note line is written in
                // the background and never delays speech.
                memoryManager.recordExchange(
                    question: transcript,
                    spokenReply: spokenText,
                    frontmostApplicationName: frontmostApplicationName
                )

                // speakText returned when audio started; stay in the speaking
                // state (the companion's speaking animation) until the reply
                // has actually finished playing.
                if voiceState == .responding {
                    if replyDisplayMode.speaksReply {
                        try await SpeechPlaybackWaiter.waitUntilPlaybackEnds {
                            self.textToSpeechClient.isPlaying
                        }
                    } else {
                        try await Task.sleep(for: .seconds(ReplyTextTiming.textOnlyHoldSeconds(characterCount: spokenText.count)))
                    }
                }
                hideReplyBubble(afterSeconds: replyDisplayMode.speaksReply ? ReplyTextTiming.secondsShownAfterSpeechEnds : 0)
            } catch is CancellationError {
                // User spoke again — response was interrupted
            } catch {
                LumenAnalytics.trackResponseError(error: error.localizedDescription)
                print("⚠️ Companion response error: \(error)")
                speakErrorFallback("i couldn't reach the model. check the provider and api key in settings.")
                // The model never saw it, so keep a spoken "remember that…" anyway.
                await memoryManager.applyTranscriptFallbackIfNeeded(transcript)
            }

            if !Task.isCancelled {
                voiceState = .idle
                scheduleTransientHideIfNeeded()
            }
        }
    }

    /// If the cursor is in transient mode (user toggled "Show Lumen" off),
    /// waits for TTS playback and any pointing animation to finish, then
    /// fades out the overlay after a 1-second pause. Cancelled automatically
    /// if the user starts another push-to-talk interaction.
    private func scheduleTransientHideIfNeeded() {
        guard !isLumenCursorEnabled && isOverlayVisible else { return }

        transientHideTask?.cancel()
        transientHideTask = Task {
            // Wait for TTS audio to finish playing
            while textToSpeechClient.isPlaying {
                try? await Task.sleep(nanoseconds: 200_000_000)
                guard !Task.isCancelled else { return }
            }

            // Wait for pointing animation to finish (location is cleared
            // when the buddy flies back to the cursor)
            while detectedElementScreenLocation != nil {
                try? await Task.sleep(nanoseconds: 200_000_000)
                guard !Task.isCancelled else { return }
            }

            // Pause 1s after everything finishes, then fade out
            try? await Task.sleep(nanoseconds: 1_000_000_000)
            guard !Task.isCancelled else { return }
            overlayWindowManager.fadeOutAndHideOverlay()
            isOverlayVisible = false
        }
    }

    /// Speaks an error message using the always-available macOS system
    /// synthesizer, so the user hears something even when the configured
    /// chat or TTS backend is down or misconfigured.
    private func speakErrorFallback(_ errorMessage: String) {
        let synthesizer = NSSpeechSynthesizer()
        synthesizer.startSpeaking(errorMessage)
        voiceState = .responding
    }

    // MARK: - Point Tag Parsing

    /// Result of parsing a [POINT:...] tag from Claude's response.
    struct PointingParseResult {
        /// The response text with the [POINT:...] tag removed — this is what gets spoken.
        let spokenText: String
        /// The parsed pixel coordinate, or nil if Claude said "none" or no tag was found.
        let coordinate: CGPoint?
        /// Short label describing the element (e.g. "run button"), or "none".
        let elementLabel: String?
        /// Which screen the coordinate refers to (1-based), or nil to default to cursor screen.
        let screenNumber: Int?
    }

    /// Parses a [POINT:x,y:label:screenN] or [POINT:none] tag from the end of Claude's response.
    /// Returns the spoken text (tag removed) and the optional coordinate + label + screen number.
    static func parsePointingCoordinates(from responseText: String) -> PointingParseResult {
        // Match [POINT:none] or [POINT:123,456:label] or [POINT:123,456:label:screen2]
        let pattern = #"\[POINT:(?:none|(\d+)\s*,\s*(\d+)(?::([^\]:\s][^\]:]*?))?(?::screen(\d+))?)\]\s*$"#

        guard let regex = try? NSRegularExpression(pattern: pattern, options: []),
              let match = regex.firstMatch(in: responseText, range: NSRange(responseText.startIndex..., in: responseText)) else {
            // No tag found at all
            return PointingParseResult(spokenText: responseText, coordinate: nil, elementLabel: nil, screenNumber: nil)
        }

        // Remove the tag from the spoken text
        let tagRange = Range(match.range, in: responseText)!
        let spokenText = String(responseText[..<tagRange.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)

        // Check if it's [POINT:none]
        guard match.numberOfRanges >= 3,
              let xRange = Range(match.range(at: 1), in: responseText),
              let yRange = Range(match.range(at: 2), in: responseText),
              let x = Double(responseText[xRange]),
              let y = Double(responseText[yRange]) else {
            return PointingParseResult(spokenText: spokenText, coordinate: nil, elementLabel: "none", screenNumber: nil)
        }

        var elementLabel: String? = nil
        if match.numberOfRanges >= 4, let labelRange = Range(match.range(at: 3), in: responseText) {
            elementLabel = String(responseText[labelRange]).trimmingCharacters(in: .whitespaces)
        }

        var screenNumber: Int? = nil
        if match.numberOfRanges >= 5, let screenRange = Range(match.range(at: 4), in: responseText) {
            screenNumber = Int(responseText[screenRange])
        }

        return PointingParseResult(
            spokenText: spokenText,
            coordinate: CGPoint(x: x, y: y),
            elementLabel: elementLabel,
            screenNumber: screenNumber
        )
    }

    // MARK: - Onboarding Prompt

    /// Types "press control + option and introduce yourself" next to the
    /// companion. Called by CompanionOverlayView when the first-run welcome ends.
    func startOnboardingPromptStream() {
        let message = "press control + option and introduce yourself"
        onboardingPromptText = ""
        showOnboardingPrompt = true
        onboardingPromptOpacity = 0.0

        withAnimation(.easeIn(duration: 0.4)) {
            onboardingPromptOpacity = 1.0
        }

        var currentIndex = 0
        Timer.scheduledTimer(withTimeInterval: 0.03, repeats: true) { timer in
            guard currentIndex < message.count else {
                timer.invalidate()
                // Auto-dismiss after 10 seconds
                DispatchQueue.main.asyncAfter(deadline: .now() + 10.0) {
                    guard self.showOnboardingPrompt else { return }
                    withAnimation(.easeOut(duration: 0.3)) {
                        self.onboardingPromptOpacity = 0.0
                    }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                        self.showOnboardingPrompt = false
                        self.onboardingPromptText = ""
                    }
                }
                return
            }
            let index = message.index(message.startIndex, offsetBy: currentIndex)
            self.onboardingPromptText.append(message[index])
            currentIndex += 1
        }
    }
}
