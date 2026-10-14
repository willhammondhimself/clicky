# Kokoro local text-to-speech — design

Date: 2026-10-14. Status: approved by Will in the brainstorm; implementation plan to follow.

## Goal

Add a third text-to-speech option, **Kokoro (local)**, that sounds close to ElevenLabs, runs fully offline after a one-time model download, costs nothing, and becomes the default voice. Apple voices stay as the zero-download fallback; ElevenLabs stays opt-in.

Success looks like: hold the hotkey, ask a question, and hear a British male Kokoro voice start well under a second after the model finishes its reply, with no gaps between sentences and no robotic artifacts. Switching back to Apple or ElevenLabs in AI Settings still works.

## Decisions made with Will

| Question | Decision |
|---|---|
| Playback | Sentence queue: split the reply into sentences, synthesize each, play them back to back through an audio engine. |
| First run (model download + compile) | Block: the spinner stays up until the model is ready, then the reply is spoken in Kokoro. The engine also warms at launch so this rarely happens. |
| Default | Kokoro is the fresh-install default. Existing installs keep their stored choice. |
| Dependency | Claude edits `project.pbxproj` to add the FluidAudio package pinned to 0.17.7; Will's Cmd+R resolves it. |
| Voice | JARVIS-like British male. Default `bm_george`. The 28 American/British voices are selectable (FluidAudio's `englishVoices` list also contains other-language packs, which are excluded). |
| Not in scope | Voice cloning (Chatterbox), speaking while the model is still streaming, a "chooser" model (OpenJev-style option scoring) — that one is a fit for accessibility-tree pointing later, not for TTS. |

## Verified facts about FluidAudio (read from the package source, 2026-10-14)

- Package: `https://github.com/FluidInference/FluidAudio`, Apache-2.0, release v0.17.7 (2026-10-08). Single library product `FluidAudio`. Platforms `.macOS(.v14)`. No external package dependencies; one binary `NemoTextProcessing.xcframework` fetched by SwiftPM. Kokoro code is compiled under the package's own `TTS` define (on by default).
- `public actor KokoroAneManager`. Initializer: `init(variant: .english, defaultVoice: String? = nil, directory: URL? = nil, computeUnits: .default, modelStore: nil, version: KokoroAneVersion = .legacy)`. `version: .v3` needs macOS 15+.
- `initialize(preloadVoices: Set<String>? = nil) async throws` downloads (if missing), compiles and loads the models plus the default voice pack. `isAvailable() async -> Bool`. `cleanup() async`.
- `synthesizeDetailed(text:voice:speed:) async throws -> KokoroAneSynthesisResult` returns `samples: [Float]` at `sampleRate` 24 000 plus timings. `synthesize(text:voice:speed:) -> Data` is the same as 16-bit WAV. Text over 510 phonemes is chunked automatically by the library.
- Voices: `KokoroAneConstants.englishVoices` (54 names; `af_heart` ships pre-converted, every other voice pack is downloaded and converted on first use). Unknown names throw `KokoroAneError.voiceNotFound`.
- v3 fast path: up to 200 acoustic frames (five seconds of audio) per chunk; above that the slower original vocoder is used. Sentence chunking keeps each call on the fast path.
- Cold load (first ever): downloads plus on-device ANE compile, about 20 s on M1 per the docs. Warm load about 0.3 s. Synthesis about 300 ms per 5 s of audio on M1; a 3 s sentence is reported at 50–80 ms on recent chips.
- Cache layout: `<Models>/kokoro-82m-coreml/ANE-v3/<revision>/en/` and `<Models>/kokoro/` for the text frontend. Passing `directory:` sets `<Models>`.
- OS advisory baked into the library: macOS 26.4 and 26.5 have an Apple BNNS bug that can crash synthesis in-process (EXC_BAD_ACCESS, not catchable); 26.6 fixes it. Will is on 26.3.

## Architecture

Three new source files plus pure helpers, all in `leanring-buddy/`, following the existing `TTSClient` protocol and the "factory builds a client from `AppSettings`" pattern. `CompanionManager` only gains the `kokoroVoice` publisher in `bindSettingsObservation`. (Implementation note: the voice list and labels live in `KokoroVoiceCatalog`, not `AppSettings`, so they stay free of the FluidAudio import and run in the terminal test harness; the engine also runs one throwaway synthesis after load because the first call otherwise pays ~9 s for the lexicon load and Neural Engine compile.)

### `KokoroVoiceEngine` (new file)

Main-actor singleton (`KokoroVoiceEngine.shared`) because the factory rebuilds TTS clients on every settings change and the Kokoro models must load once, not per client.

- Owns one `KokoroAneManager`, created lazily with `variant: .english`, `directory: ~/Library/Application Support/Clicky/Models`, and `version: .v3` when `#available(macOS 15, *)`, else `.legacy`.
- `@Published private(set) var loadState: LoadState` with cases `notLoaded`, `loading`, `ready`, `failed(message: String)`, `unavailable(reason: String)`.
- `func prepareIfNeeded(preloadingVoice voice: String) async` — idempotent. If a load is already in flight it awaits that task. Sets `loading`, calls `initialize(preloadVoices: [voice])` off the main actor, then `ready` or `failed`. Also called fire-and-forget by the factory (see wiring).
- `func synthesizeSentence(_ sentence: String, voice: String) async throws -> AVAudioPCMBuffer` — calls `synthesizeDetailed`, copies `samples` into a 24 kHz mono Float32 buffer. Throws `KokoroVoiceEngineError.modelNotReady` if `loadState` is not `ready`.
- `static func operatingSystemBlocksKokoro() -> String?` — returns the reason string for macOS 26.4–26.5, nil otherwise. When non-nil, `loadState` starts as `unavailable` and `prepareIfNeeded` returns immediately.
- `func retryLoad(voice:)` — resets `failed` to `notLoaded` and calls `prepareIfNeeded`.

### `SentenceAudioQueuePlayer` (new file)

Main-actor class wrapping `AVAudioEngine` + `AVAudioPlayerNode` connected at 24 kHz mono Float32.

- `func enqueue(_ buffer: AVAudioPCMBuffer)` — starts the engine and node if needed, schedules the buffer with `completionCallbackType: .dataPlayedBack`, increments `scheduledBufferCount`; the completion decrements it on the main actor.
- `var isPlaying: Bool` — `scheduledBufferCount > 0`.
- `func stop()` — `playerNode.stop()`, resets the count. The engine is left running between replies to avoid start latency; it is stopped only on `deinit`.
- Output goes to the system default output device; no device selection.

### `KokoroTTSClient` (new file)

Conforms to `TTSClient`. Constructed by the factory with the chosen voice. Holds an `AppleSpeechTTSClient` for fallback.

`speakText(_:)`:
1. `stopPlayback()`.
2. `await engine.prepareIfNeeded(preloadingVoice: voice)`. The caller keeps the spinner up during this await (`voiceState` stays `.processing` until `speakText` returns), which is the agreed blocking first-run behaviour.
3. If `loadState` is `failed` or `unavailable`: log the reason and delegate the whole call to the Apple client, then return.
4. `sentences = SentenceSplitter.split(text)`.
5. Synthesize the first sentence, enqueue it, then return (this flips the UI to "responding").
6. Before returning, start `remainingSentencesTask` that synthesizes and enqueues the rest in order, checking `Task.isCancelled` between sentences.

`isPlaying`: `player.isPlaying || remainingSentencesTask is running || appleFallbackClient.isPlaying`.

`stopPlayback()`: cancels `remainingSentencesTask`, `player.stop()`, `appleFallbackClient.stopPlayback()`.

### `SentenceSplitter` (new file, pure function, unit-tested)

`static func split(_ text: String) -> [String]`:
- Split after `.`, `?`, `!` (optionally followed by closing quotes/brackets) when followed by whitespace or end of text, and on newlines.
- Trim each piece; drop empties.
- Merge any piece shorter than 20 characters into the following piece (or the preceding one if it is last), so "ok." does not become its own 80 ms synth call.
- Any piece longer than 300 characters is split at the last comma before 300; if there is no comma, it is left whole (the library chunks at 510 phonemes anyway).
- If the result is empty, return `[text.trimmed]` when non-empty, else `[]`. `speakText` with no sentences is a no-op.

### Settings (`AppSettings.swift`)

- `TextToSpeechProviderKind` gains `case kokoro`, display name "Kokoro (local)", `secretKey` nil. The fresh-install default becomes `.kokoro`; a stored value is always respected.
- New `@Published var kokoroVoice: String` (`Keys.kokoroVoice = "settings.kokoroVoice"`), default `AppSettings.defaultKokoroVoice = "bm_george"`.
- `static func availableKokoroVoices() -> [KokoroVoiceOption]` where `KokoroVoiceOption` has `id` (the raw code), `label`, and sort order. Labels come from the code: first letter `a`/`b` → American/British, second `f`/`m` → female/male, the rest capitalised, e.g. `bm_george` → "George (British, male)". British voices first, then American, alphabetical within each.

### Factory (`TTSClient.swift`)

`case .kokoro`: call `KokoroVoiceEngine.shared.prepareIfNeeded(preloadingVoice:)` in a fire-and-forget `Task` (same spirit as `OllamaModelWarmer`), then return `KokoroTTSClient(voice: appSettings.kokoroVoice)`. The existing `CompanionManager` settings observer already rebuilds clients when the provider or voice changes, so changing the voice re-warms that voice pack.

### Panel (`CompanionPanelView.swift`)

In the TTS `switch`, add `case .kokoro:` with:
- A "Voice" picker bound to `appSettings.kokoroVoice` over `availableKokoroVoices()`, same row style as the Apple voice picker.
- A status row below it driven by `KokoroVoiceEngine.shared.loadState` (observed via `@ObservedObject`): "downloading voice model…" (with a small `ProgressView`) for `loading`, "ready" for `ready`, the message for `failed` with a "Retry" button (pointer cursor on hover, as every button here), and the reason for `unavailable`.
- The footer sentence becomes "Keys are stored in your macOS Keychain. Leave everything on Ollama + Kokoro to run fully offline."

### Project wiring

- `leanring-buddy.xcodeproj/project.pbxproj`: add an `XCRemoteSwiftPackageReference` for `https://github.com/FluidInference/FluidAudio` with `kind = exactVersion; version = 0.17.7;`, an `XCSwiftPackageProductDependency` for product `FluidAudio`, link it in the app target's `packageProductDependencies` and Frameworks build phase, and list the reference in the project's `packageReferences`. The test and UI-test targets do not link it. Xcode writes `Package.resolved` on first build; it gets committed.
- Deployment target stays 14.2 (package minimum is 14). v3 vs legacy is chosen at runtime with `#available`.
- No Info.plist or entitlement changes: the app is not sandboxed, Hugging Face is HTTPS, and ANE compilation needs nothing extra.
- Docs: `AGENTS.md` Key Files table and Architecture TTS line, README voice section, `docs/HANDOFF.md` status.

## Data flow for one reply

```
CompanionManager.speakText(spokenText)
  └─ KokoroTTSClient.speakText
       ├─ stopPlayback()
       ├─ await KokoroVoiceEngine.prepareIfNeeded      (no-op when ready; blocks on first run)
       ├─ loadState failed/unavailable? → AppleSpeechTTSClient.speakText, return
       ├─ SentenceSplitter.split(text) → [s1, s2, …]
       ├─ buffer1 = await engine.synthesizeSentence(s1)  (~50–300 ms)
       ├─ player.enqueue(buffer1)                        (audio starts)
       ├─ remainingSentencesTask = Task { for s in rest { enqueue(await synthesize(s)) } }
       └─ return                                         → voiceState = .responding
scheduleTransientHideIfNeeded polls isPlaying until the queue drains.
```

## Error handling

| Situation | Behaviour |
|---|---|
| No network on first run | `initialize` throws → `loadState = .failed("…")`; reply spoken by Apple voice; status row shows the error with Retry. |
| Voice pack download fails for a non-default voice | Same path as above; the message names the voice. Retry re-attempts. |
| `synthesizeSentence` throws mid-reply | Log, speak the remaining text with the Apple client, keep `loadState` as is. |
| macOS 26.4–26.5 | Engine never loads; `unavailable(reason)`; Apple voice used; row explains. |
| User presses the hotkey while speaking | Existing `stopPlayback` call: task cancelled, queue cleared, nothing else to clean up. |
| Settings change mid-speech | `rebuildClientsFromSettings` already calls `stopPlayback` before swapping clients; the engine singleton persists. |

Nothing in this feature throws out of `speakText` except what the Apple fallback could throw today, so `CompanionManager`'s existing catch block is unchanged.

## Testing

Unit tests (existing `leanring-buddyTests` target, run by Will in Xcode):
- `SentenceSplitterTests`: plain sentences, abbreviations with trailing space ("e.g. this"), short fragment merging, 300-character comma split, newline handling, empty and whitespace-only input, text with no terminal punctuation.
- `KokoroVoiceLabelTests`: `bm_george` → "George (British, male)", `af_heart` → "Heart (American, female)", British sorted before American.
- `KokoroVoiceEngine.operatingSystemBlocksKokoro` for 26.3, 26.4, 26.5, 26.6, 27.0.

Manual checklist (Cmd+R, never `xcodebuild`):
1. Fresh state (delete `~/Library/Application Support/Clicky/Models`): select Kokoro, ask a question immediately → spinner, then Kokoro speech; status row went downloading → ready.
2. Quit and relaunch → first reply within ~0.5 s of the model finishing (warm load).
3. Change voice to `bm_fable` → next reply uses it; status row briefly shows downloading for the new pack.
4. Ask a multi-sentence question → no audible gaps between sentences.
5. Press the hotkey mid-sentence → speech stops immediately, new recording starts.
6. Switch TTS to Apple, then ElevenLabs, then back → each works; no stuck `isPlaying` (transient cursor fades out).
7. Wi-Fi off with models cached → Kokoro still speaks.
8. Terminal typecheck: the files that `import FluidAudio` cannot be typechecked until Xcode has built the package once. After Will's first Cmd+R, the `swiftc -typecheck` command from `docs/HANDOFF.md` gains `-I <dir containing FluidAudio.swiftmodule>` found under `~/Library/Developer/Xcode/DerivedData/leanring-buddy-*/Build/Products/Debug/`. Until then, Cmd+R is the compile check.

## Out of scope / later

- Speaking sentences while the model is still streaming (needs `CompanionManager` changes; the queue player is already the right shape).
- Chatterbox voice cloning via the same package.
- Parakeet speech-to-text via the same package (planned STT upgrade).
- A chooser model (OpenJev-style option scoring) for accessibility-tree pointing and local/cloud routing.
