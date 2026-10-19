//
//  CompanionPanelView.swift
//  leanring-buddy
//
//  The SwiftUI content hosted inside the menu bar panel. Shows the companion
//  voice status, push-to-talk shortcut, and AI settings. Designed to feel
//  like Loom's recording panel — dark, rounded, minimal, and special.
//

import AVFoundation
import SwiftUI

struct CompanionPanelView: View {
    @ObservedObject var companionManager: CompanionManager
    @ObservedObject private var appSettings = AppSettings.shared
    @ObservedObject private var kokoroVoiceEngine = KokoroVoiceEngine.shared
    @ObservedObject private var memoryManager = MemoryManager.shared
    @State private var isAISettingsExpanded: Bool = false
    /// Draft text for each API key field. Keys are written to the Keychain
    /// only when the user clicks Save, never on every keystroke.
    @State private var apiKeyDrafts: [SecretsStore.Key: String] = [:]
    /// Which keys currently have a value in the Keychain (for the ✓ badge).
    @State private var savedAPIKeys: Set<SecretsStore.Key> = []

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            panelHeader
            Divider()
                .background(panelBorderColor)
                .padding(.horizontal, 16)

            permissionsCopySection
                .padding(.top, 16)
                .padding(.horizontal, 16)

            if companionManager.allPermissionsGranted {
                Spacer()
                    .frame(height: 12)

                aiSettingsSection
                    .padding(.horizontal, 16)
            }

            if !companionManager.allPermissionsGranted {
                Spacer()
                    .frame(height: 16)

                settingsSection
                    .padding(.horizontal, 16)
            }

            if !companionManager.hasCompletedOnboarding && companionManager.allPermissionsGranted {
                Spacer()
                    .frame(height: 16)

                startButton
                    .padding(.horizontal, 16)
            }

            Spacer()
                .frame(height: 12)

            Divider()
                .background(panelBorderColor)
                .padding(.horizontal, 16)

