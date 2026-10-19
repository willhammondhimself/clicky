# Lumen - Agent Instructions

<!-- This is the single source of truth for all AI coding agents. CLAUDE.md is a symlink to this file. -->
<!-- AGENTS.md spec: https://github.com/agentsmd/agents.md — supported by Claude Code, Cursor, Copilot, Gemini CLI, and others. -->

## Overview

macOS menu bar companion app. Lives entirely in the macOS status bar (no dock icon, no main window). Clicking the menu bar icon opens a custom floating panel with companion voice controls and AI settings. Uses push-to-talk (ctrl+option) to capture voice input, transcribes it via the configured STT provider (Apple Speech by default), and sends the transcript + a screenshot of the user's screen to the configured vision chat model (Ollama on localhost by default; OpenRouter/Anthropic/custom opt-in). The model responds with text (streamed via SSE) which is spoken via the configured TTS provider (Kokoro on-device by default; Apple voices and ElevenLabs selectable). An on-screen companion, drawn by the selected skin (Ember, Instrument or Marginalia; default Marginalia), can fly to and mark UI elements the model references on any connected monitor.

This fork calls provider APIs directly. API keys are stored in the macOS Keychain (`SecretsStore`) and entered through the in-app settings panel; nothing sensitive ships in the app. There is no proxy server and no telemetry.

## Architecture

