# HANDOFF — read this first after a context reset

Last updated: 2026-10-14. Branch `feature/direct-providers`, pushed to `willhammondhimself/clicky`.

## Where we are

The fork builds and the core loop works end to end on Will's M4 Pro (48 GB):
hold Ctrl+Option → Apple Speech (on-device) → screenshot → `gemma4:26b` on Ollama → spoken answer + cursor flies to the right element. Verified by Will in the real app ("got the right answer"). Measured model latency with an app-sized screenshot: 5.9 s → 2.1 s → 0.9 s, model 100% on GPU.

Commits on top of upstream `a80fa80`:

| Commit | What |
|---|---|
| `ea1fede` | Direct provider calls, Keychain keys, AI Settings panel, STT/TTS toggles, telemetry removed, SPM deps dropped |
| `7fd4fdf` | Main-actor isolation warning fixes (project uses `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`) |
| `9c7a8d6` | `reasoning_effort: "none"` for the Ollama provider — gemma4 thinks by default and returned empty text |
| `340ceef` | `OllamaModelWarmer`: preload + `keep_alive: -1` via native `/api/generate` (the `/v1` endpoint ignores keep_alive) |
| `949b83d` | Ollama default URL `127.0.0.1` (localhost → `::1` first → refused) |

Settings model (all in the panel's **AI Settings**, persisted in UserDefaults via `AppSettings`; keys in Keychain via `SecretsStore`):
- Chat: `ChatProviderKind` = ollama (default) | openRouter | anthropicDirect | custom; base URL + model text fields
- STT: `SpeechToTextProviderKind` = apple (default) | assemblyAI | openAI
- TTS: `TextToSpeechProviderKind` = apple (default) | elevenLabs; Apple voice picker

Will downloaded the **Zoe (Premium)** Apple voice; it's the ceiling for AVSpeechSynthesizer and he still wants better.

## Conventions that bite

- **Never run `xcodebuild` from the terminal** — resets TCC grants. Will builds with Cmd+R. Typecheck instead:
  `xcrun swiftc -typecheck -sdk "$(xcrun --show-sdk-path --sdk macosx)" -target arm64-apple-macos14.2 -parse-as-library -default-isolation MainActor leanring-buddy/*.swift`
- Xcode project uses **synchronized folders**: new `.swift` files in `leanring-buddy/` are picked up automatically; no pbxproj edits.
- SourceKit per-file "cannot find type" diagnostics are noise (no module context). Trust the typecheck above.
- Don't rename the `leanring-buddy` dir/scheme. Don't fix upstream's known Swift-6 warnings.
- Commit messages: no AI attribution lines (Will's global rule).
- Default actor isolation is MainActor: unannotated types are main-actor. Mark things `nonisolated` deliberately when they must be read from non-main contexts (see `AppSettings.Keys`).

## NEXT FEATURE: local Kokoro TTS via FluidAudio

**Goal:** a third TTS option, "Kokoro (local)", that sounds close to ElevenLabs, runs offline, costs nothing. Becomes the new default once it works.

**Why FluidAudio and not a Python sidecar:** it's a pure Swift package (CoreML/ANE), Apache-2.0, 3k stars, v0.17.7 released 2026-10-08, actively maintained. No Python, no extra process. It also ships Parakeet STT, which is the planned STT upgrade later — one dependency covers both.

**Facts verified 2026-10-14 (from the repo's `Documentation/TTS/KokoroAne.md` and `Benchmarks.md`):**
- SPM: `https://github.com/FluidInference/FluidAudio`, single library product `FluidAudio` (docs mentioning `FluidAudioTTS` are stale).
- API:
  ```swift
  import FluidAudio
  let kokoro = KokoroAneManager(version: .v3)          // v3 needs macOS 15+; we're on 26
  try await kokoro.initialize(preloadVoices: ["af_heart"])
  let wav = try await kokoro.synthesize(text: "Hello world.", voice: "af_heart")   // returns WAV data
  let detailed = try await kokoro.synthesizeDetailed(text: ...)  // timings, usedFastVocoder
  ```
- Latency: ~50–80 ms for a 3.3 s English sentence on M5 Pro (complete audio, not streaming). Effectively instant for Clicky's 1–2 sentence replies.
- Models download on first `initialize()` from HF `FluidInference/kokoro-82m-coreml` (pinned revision, hash-verified) and compile on device → first launch is slow (tens of seconds, needs network once); cached after under `<Models>/kokoro-82m-coreml/ANE-v3/…`. `directory:` overrides the cache root.
- Voices: 54 English (`af_heart` default, `af_bella`, `am_adam`, `am_michael`…). Limits: ≤ 510 phonemes per call, ≤ 5 s audio on the fast path — **chunk by sentence** upstream.
- Known caveat: v3 is "opt-in", maintainers note Core ML crash advisories on OS 26.4+/27 for other compute policies; v3's fixed hybrid routing completed their checks. If v3 misbehaves, `version: .legacy` is the fallback.
- Other backends in the same package if Kokoro disappoints: Chatterbox (Will already has Chatterbox from the Haven project), PocketTTS, Supertonic3, LuxTts.

**Integration sketch (to be designed properly in the brainstorm — do not just build this):**
1. Add FluidAudio SPM dependency (pbxproj via Xcode UI, or ask Will to add it in Xcode: File → Add Package Dependencies).
2. `KokoroTTSClient.swift` conforming to `TTSClient`: lazy `KokoroAneManager`, `initialize()` on first use (or at launch, off-main, with a "downloading voice model…" state), sentence-chunk the text, synthesize → `AVAudioPlayer` (or `AVAudioEngine` for gapless chunk streaming), `isPlaying`/`stopPlayback` like the ElevenLabs client.
3. `TextToSpeechProviderKind.kokoro`, voice picker for the English voice list, `TTSClientFactory` case.
4. Warm-up on launch when selected (same spirit as `OllamaModelWarmer`) so the first reply isn't slow.
5. Open questions for the brainstorm: play chunks as they're produced vs wait for all; where the model cache lives; what the UI shows during the one-time download; whether to drop the Apple option afterwards (no — keep as zero-download fallback).

**After this:** memory (profile + daily notes + "remember this" tool), then wake word, then proactive, then background tasks — see `~/.claude/plans/great-make-a-plan-soft-curry.md` and the brainstorm decomposition in the session.

## Research artifacts from this session (not persisted elsewhere)

Three deep-research reports on HeyClicky (what it does, weekly ship log v1.0→v1.0.53, open-source architecture incl. exact system prompt and pointing math) were produced as workflow outputs under the session's `tasks/` dir. Key takeaways already applied: pointing tag grammar, 1280-px JPEG capture, HeyClicky's PROFILE.md/VOLATILE.md memory design (for the memory feature), and that HeyClicky removed proactive agents for annoyance/privacy reasons (v1.0.46) — design proactive narrowly.