            footerSection
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
        }
        .frame(width: 320)
        .background(panelBackground)
        .onAppear(perform: refreshSavedAPIKeyBadges)
    }

    // MARK: - Header

    private var panelHeader: some View {
        HStack {
            HStack(spacing: 8) {
                // Animated status dot
                Circle()
                    .fill(statusDotColor)
                    .frame(width: 8, height: 8)
                    .shadow(color: statusDotColor.opacity(0.6), radius: 4)

                Text("Lumen")
                    .font(.skinFont(size: 14, weight: .semibold, design: skinTheme.fontDesign))
                    .foregroundColor(panelTextPrimaryColor)
            }

            Spacer()

            Text(statusText)
                .font(.skinFont(size: 12, weight: .medium, design: skinTheme.fontDesign))
                .foregroundColor(panelTextTertiaryColor)

            Button(action: {
                NotificationCenter.default.post(name: .lumenDismissPanel, object: nil)
            }) {
                Image(systemName: "xmark")
                    .font(.skinFont(size: 10, weight: .semibold, design: skinTheme.fontDesign))
                    .foregroundColor(panelTextTertiaryColor)
                    .frame(width: 20, height: 20)
                    .background(
                        Circle()
                            .fill(panelControlFillColor)
                    )
            }
            .buttonStyle(.plain)
            .pointerCursor()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
    }

    // MARK: - Permissions Copy

    @ViewBuilder
    private var permissionsCopySection: some View {
        if companionManager.hasCompletedOnboarding && companionManager.allPermissionsGranted {
            Text("Hold Control+Option to talk.")
                .font(.skinFont(size: 12, weight: .medium, design: skinTheme.fontDesign))
                .foregroundColor(panelTextSecondaryColor)
                .frame(maxWidth: .infinity, alignment: .leading)
        } else if companionManager.allPermissionsGranted {
            Text("You're all set. Hit Start to meet Lumen.")
                .font(.skinFont(size: 12, weight: .medium, design: skinTheme.fontDesign))
                .foregroundColor(panelTextSecondaryColor)
                .frame(maxWidth: .infinity, alignment: .leading)
        } else if companionManager.hasCompletedOnboarding {
            // Permissions were revoked after onboarding — tell user to re-grant
            VStack(alignment: .leading, spacing: 6) {
                Text("Permissions needed")
                    .font(.skinFont(size: 12, weight: .bold, design: skinTheme.fontDesign))
                    .foregroundColor(panelTextSecondaryColor)

                Text("Some permissions were revoked. Grant all four below to keep using Lumen.")
                    .font(.skinFont(size: 11, design: skinTheme.fontDesign))
                    .foregroundColor(panelTextTertiaryColor)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        } else {
            VStack(alignment: .leading, spacing: 6) {
                Text("Hi, I'm Lumen.")
                    .font(.skinFont(size: 12, weight: .bold, design: skinTheme.fontDesign))
                    .foregroundColor(panelTextSecondaryColor)

                Text("A voice assistant that lives in your menu bar, runs on your Mac, and can see your screen when you ask.")
                    .font(.skinFont(size: 11, design: skinTheme.fontDesign))
                    .foregroundColor(panelTextTertiaryColor)
                    .fixedSize(horizontal: false, vertical: true)

                Text("Lumen only takes a screenshot while you hold the hot key. Nothing is captured in the background.")
                    .font(.skinFont(size: 11, design: skinTheme.fontDesign))
                    .foregroundColor(panelAccentColor)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    // MARK: - Start Button

    @ViewBuilder
    private var startButton: some View {
        if !companionManager.hasCompletedOnboarding && companionManager.allPermissionsGranted {
            Button(action: {
                companionManager.triggerOnboarding()
            }) {
                Text("Start")
                    .font(.skinFont(size: 14, weight: .semibold, design: skinTheme.fontDesign))
                    .foregroundColor(panelOnAccentColor)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .background(
                        RoundedRectangle(cornerRadius: DS.CornerRadius.large, style: .continuous)
                            .fill(panelAccentColor)
                    )
            }
            .buttonStyle(.plain)
            .pointerCursor()
        }
    }

    // MARK: - Permissions

    private var settingsSection: some View {
        VStack(spacing: 2) {
            Text("PERMISSIONS")
                .font(.skinFont(size: 10, weight: .semibold, design: skinTheme.fontDesign))
                .foregroundColor(panelTextTertiaryColor)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.bottom, 6)

            microphonePermissionRow

            accessibilityPermissionRow

            screenRecordingPermissionRow

            if companionManager.hasScreenRecordingPermission {
                screenContentPermissionRow
            }

        }
    }

    private var accessibilityPermissionRow: some View {
        let isGranted = companionManager.hasAccessibilityPermission
        return HStack {
            HStack(spacing: 8) {
                Image(systemName: "hand.raised")
                    .font(.skinFont(size: 12, weight: .medium, design: skinTheme.fontDesign))
                    .foregroundColor(isGranted ? panelTextTertiaryColor : DS.Colors.warning)
                    .frame(width: 16)

                Text("Accessibility")
                    .font(.skinFont(size: 13, weight: .medium, design: skinTheme.fontDesign))
                    .foregroundColor(panelTextSecondaryColor)
            }

            Spacer()

            if isGranted {
                HStack(spacing: 4) {
                    Circle()
                        .fill(DS.Colors.success)
                        .frame(width: 6, height: 6)
                    Text("Granted")
                        .font(.skinFont(size: 11, weight: .medium, design: skinTheme.fontDesign))
                        .foregroundColor(DS.Colors.success)
                }
            } else {
                HStack(spacing: 6) {
                    Button(action: {
                        // Triggers the system accessibility prompt (AXIsProcessTrustedWithOptions)
                        // on first attempt, then opens System Settings on subsequent attempts.
                        WindowPositionManager.requestAccessibilityPermission()
                    }) {
                        Text("Grant")
                            .font(.skinFont(size: 11, weight: .semibold, design: skinTheme.fontDesign))
                            .foregroundColor(panelOnAccentColor)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 4)
                            .background(
                                Capsule()
                                    .fill(panelAccentColor)
                            )
                    }
                    .buttonStyle(.plain)
                    .pointerCursor()

                    Button(action: {
                        // Reveals the app in Finder so the user can drag it into
                        // the Accessibility list if it doesn't appear automatically
                        // (common with unsigned dev builds).
                        WindowPositionManager.revealAppInFinder()
                        WindowPositionManager.openAccessibilitySettings()
                    }) {
                        Text("Find App")
                            .font(.skinFont(size: 11, weight: .semibold, design: skinTheme.fontDesign))
                            .foregroundColor(panelTextSecondaryColor)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 4)
                            .background(
                                Capsule()
                                    .stroke(panelBorderColor, lineWidth: 0.8)
                            )
                    }
                    .buttonStyle(.plain)
                    .pointerCursor()
                }
            }
        }
        .padding(.vertical, 6)
    }

    private var screenRecordingPermissionRow: some View {
        let isGranted = companionManager.hasScreenRecordingPermission
        return HStack {
            HStack(spacing: 8) {
                Image(systemName: "rectangle.dashed.badge.record")
                    .font(.skinFont(size: 12, weight: .medium, design: skinTheme.fontDesign))
                    .foregroundColor(isGranted ? panelTextTertiaryColor : DS.Colors.warning)
                    .frame(width: 16)

                VStack(alignment: .leading, spacing: 1) {
                    Text("Screen Recording")
                        .font(.skinFont(size: 13, weight: .medium, design: skinTheme.fontDesign))
                        .foregroundColor(panelTextSecondaryColor)

                    Text(isGranted
                         ? "Only takes a screenshot when you use the hotkey"
                         : "Quit and reopen after granting")
                        .font(.skinFont(size: 10, design: skinTheme.fontDesign))
                        .foregroundColor(panelTextTertiaryColor)
                }
            }

            Spacer()

            if isGranted {
                HStack(spacing: 4) {
                    Circle()
                        .fill(DS.Colors.success)
                        .frame(width: 6, height: 6)
                    Text("Granted")
                        .font(.skinFont(size: 11, weight: .medium, design: skinTheme.fontDesign))
                        .foregroundColor(DS.Colors.success)
                }
            } else {
                Button(action: {
                    // Triggers the native macOS screen recording prompt on first
                    // attempt (auto-adds app to the list), then opens System Settings
                    // on subsequent attempts.
                    WindowPositionManager.requestScreenRecordingPermission()
                }) {
                    Text("Grant")
                        .font(.skinFont(size: 11, weight: .semibold, design: skinTheme.fontDesign))
                        .foregroundColor(panelOnAccentColor)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(
                            Capsule()
                                .fill(panelAccentColor)
                        )
                }
                .buttonStyle(.plain)
                .pointerCursor()
            }
        }
        .padding(.vertical, 6)
    }

    private var screenContentPermissionRow: some View {
        let isGranted = companionManager.hasScreenContentPermission
        return HStack {
            HStack(spacing: 8) {
                Image(systemName: "eye")
                    .font(.skinFont(size: 12, weight: .medium, design: skinTheme.fontDesign))
                    .foregroundColor(isGranted ? panelTextTertiaryColor : DS.Colors.warning)
                    .frame(width: 16)

                Text("Screen Content")
                    .font(.skinFont(size: 13, weight: .medium, design: skinTheme.fontDesign))
                    .foregroundColor(panelTextSecondaryColor)
            }

            Spacer()

            if isGranted {
                HStack(spacing: 4) {
                    Circle()
                        .fill(DS.Colors.success)
                        .frame(width: 6, height: 6)
                    Text("Granted")
                        .font(.skinFont(size: 11, weight: .medium, design: skinTheme.fontDesign))
                        .foregroundColor(DS.Colors.success)
                }
            } else {
                Button(action: {
                    companionManager.requestScreenContentPermission()
                }) {
                    Text("Grant")
                        .font(.skinFont(size: 11, weight: .semibold, design: skinTheme.fontDesign))
                        .foregroundColor(panelOnAccentColor)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(
                            Capsule()
                                .fill(panelAccentColor)
                        )
                }
                .buttonStyle(.plain)
                .pointerCursor()
            }
        }
        .padding(.vertical, 6)
    }

    private var microphonePermissionRow: some View {
        let isGranted = companionManager.hasMicrophonePermission
        return HStack {
            HStack(spacing: 8) {
                Image(systemName: "mic")
                    .font(.skinFont(size: 12, weight: .medium, design: skinTheme.fontDesign))
                    .foregroundColor(isGranted ? panelTextTertiaryColor : DS.Colors.warning)
                    .frame(width: 16)

                Text("Microphone")
                    .font(.skinFont(size: 13, weight: .medium, design: skinTheme.fontDesign))
                    .foregroundColor(panelTextSecondaryColor)
            }

            Spacer()

            if isGranted {
                HStack(spacing: 4) {
                    Circle()
                        .fill(DS.Colors.success)
                        .frame(width: 6, height: 6)
                    Text("Granted")
                        .font(.skinFont(size: 11, weight: .medium, design: skinTheme.fontDesign))
                        .foregroundColor(DS.Colors.success)
                }
            } else {
                Button(action: {
                    // Triggers the native macOS microphone permission dialog on
                    // first attempt. If already denied, opens System Settings.
                    let status = AVCaptureDevice.authorizationStatus(for: .audio)
                    if status == .notDetermined {
                        AVCaptureDevice.requestAccess(for: .audio) { _ in }
                    } else {
                        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone") {
                            NSWorkspace.shared.open(url)
                        }
                    }
                }) {
                    Text("Grant")
                        .font(.skinFont(size: 11, weight: .semibold, design: skinTheme.fontDesign))
                        .foregroundColor(panelOnAccentColor)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(
                            Capsule()
                                .fill(panelAccentColor)
                        )
                }
                .buttonStyle(.plain)
                .pointerCursor()
            }
        }
        .padding(.vertical, 6)
    }

    private func permissionRow(
        label: String,
        iconName: String,
        isGranted: Bool,
        settingsURL: String
    ) -> some View {
        HStack {
            HStack(spacing: 8) {
                Image(systemName: iconName)
                    .font(.skinFont(size: 12, weight: .medium, design: skinTheme.fontDesign))
                    .foregroundColor(isGranted ? panelTextTertiaryColor : DS.Colors.warning)
                    .frame(width: 16)

                Text(label)
                    .font(.skinFont(size: 13, weight: .medium, design: skinTheme.fontDesign))
                    .foregroundColor(panelTextSecondaryColor)
            }

            Spacer()

            if isGranted {
                HStack(spacing: 4) {
                    Circle()
                        .fill(DS.Colors.success)
                        .frame(width: 6, height: 6)
                    Text("Granted")
                        .font(.skinFont(size: 11, weight: .medium, design: skinTheme.fontDesign))
                        .foregroundColor(DS.Colors.success)
                }
            } else {
                Button(action: {
                    if let url = URL(string: settingsURL) {
                        NSWorkspace.shared.open(url)
                    }
                }) {
                    Text("Grant")
                        .font(.skinFont(size: 11, weight: .semibold, design: skinTheme.fontDesign))
                        .foregroundColor(panelOnAccentColor)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(
                            Capsule()
                                .fill(panelAccentColor)
                        )
                }
                .buttonStyle(.plain)
                .pointerCursor()
            }
        }
        .padding(.vertical, 6)
    }



    private var speechToTextProviderRow: some View {
        HStack {
            HStack(spacing: 8) {
                Image(systemName: "mic.badge.waveform")
                    .font(.skinFont(size: 12, weight: .medium, design: skinTheme.fontDesign))
                    .foregroundColor(panelTextTertiaryColor)
                    .frame(width: 16)

                Text("Speech to Text")
                    .font(.skinFont(size: 13, weight: .medium, design: skinTheme.fontDesign))
                    .foregroundColor(panelTextSecondaryColor)
            }

            Spacer()

            Text(companionManager.buddyDictationManager.transcriptionProviderDisplayName)
                .font(.skinFont(size: 11, weight: .medium, design: skinTheme.fontDesign))
                .foregroundColor(panelTextTertiaryColor)
        }
        .padding(.vertical, 4)
    }

    // MARK: - AI Settings (provider, model, voice, API keys)

    private var aiSettingsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            aiSettingsHeaderRow

            if isAISettingsExpanded {
                settingsSubsectionLabel("APPEARANCE")
                settingsPickerRow(title: "Skin", selection: $appSettings.selectedSkin)

                settingsSubsectionLabel("MODEL")
                    .padding(.top, 4)
                settingsPickerRow(title: "Provider", selection: $appSettings.chatProviderKind)

                if appSettings.chatProviderKind.usesOpenAICompatibleAPI {
                    settingsTextFieldRow(title: "Base URL", text: $appSettings.chatBaseURL, placeholder: "https://…/v1")
                }
                settingsTextFieldRow(title: "Model", text: $appSettings.chatModel, placeholder: "model id")

                if let chatSecretKey = appSettings.chatProviderKind.secretKey {
                    apiKeyRow(for: chatSecretKey)
                }

                settingsSubsectionLabel("VOICE")
                    .padding(.top, 4)
                settingsPickerRow(title: "Speech to text", selection: $appSettings.speechToTextProviderKind)
                if let speechToTextSecretKey = appSettings.speechToTextProviderKind.secretKey {
                    apiKeyRow(for: speechToTextSecretKey)
                }

                settingsPickerRow(title: "Replies", selection: $appSettings.replyDisplayMode)
                settingsPickerRow(title: "Text to speech", selection: $appSettings.textToSpeechProviderKind)
                switch appSettings.textToSpeechProviderKind {
                case .kokoro:
                    kokoroVoicePickerRow
                    kokoroModelStatusRow
                case .apple:
                    appleVoicePickerRow
                case .elevenLabs:
                    apiKeyRow(for: .elevenLabs)
                    settingsTextFieldRow(title: "Voice ID", text: $appSettings.elevenLabsVoiceID, placeholder: AppSettings.defaultElevenLabsVoiceID)
                }

                settingsSubsectionLabel("MEMORY")
                    .padding(.top, 4)
                settingsToggleRow(title: "Remember things", isOn: $appSettings.isMemoryEnabled)
                if appSettings.isMemoryEnabled {
                    memoryStatusRow
                    memoryActionsRow
                }

                Text("Keys are stored in your macOS Keychain. Leave everything on Ollama + Kokoro to run fully offline.")
                    .font(.skinFont(size: 10, design: skinTheme.fontDesign))
                    .foregroundColor(panelTextTertiaryColor)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 2)
            }
        }
    }

    /// Collapsed by default so the panel stays short; the summary line shows
    /// the active stack at a glance.
    private var aiSettingsHeaderRow: some View {
        Button(action: {
            withAnimation(.easeInOut(duration: 0.15)) {
                isAISettingsExpanded.toggle()
            }
        }) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("AI Settings")
                        .font(.skinFont(size: 13, weight: .medium, design: skinTheme.fontDesign))
                        .foregroundColor(panelTextSecondaryColor)
                    Text(activeStackSummary)
                        .font(.skinFont(size: 10, design: skinTheme.fontDesign))
                        .foregroundColor(panelTextTertiaryColor)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }

                Spacer()

                Image(systemName: isAISettingsExpanded ? "chevron.up" : "chevron.down")
                    .font(.skinFont(size: 10, weight: .semibold, design: skinTheme.fontDesign))
                    .foregroundColor(panelTextTertiaryColor)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .pointerCursor()
        .padding(.vertical, 4)
    }

    private var activeStackSummary: String {
        let speechToTextName = appSettings.speechToTextProviderKind.displayName
        let chatName = "\(appSettings.chatProviderKind.displayName) · \(appSettings.chatModel)"
        let textToSpeechName = appSettings.textToSpeechProviderKind.displayName
        return "\(speechToTextName) → \(chatName) → \(textToSpeechName)"
    }

    private func settingsSubsectionLabel(_ title: String) -> some View {
        Text(title)
            .font(.skinFont(size: 10, weight: .semibold, design: skinTheme.fontDesign))
            .foregroundColor(panelTextTertiaryColor)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func settingsPickerRow<Kind: CaseIterable & Identifiable & RawRepresentable & Hashable>(
        title: String,
        selection: Binding<Kind>
    ) -> some View where Kind.AllCases: RandomAccessCollection {
        HStack {
            Text(title)
                .font(.skinFont(size: 12, weight: .medium, design: skinTheme.fontDesign))
                .foregroundColor(panelTextSecondaryColor)
            Spacer()
            Picker("", selection: selection) {
                ForEach(Array(Kind.allCases)) { kind in
                    Text(displayName(for: kind)).tag(kind)
                }
            }
            .pickerStyle(.menu)
            .labelsHidden()
            .frame(maxWidth: 160)
        }
    }

    /// The provider enums and LumenSkin each expose `displayName`; this keeps the
    /// generic picker row from needing a shared protocol.
    private func displayName<Kind>(for kind: Kind) -> String {
        if let chatProviderKind = kind as? ChatProviderKind { return chatProviderKind.displayName }
        if let speechToTextProviderKind = kind as? SpeechToTextProviderKind { return speechToTextProviderKind.displayName }
        if let textToSpeechProviderKind = kind as? TextToSpeechProviderKind { return textToSpeechProviderKind.displayName }
        if let lumenSkin = kind as? LumenSkin { return lumenSkin.displayName }
        if let replyDisplayMode = kind as? ReplyDisplayMode { return replyDisplayMode.displayName }
        return "\(kind)"
    }

    private func settingsTextFieldRow(title: String, text: Binding<String>, placeholder: String) -> some View {
        HStack {
            Text(title)
                .font(.skinFont(size: 12, weight: .medium, design: skinTheme.fontDesign))
                .foregroundColor(panelTextSecondaryColor)
            Spacer()
            TextField(placeholder, text: text)
                .textFieldStyle(.roundedBorder)
                .font(.skinFont(size: 11, design: skinTheme.fontDesign))
                .frame(maxWidth: 190)
        }
    }

    private var appleVoicePickerRow: some View {
        let availableVoices = AppSettings.availableAppleVoices()
        return HStack {
            Text("Voice")
                .font(.skinFont(size: 12, weight: .medium, design: skinTheme.fontDesign))
                .foregroundColor(panelTextSecondaryColor)
            Spacer()
            Picker("", selection: $appSettings.appleVoiceIdentifier) {
                Text("System default").tag("")
                ForEach(availableVoices, id: \.identifier) { voice in
                    Text(appleVoiceLabel(for: voice)).tag(voice.identifier)
                }
            }
            .pickerStyle(.menu)
            .labelsHidden()
            .frame(maxWidth: 190)
        }
    }

    private var kokoroVoicePickerRow: some View {
        HStack {
            Text("Voice")
                .font(.skinFont(size: 12, weight: .medium, design: skinTheme.fontDesign))
                .foregroundColor(panelTextSecondaryColor)
            Spacer()
            Picker("", selection: $appSettings.kokoroVoice) {
                ForEach(KokoroVoiceCatalog.availableVoices()) { voiceOption in
                    Text(voiceOption.label).tag(voiceOption.id)
                }
            }
            .pickerStyle(.menu)
            .labelsHidden()
            .frame(maxWidth: 190)
        }
    }

    /// One line under the voice picker so the first-run download isn't a
    /// mystery: downloading → ready, or the error with a Retry button.
    private var kokoroModelStatusRow: some View {
        HStack(spacing: 6) {
            switch kokoroVoiceEngine.loadState {
            case .notLoaded:
                kokoroStatusText("voice model loads on first use")
            case .loading:
                ProgressView()
                    .controlSize(.mini)
                kokoroStatusText("downloading voice model… (one time, ~300 MB)")
            case .ready:
                kokoroStatusText("voice model ready")
            case .failed(let message):
                kokoroStatusText(message)
                Button("Retry") {
                    Task {
                        await kokoroVoiceEngine.retryLoad(preloadingVoice: appSettings.kokoroVoice)
                    }
                }
                .buttonStyle(.plain)
                .font(.skinFont(size: 10, weight: .semibold, design: skinTheme.fontDesign))
                .foregroundColor(panelTextSecondaryColor)
                .pointerCursor()
            case .unavailable(let reason):
                kokoroStatusText(reason)
            }
            Spacer()
        }
    }

    private func kokoroStatusText(_ text: String) -> some View {
        Text(text)
            .font(.skinFont(size: 10, design: skinTheme.fontDesign))
            .foregroundColor(panelTextTertiaryColor)
            .fixedSize(horizontal: false, vertical: true)
    }

    // MARK: - Memory rows

    private func settingsToggleRow(title: String, isOn: Binding<Bool>) -> some View {
        HStack {
            Text(title)
                .font(.skinFont(size: 12, weight: .medium, design: skinTheme.fontDesign))
                .foregroundColor(panelTextSecondaryColor)
            Spacer()
            Toggle("", isOn: isOn)
                .toggleStyle(.switch)
                .controlSize(.mini)
                .labelsHidden()
                .pointerCursor()
        }
    }

    /// Mirrors the Kokoro row: what the two memory models (embeddings +
    /// summariser, both from Ollama) are doing, with Retry on failure.
    private var memoryStatusRow: some View {
        HStack(spacing: 6) {
            switch memoryManager.provisioningState {
            case .notChecked:
                kokoroStatusText("memory models are checked at launch")
            case .checking:
                ProgressView()
                    .controlSize(.mini)
                kokoroStatusText("checking memory models…")
            case .pulling(let modelName, let fractionCompleted):
                ProgressView()
                    .controlSize(.mini)
                if let fractionCompleted {
                    kokoroStatusText("downloading \(modelName)… \(Int(fractionCompleted * 100))% (one time)")
                } else {
                    kokoroStatusText("downloading \(modelName)… (one time)")
                }
            case .ready:
                kokoroStatusText("memory ready · \(memoryManager.profileFactLineCount) facts in profile")
            case .ollamaUnreachable(let message), .failed(let message):
                kokoroStatusText(message + " — using the last two days of notes meanwhile")
                Button("Retry") {
                    memoryManager.retryProvisioning()
                }
                .buttonStyle(.plain)
                .font(.skinFont(size: 10, weight: .semibold, design: skinTheme.fontDesign))
                .foregroundColor(panelTextSecondaryColor)
                .pointerCursor()
            }
            Spacer()
        }
    }

    private var memoryActionsRow: some View {
        HStack(spacing: 12) {
            Button("Open memory folder") {
                NSWorkspace.shared.open(memoryManager.memoryRootDirectoryURL)
            }
            .buttonStyle(.plain)
            .font(.skinFont(size: 10, weight: .semibold, design: skinTheme.fontDesign))
            .foregroundColor(panelTextSecondaryColor)
            .pointerCursor()

            Button("Forget today") {
                Task {
                    await memoryManager.forgetToday()
                }
            }
            .buttonStyle(.plain)
            .font(.skinFont(size: 10, weight: .semibold, design: skinTheme.fontDesign))
            .foregroundColor(panelTextSecondaryColor)
            .pointerCursor()

            Spacer()
        }
    }

    private func appleVoiceLabel(for voice: AVSpeechSynthesisVoice) -> String {
        switch voice.quality {
        case .premium: return "\(voice.name) (Premium)"
        case .enhanced: return "\(voice.name) (Enhanced)"
        default: return voice.name
        }
    }

    /// SecureField + Save button for one Keychain-backed API key. The ✓ badge
    /// means a value is saved; the field itself never displays the stored key.
    private func apiKeyRow(for secretKey: SecretsStore.Key) -> some View {
        let isSaved = savedAPIKeys.contains(secretKey)
        let draftBinding = Binding<String>(
            get: { apiKeyDrafts[secretKey] ?? "" },
            set: { apiKeyDrafts[secretKey] = $0 }
        )
        return HStack(spacing: 6) {
            Text("\(secretKey.displayName) key")
                .font(.skinFont(size: 12, weight: .medium, design: skinTheme.fontDesign))
                .foregroundColor(panelTextSecondaryColor)

            if isSaved {
                Image(systemName: "checkmark.circle.fill")
                    .font(.skinFont(size: 10, design: skinTheme.fontDesign))
                    .foregroundColor(DS.Colors.success)
            }

            Spacer()

            SecureField(isSaved ? "saved — paste to replace" : "paste key", text: draftBinding)
                .textFieldStyle(.roundedBorder)
                .font(.skinFont(size: 11, design: skinTheme.fontDesign))
                .frame(maxWidth: 140)

            Button(action: {
                saveAPIKey(secretKey)
            }) {
                Text("Save")
                    .font(.skinFont(size: 11, weight: .semibold, design: skinTheme.fontDesign))
                    .foregroundColor(panelTextPrimaryColor)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(
                        RoundedRectangle(cornerRadius: 5, style: .continuous)
                            .fill(panelControlFillColor)
                    )
            }
            .buttonStyle(.plain)
            .pointerCursor()
            .disabled((apiKeyDrafts[secretKey] ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
    }

    private func saveAPIKey(_ secretKey: SecretsStore.Key) {
        let draftValue = apiKeyDrafts[secretKey] ?? ""
        SecretsStore.write(secretKey, value: draftValue)
        apiKeyDrafts[secretKey] = ""
        refreshSavedAPIKeyBadges()
        // Keys live outside AppSettings, so the settings publishers won't
        // notice — rebuild the clients explicitly.
        companionManager.rebuildClientsFromSettings()
        companionManager.buddyDictationManager.reloadTranscriptionProviderFromSettings()
    }

    private func refreshSavedAPIKeyBadges() {
        // Explicit closure rather than passing `SecretsStore.hasValue` directly:
        // a bare function reference loses main-actor isolation under the
        // project's default-MainActor setting and the compiler warns.
        savedAPIKeys = Set(SecretsStore.Key.allCases.filter { secretKey in
            SecretsStore.hasValue(secretKey)
        })
    }

    // MARK: - Footer

    private var footerSection: some View {
        HStack {
            Button(action: {
                NSApp.terminate(nil)
            }) {
                HStack(spacing: 6) {
                    Image(systemName: "power")
                        .font(.skinFont(size: 11, weight: .medium, design: skinTheme.fontDesign))
                    Text("Quit Lumen")
                        .font(.skinFont(size: 12, weight: .medium, design: skinTheme.fontDesign))
                }
                .foregroundColor(panelTextTertiaryColor)
            }
            .buttonStyle(.plain)
            .pointerCursor()

        }
    }

    // MARK: - Visual Helpers

    private var panelBackground: some View {
        SkinPanelBackground(theme: skinTheme)
    }

    // MARK: - Skin Colours

    /// The selected skin's tokens. Read from AppSettings, so switching skins
    /// restyles the panel immediately.
    private var skinTheme: SkinTheme { SkinTheme.theme(for: appSettings.selectedSkin) }
    private var panelTextPrimaryColor: Color { Color(hex: skinTheme.panelTextPrimaryHex) }
    private var panelTextSecondaryColor: Color { Color(hex: skinTheme.panelTextSecondaryHex) }
    private var panelTextTertiaryColor: Color { Color(hex: skinTheme.panelTextTertiaryHex) }
    private var panelBorderColor: Color { Color(hex: skinTheme.panelBorderHex) }
    private var panelAccentColor: Color { Color(hex: skinTheme.panelAccentHex) }
    private var panelOnAccentColor: Color { Color(hex: skinTheme.panelOnAccentHex) }
    private var panelControlFillColor: Color { Color(hex: skinTheme.panelControlFillHex) }

    private var statusDotColor: Color {
        if !companionManager.isOverlayVisible {
            return panelTextTertiaryColor
        }
        switch companionManager.voiceState {
        case .idle:
            return DS.Colors.success
        case .listening:
            return panelAccentColor
        case .processing, .responding:
            return panelAccentColor
        }
    }

    private var statusText: String {
        if !companionManager.hasCompletedOnboarding || !companionManager.allPermissionsGranted {
            return "Setup"
        }
        if !companionManager.isOverlayVisible {
            return "Ready"
        }
        switch companionManager.voiceState {
        case .idle:
            return "Active"
        case .listening:
            return "Listening"
        case .processing:
            return "Processing"
        case .responding:
            return "Responding"
        }
    }

}