- **App Type**: Menu bar-only (`LSUIElement=true`), no dock icon or main window
- **Framework**: SwiftUI (macOS native) with AppKit bridging for menu bar panel and cursor overlay
- **Pattern**: MVVM with `@StateObject` / `@Published` state management
- **AI Chat**: pluggable `ChatClient` — `OpenAICompatibleChatClient` (OpenRouter, Ollama, any `/chat/completions` server; default Ollama `gemma4:26b`) or `ClaudeAPI` (Anthropic Messages API direct). SSE streaming. Chosen in `AppSettings.chatProviderKind`.
- **Speech-to-Text**: pluggable `BuddyTranscriptionProvider` — Apple Speech on-device (default), AssemblyAI real-time streaming (`u3-rt-pro`), or OpenAI upload. Chosen in `AppSettings.speechToTextProviderKind`.
- **Text-to-Speech**: pluggable `TTSClient` — `KokoroTTSClient` (on-device Kokoro-82M via the FluidAudio Swift package, default), `AppleSpeechTTSClient` (AVSpeechSynthesizer) or `ElevenLabsTTSClient` (`eleven_flash_v2_5`, direct). Chosen in `AppSettings.textToSpeechProviderKind`. Kokoro models (~380 MB) download once from Hugging Face into `~/Library/Application Support/Lumen/Models` (plus ~40 MB of pronunciation assets in FluidAudio's own `~/.cache/fluidaudio`); `KokoroVoiceEngine` is a singleton so they load once per app run.
- **Settings & Secrets**: `AppSettings` (UserDefaults-backed `ObservableObject`) for provider/model/voice choices; `SecretsStore` (Keychain, service `com.willhammond.lumen`) for API keys. `CompanionManager` observes `AppSettings` and rebuilds clients on change.
- **Memory**: `MemoryManager` keeps `~/Library/Application Support/Lumen/Memory/PROFILE.md` (facts about the user, one `- ` bullet per line under `## ` headings) and `notes/YYYY-MM-DD.md` (one summarised line per exchange). The profile, today's note and the top-8 past note lines by embedding similarity (`embeddinggemma` via Ollama `/api/embed`, index in `notes/index.json`) are appended to the system prompt. The model writes facts with `[REMEMBER:Section:fact]` and removes them with `[FORGET:text]` tags (stripped before TTS by `MemoryTagParser`, which must run before the `[POINT]` parser); "remember that …" spoken at the start of a question is a fallback. Daily-note lines are summarised by `gemma4:e2b` (`/api/generate`, background) or written raw when it is unavailable. Both models are pulled from Ollama at launch when missing (`MemoryModelProvisioner`); until then the last two days are injected whole. On by default (`AppSettings.isMemoryEnabled`).
- **Screen Capture**: ScreenCaptureKit (macOS 14.2+), multi-monitor support
- **Voice Input**: Push-to-talk via `AVAudioEngine` + pluggable transcription-provider layer. Records from the MacBook's built-in mic by default (`MicrophoneSelection`, panel Voice → Microphone), so AirPods never drop into headset mode; capture restarts on `AVAudioEngineConfigurationChange`. System-wide keyboard shortcut via listen-only CGEvent tap.
- **Element Pointing**: the model embeds `[POINT:x,y:label:screenN]` tags in responses, with x,y on a 0-1000 grid over the screenshot (vision models answer far more accurately on that grid than in screenshot pixels). `CompanionManager` maps the grid point to global coordinates (`PointingGeometry.displayLocalPoint`), starts the flight toward a small box around the point and speaks immediately; meanwhile `AccessibilityElementBoundsResolver` asks macOS Accessibility for the element under it in the app owning the topmost window there (off the main actor, 400 ms cap) and a nearby element whose name matches the `[POINT]` label wins (`NamedElementSnap`); otherwise `ElementBoundsSelection` picks the rect (rejects Lumen's own windows, containers and anything over a quarter of the display, walks up from tiny hits, falls back to a 44×28 box). The overlay snaps to that rect mid-flight or after landing; `PointingRequestCounter` drops results that arrive after the pointing ended. The overlay flies the companion along a bezier arc, parks it just outside the rect (`PointingGeometry`), and the skin draws its mark around the rect with the element's name in a bubble.
- **Skins**: `LumenSkin` + `SkinTheme` (fixed palettes, system fonts New York / SF Mono / SF Rounded) chosen in AI Settings → Appearance (`AppSettings.selectedSkin`, not part of the client-rebuild merge). `SkinViews.swift` dispatches the companion (`CompanionVisualState`: idle/listening/thinking/speaking/flying), the pointing mark and the bubble to `EmberSkinViews`, `InstrumentSkinViews`, `MarginaliaSkinViews`; `SkinPanelBackground` draws the panel card (glass on macOS 26) and `SkinMenuBarIcon` the menu bar icon. Design: `docs/superpowers/specs/2026-10-19-skins-design.md`.
- **Replies on screen and auto-hide**: replies can also appear as text in a skin bubble beside the companion, revealed a little ahead of the voice (`ReplyDisplayMode`). The companion fades out while the user types, leaves the mouse still or uses a full-screen app (`CompanionAutoHide`), and always shows while listening, thinking, speaking or pointing.
- **Concurrency**: `@MainActor` isolation, async/await throughout
- **Analytics**: none. `LumenAnalytics.swift` is a no-op stub kept so call sites compile.
- **Networking**: `Info.plist` sets `NSAllowsLocalNetworking` so the app can reach `http://localhost:11434` (Ollama) despite App Transport Security.

### Key Architecture Decisions

**Menu Bar Panel Pattern**: The companion panel uses `NSStatusItem` for the menu bar icon and a custom borderless `NSPanel` for the floating control panel. This gives full control over appearance (dark, rounded corners, custom shadow) and avoids the standard macOS menu/popover chrome. The panel is non-activating so it doesn't steal focus. A global event monitor auto-dismisses it on outside clicks.

**Cursor Overlay**: A full-screen transparent `NSPanel` hosts the skinned companion (`CompanionOverlayView`). It's non-activating, joins all Spaces, and never steals focus. The cursor position, response text, waveform, and pointing animations all render in this overlay via SwiftUI through `NSHostingView`.

**Global Push-To-Talk Shortcut**: Background push-to-talk uses a listen-only `CGEvent` tap instead of an AppKit global monitor so modifier-based shortcuts like `ctrl + option` are detected more reliably while the app is running in the background.

**Shared URLSession for AssemblyAI**: A single long-lived `URLSession` is shared across all AssemblyAI streaming sessions (owned by the provider, not the session). Creating and invalidating a URLSession per session corrupts the OS connection pool and causes "Socket is not connected" errors after a few rapid reconnections.

**Transient Cursor Mode**: When "Show Lumen" is off, pressing the hotkey fades in the cursor overlay for the duration of the interaction (recording → response → TTS → optional pointing), then fades it out automatically after 1 second of inactivity.

## Key Files

| File | Lines | Purpose |
|------|-------|---------|
| `leanring_buddyApp.swift` | ~89 | Menu bar app entry point. Uses `@NSApplicationDelegateAdaptor` with `CompanionAppDelegate` which creates `MenuBarPanelManager` and starts `CompanionManager`. No main window — the app lives entirely in the status bar. |
| `CompanionManager.swift` | ~880 | Central state machine. Owns dictation, shortcut monitoring, screen capture, the active `ChatClient` and `TTSClient`, and overlay management. Observes `AppSettings` and rebuilds clients on change (`rebuildClientsFromSettings`). Tracks voice state (idle/listening/processing/responding), conversation history, and cursor visibility. Coordinates the full push-to-talk → screenshot → chat → TTS → pointing pipeline. |
| `AppSettings.swift` | ~230 | `@MainActor ObservableObject` singleton over UserDefaults: chat provider kind/base URL/model, STT provider, TTS provider (default `kokoro`), Kokoro voice, Apple voice id, ElevenLabs voice id, `isMemoryEnabled` (default on). Defines the `ChatProviderKind`, `SpeechToTextProviderKind`, `TextToSpeechProviderKind` enums with their defaults. |
| `SecretsStore.swift` | ~110 | Keychain wrapper for API keys (OpenRouter, Anthropic, AssemblyAI, ElevenLabs, OpenAI). `read`/`write`/`delete`/`hasValue`. Writing an empty string deletes. |
| `ChatClient.swift` | ~75 | `ChatClient` protocol shared by the chat backends, plus `ChatClientFactory.makeClient(from:)` which picks the implementation from `AppSettings`. |
| `OpenAICompatibleChatClient.swift` | ~190 | Streaming vision chat for any OpenAI-style `/chat/completions` endpoint (OpenRouter, Ollama, LM Studio…). Images sent as base64 data-URI `image_url` parts; parses `choices[0].delta.content` SSE. |
| `OllamaModelWarmer.swift` | ~65 | Fire-and-forget preload of the selected Ollama model with `keep_alive: -1` via the native `/api/generate` endpoint (the `/v1` endpoint ignores keep_alive). Called by `ChatClientFactory` whenever the Ollama provider is built. |
| `TTSClient.swift` | ~25 | `TTSClient` protocol (`speakText`, `isPlaying`, `stopPlayback`). |
| `TTSClientFactory.swift` | ~40 | `TTSClientFactory.makeClient(from:)` — picks Kokoro/Apple/ElevenLabs from `AppSettings`; fires the Kokoro warm-up. |
| `KokoroModelLoadCoordinator.swift` | ~95 | FluidAudio-free load sequencing: one in-flight load, late callers wait and re-check, failure sticky per voice (a different voice retries; `retryLoad` for the same). Unit-tested. |
| `KokoroModelLoadState.swift` | ~20 | `notLoaded/loading/ready/failed/unavailable`. |
| `KokoroSentenceSynthesizing.swift` | ~25 | Protocol the client uses for the engine, so tests can substitute a fake. |
| `AppleSpeechTTSClient.swift` | ~80 | On-device TTS via `AVSpeechSynthesizer`. Zero-download fallback. Tracks `isPlaying` through the synthesizer delegate. |
| `KokoroVoiceEngine.swift` | ~130 | Singleton owning the FluidAudio `KokoroAneManager`; conforms to `KokoroSentenceSynthesizing`. Delegates load sequencing to `KokoroModelLoadCoordinator`, republishes `loadState`, runs a warm-up synthesis after load, sentence → 24 kHz PCM buffer. |
| `KokoroTTSClient.swift` | ~130 | `TTSClient` for Kokoro (default): sentence split → synthesize → gapless queue; speaks with the Apple voice when the model can't load. |
| `SentenceAudioQueuePlayer.swift` | ~90 | `AVAudioEngine`/`AVAudioPlayerNode` queue for PCM buffers with generation-guarded `isPlaying` and `stop()`. |
| `SentenceSplitter.swift` | ~140 | Pure sentence chunker for TTS (merge pieces under 20 chars, split over 300 at a comma). Unit-tested. |
| `KokoroVoiceCatalog.swift` | ~80 | The 28 American/British Kokoro voice codes with readable labels; default `bm_george`. Unit-tested. |
| `KokoroOperatingSystemSupport.swift` | ~35 | Blocks Kokoro on macOS 26.4–26.5 (Apple BNNS crash bug, fixed in 26.6); v3 runtime availability. Unit-tested. |
| `ApplicationSupportFolderMigration.swift` | ~60 | One-time move of `~/Library/Application Support/Clicky` to `.../Lumen` (memory + Kokoro models) after the rename. `currentFolderURL` runs it on first access, so storage paths always resolve after the move. Unit-tested. |
| `LumenSkin.swift` | ~30 | The three skins (`ember`, `instrument`, `marginalia`), display names, default `.marginalia`. Unit-tested. |
| `SkinTheme.swift` | ~125 | Per-skin colour/type/shape tokens as hex strings and numbers (panel, companion, halo, mark, highlighter, bubble). Unit-tested. |
| `CompanionVisualState.swift` | ~30 | Resolves the companion's animation from the voice state and flight: flying > listening > thinking > speaking > idle. Unit-tested. |
| `PointingGeometry.swift` | ~65 | AppKit ⇄ Accessibility ⇄ overlay coordinate conversions and the companion's parking point beside a target. Unit-tested. |
| `ElementBoundsSelection.swift` | ~100 | Chooses the rect a pointing mark hugs from the Accessibility hit and its ancestors, or a fallback box. Unit-tested. |
| `PointingBubbleText.swift` | ~20 | Bubble text: the `[POINT]` label, else a short phrase. Unit-tested. |
| `WindowUnderPointSelection.swift` | ~35 | Picks the app owning the topmost on-screen window under a point, skipping Lumen's own overlay and transparent windows, so the Accessibility hit test targets that app. Unit-tested. |
| `PointingRequestCounter.swift` | ~30 | Numbers each pointing so a late Accessibility lookup only moves the mark while its pointing is still current. Unit-tested. |
| `ReplyDisplayMode.swift` | ~50 | Voice + text (default) / Voice only / Text only (`AppSettings.replyDisplayMode`, panel Voice → Replies) and `ReplyTextTiming` (40 chars/s reveal, 3 s linger after speech, text-only hold 3–20 s). Unit-tested. |
| `CompanionAutoHide.swift` | ~45 | When the companion steps aside: typing (not shortcuts), mouse still 3 s, or a full-screen frontmost app; never while Lumen is busy. Unit-tested. |
| `CompanionAutoHideMonitor.swift` | ~115 | Feeds `CompanionAutoHide`: 4 Hz mouse poll, global keyDown monitor (Lumen's own panel never counts), 1 Hz full-screen window check; publishes changes to `CompanionManager.isCompanionAutoHidden`. |
| `MicrophoneSelection.swift` | ~55 | `MicrophonePreference` (MacBook mic by default, or System default) and the rule picking the Core Audio input: the built-in mic even when AirPods are macOS's default; macOS chooses when there is none (lid closed). Unit-tested. |
| `AudioInputDeviceCatalog.swift` | ~95 | Core Audio input devices (id, name, built-in/Bluetooth/other) and the system default input. |
| `NamedElementSnap.swift` | ~95 | Snaps the mark to an element within 80 pt whose name matches the `[POINT]` label ("resign button" → "Resign"), ignoring filler words; nearest best match wins. The resolver hit-tests a 9×9 grid (every 20 pt) around the point, nearest first, to find candidates (1 s budget, runs while the reply is spoken). Unit-tested. |
| `SpeechPlaybackWaiter.swift` | ~30 | Waits (cancellable, with a deadline) until TTS playback ends so the companion stays in its speaking state for the whole reply. Unit-tested. |
| `AccessibilityElementBoundsResolver.swift` | ~120 | Accessibility element-at-point lookup off the main actor: window list → owning app → hit test, 150 ms per message and 400 ms overall; feeds `ElementBoundsSelection`. |
| `SkinViews.swift` | ~160 | `SkinCompanionView`, `SkinPointingMarkView`, `SkinBubbleView` dispatchers, `Font.skinFont`, `SkinMotion` timing helpers. |
| `EmberSkinViews.swift` | ~110 | Ember: warm orb (breathe, ripples, orbiting satellites, pulse) and a warm outline mark. |
| `InstrumentSkinViews.swift` | ~155 | Instrument: tick ring with orange core, sweep, corner brackets with x/y readout. |
| `MarginaliaSkinViews.swift` | ~155 | Marginalia (default): ink dot with Ember's motion, hand-drawn loop + highlighter mark. |
| `SkinMenuBarIcon.swift` | ~65 | Per-skin 18 pt template menu bar icon. |
| `SkinPanelBackground.swift` | ~60 | Per-skin panel card: system glass (macOS 26) / frosted fallback, or Instrument's solid card with a hard shadow. |
| `MemoryManager.swift` | ~515 | `@MainActor` singleton glue for memory: `prepareAtLaunch`, `memoryPromptBlock(forQuestion:)` (retrieval with a 5 s timeout → last-two-days fallback), `applyMemoryTags`, `recordExchange` (background summary + index), `forgetToday`. Catches every error; nothing throws into the reply pipeline. Talks to Ollama at the settings URL when Ollama is the chat provider, else the default local URL. |
| `MemoryStore.swift` | ~145 | `actor` doing all memory file I/O under an injected root (profile read/write, note append/read/list/delete, index read/write). Unit-tested against a temp dir. |
| `MemoryTagParser.swift` | ~100 | Strips `[REMEMBER:Section:fact]` / `[FORGET:text]` anywhere in a reply (case-insensitive, unterminated tag cut to end). Runs before `parsePointingCoordinates`. Unit-tested. |
| `MemoryTranscriptCommand.swift` | ~40 | "remember that/this/to …" at the start of a transcript → fact text. Unit-tested. |
| `ProfileMarkdownEditor.swift` | ~155 | Starter PROFILE.md, `ProfileSection` (About me/Projects/Tools/Preferences/Notes; unknown → Notes), append-under-heading (duplicate no-op), remove-bullet-only, prompt text. Unit-tested. |
| `DailyNoteEntry.swift` | ~105 | `HH:MM · App · summary` line format/parse, `YYYY-MM-DD.md` naming with an injected calendar. Unit-tested. |
| `DailyNoteSummarizer.swift` | ~85 | Summariser prompts, model-output sanitising (160 chars, no `·`/newlines/tags) and the raw `question → first sentence` fallback. Unit-tested. |
| `MemoryIndex.swift` | ~140 | `MemoryIndexDocument` (Codable, schema + model stamped), cosine `topHits`, staleness by file mtime, per-line embedding reuse. Unit-tested. |
| `MemoryPromptBuilder.swift` | ~90 | Builds the "what you know about the user" + "recent notes" block, 8,000-char cap, drops past-oldest → today-oldest → profile tail. Unit-tested. |
| `MemoryModelProvisioningState.swift` | ~30 | `notChecked/checking/pulling/ready/ollamaUnreachable/failed` + `MemoryModelCatalog` (`embeddinggemma`, `gemma4:e2b`). |
| `MemoryModelProvisioner.swift` | ~115 | Lists Ollama models and pulls the missing ones sequentially with progress; single in-flight run, sticky failure, `retry()`. Unit-tested with fakes. |
| `OllamaNativeEndpoints.swift` | ~180 | Pure URL/body/response helpers for Ollama's native `/api/tags`, `/api/pull`, `/api/embed`, `/api/generate`. Unit-tested. |
| `OllamaNativeClient.swift` | ~110 | URLSession wrapper over the endpoints above (streams pull progress; retries `generate` without `think` on HTTP 400). |
| `MenuBarPanelManager.swift` | ~243 | NSStatusItem + custom NSPanel lifecycle. Creates the menu bar icon, manages the floating companion panel (show/hide/position), installs click-outside-to-dismiss monitor. |
| `CompanionPanelView.swift` | ~960 | SwiftUI panel content for the menu bar dropdown, themed by the selected skin. Shows companion status, push-to-talk instructions, the collapsible **AI Settings** section (Appearance skin picker, provider/model/base URL, STT + TTS pickers, Kokoro voice picker with model-status row and Retry, Apple voice picker, Memory toggle + model status row + "Open memory folder"/"Forget today", Keychain-backed API key fields with Save), permissions UI, a Start button on first run, and quit button. |
| `OverlayWindow.swift` | ~700 | Full-screen transparent overlay (`CompanionOverlayView`) hosting the skinned companion, pointing mark and bubbles. Handles cursor following, the bezier flight to a target, parking beside the element rect, multi-monitor coordinate mapping, and the first-run welcome → prompt bubbles. |
| `CompanionResponseOverlay.swift` | ~217 | Unused upstream response-bubble panel (never instantiated). |
| `CompanionScreenCaptureUtility.swift` | ~132 | Multi-monitor screenshot capture using ScreenCaptureKit. Returns labeled image data for each connected display. |
| `BuddyDictationManager.swift` | ~866 | Push-to-talk voice pipeline. Handles microphone capture via `AVAudioEngine`, provider-aware permission checks, keyboard/button dictation sessions, transcript finalization, shortcut parsing, contextual keyterms, and live audio-level reporting for waveform feedback. |
| `BuddyTranscriptionProvider.swift` | ~110 | Protocol surface and provider factory for voice transcription backends. Resolves provider from `AppSettings.speechToTextProviderKind` (falls back to `VoiceTranscriptionProvider` in Info.plist) — Apple Speech, AssemblyAI, or OpenAI. Falls back to Apple when a cloud provider has no key. |
| `AssemblyAIStreamingTranscriptionProvider.swift` | ~490 | Streaming transcription provider. Exchanges the Keychain API key for a temp token at `streaming.assemblyai.com/v3/token`, opens an AssemblyAI v3 websocket, streams PCM16 audio, tracks turn-based transcripts, and delivers finalized text on key-up. Shares a single URLSession across all sessions. |
| `OpenAIAudioTranscriptionProvider.swift` | ~320 | Upload-based transcription provider. Key from Keychain (Info.plist `OpenAIAPIKey` as fallback). Buffers push-to-talk audio locally, uploads as WAV on release, returns finalized transcript. |
| `AppleSpeechTranscriptionProvider.swift` | ~147 | Local fallback transcription provider backed by Apple's Speech framework. |
| `BuddyAudioConversionSupport.swift` | ~108 | Audio conversion helpers. Converts live mic buffers to PCM16 mono audio and builds WAV payloads for upload-based providers. |
| `GlobalPushToTalkShortcutMonitor.swift` | ~132 | System-wide push-to-talk monitor. Owns the listen-only `CGEvent` tap and publishes press/release transitions. |
| `ClaudeAPI.swift` | ~300 | Anthropic Messages API client (direct, `x-api-key` from Keychain) with streaming (SSE) and non-streaming modes. Conforms to `ChatClient`. TLS warmup optimization, image MIME detection, conversation history support. |
| `OpenAIAPI.swift` | ~142 | Legacy OpenAI GPT vision API client. Unused; superseded by `OpenAICompatibleChatClient`. |
| `ElevenLabsTTSClient.swift` | ~95 | ElevenLabs TTS client (direct, `xi-api-key` from Keychain). Conforms to `TTSClient`. Plays back audio via `AVAudioPlayer`. Exposes `isPlaying` for transient cursor scheduling. |
| `ElementLocationDetector.swift` | ~335 | Unused upstream Anthropic computer-use point detector (never instantiated); pointing uses `[POINT]` + Accessibility instead. |
| `DesignSystem.swift` | ~880 | Design system tokens — colors, corner radii, shared styles. All UI references `DS.Colors`, `DS.CornerRadius`, etc. |
| `LumenAnalytics.swift` | ~30 | No-op stub. Upstream's PostHog integration was removed; method names kept so call sites compile. |
| `WindowPositionManager.swift` | ~262 | Window placement logic, Screen Recording permission flow, and accessibility permission helpers. |
| `AppBundleConfiguration.swift` | ~28 | Runtime configuration reader for keys stored in the app bundle Info.plist. |

## Build & Run

```bash
# Open in Xcode
open leanring-buddy.xcodeproj

# Select the leanring-buddy scheme, set signing team, Cmd+R to build and run

# Known non-blocking warnings: Swift 6 concurrency warnings,
# deprecated onChange warning in OverlayWindow.swift. Do NOT attempt to fix these.
```

**Do NOT run `xcodebuild` from the terminal** — it invalidates TCC (Transparency, Consent, and Control) permissions and the app will need to re-request screen recording, accessibility, etc.

## Typechecking without Xcode

To catch compile errors from the terminal without producing an app bundle (and therefore without disturbing TCC permissions):

```bash
tools/typecheck.sh      # prints "typecheck: 0 errors" on success
```

It runs `swiftc -typecheck` with the app's settings (macOS 14.2, main-actor default isolation) and, once Xcode has built the project at least once, points the compiler at the FluidAudio module in DerivedData so files that `import FluidAudio` typecheck too.

## Terminal tests

Pure-logic files (no AppKit/FluidAudio imports) are symlinked into a small SwiftPM package so their Swift Testing suites run from the terminal:

```bash
cd tools/logic-tests && swift test
```

After adding a new symlink, delete `tools/logic-tests/.build` once — SwiftPM caches the source list. Test files live in `leanring-buddyTests/` and import the module conditionally (`leanring_buddy` in Xcode, `LumenLogic` in the harness), so Cmd+U runs the same tests.

## Xcode MCP

Xcode 26.3+ ships an MCP server (`xcrun mcpbridge`). It is registered for Claude Code at user scope; enable it in Xcode → Settings → Intelligence (Enable Model Context Protocol + Xcode Tools) so an agent can build, test and read issues through Xcode itself without touching TCC.

## Configuration

No config files. Provider/model/voice choices live in UserDefaults via `AppSettings`; API keys live in the Keychain via `SecretsStore`. Both are edited from the panel's **AI Settings** section. `.env.example` lists the keys for documentation only — the app never reads it.

## Code Style & Conventions

### Variable and Method Naming

IMPORTANT: Follow these naming rules strictly. Clarity is the top priority.

- Be as clear and specific with variable and method names as possible
- **Optimize for clarity over concision.** A developer with zero context on the codebase should immediately understand what a variable or method does just from reading its name
- Use longer names when it improves clarity. Do NOT use single-character variable names
- Example: use `originalQuestionLastAnsweredDate` instead of `originalAnswered`
- When passing props or arguments to functions, keep the same names as the original variable. Do not shorten or abbreviate parameter names. If you have `currentCardData`, pass it as `currentCardData`, not `card` or `cardData`

### Code Clarity

- **Clear is better than clever.** Do not write functionality in fewer lines if it makes the code harder to understand
- Write more lines of code if additional lines improve readability and comprehension
- Make things so clear that someone with zero context would completely understand the variable names, method names, what things do, and why they exist
- When a variable or method name alone cannot fully explain something, add a comment explaining what is happening and why

### Swift/SwiftUI Conventions

- Use SwiftUI for all UI unless a feature is only supported in AppKit (e.g., `NSPanel` for floating windows)
- All UI state updates must be on `@MainActor`
- Use async/await for all asynchronous operations
- Comments should explain "why" not just "what", especially for non-obvious AppKit bridging
- AppKit `NSPanel`/`NSWindow` bridged into SwiftUI via `NSHostingView`
- All buttons must show a pointer cursor on hover
- For any interactive element, explicitly think through its hover behavior (cursor, visual feedback, and whether hover should communicate clickability)

### Do NOT

- Do not add features, refactor code, or make "improvements" beyond what was asked
- Do not add docstrings, comments, or type annotations to code you did not change
- Do not try to fix the known non-blocking warnings (Swift 6 concurrency, deprecated onChange)
- Do not rename the project directory or scheme (the "leanring" typo is intentional/legacy)
- Do not run `xcodebuild` from the terminal — it invalidates TCC permissions

## Git Workflow

- Branch naming: `feature/description` or `fix/description`
- Commit messages: imperative mood, concise, explain the "why" not the "what"
- Do not force-push to main

## Self-Update Instructions

<!-- AI agents: follow these instructions to keep this file accurate. -->

When you make changes to this project that affect the information in this file, update this file to reflect those changes. Specifically:

1. **New files**: Add new source files to the "Key Files" table with their purpose and approximate line count
2. **Deleted files**: Remove entries for files that no longer exist
3. **Architecture changes**: Update the architecture section if you introduce new patterns, frameworks, or significant structural changes
4. **Build changes**: Update build commands if the build process changes
5. **New conventions**: If the user establishes a new coding convention during a session, add it to the appropriate conventions section
6. **Line count drift**: If a file's line count changes significantly (>50 lines), update the approximate count in the Key Files table

Do NOT update this file for minor edits, bug fixes, or changes that don't affect the documented architecture or conventions.
