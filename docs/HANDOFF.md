# HANDOFF — read this first after a context reset

Last updated: 2026-10-19. Branch `feature/lumen-rename` (off `feature/direct-providers`, where Kokoro and memory are merged; memory landed via PR #1 on 2026-10-18). The app is being renamed from Clicky to **Lumen** and redesigned (see below). Kokoro work: `docs/superpowers/plans/2026-10-14-kokoro-tts.md`; memory work: `docs/superpowers/plans/2026-10-17-memory.md` (decisions + architecture).

## Where we are

The fork builds and the core loop works end to end, fully offline, on Will's M4 Pro (48 GB):
hold Ctrl+Option → Apple Speech (on-device) → screenshot → `gemma4:26b` on Ollama → **Kokoro** British male voice (on-device) + cursor flies to the right element. Will verified all of that in the real app on 2026-10-15.

**Rename to Lumen (2026-10-19, in progress on `feature/lumen-rename`):**
- Full rename, chosen by Will: display name, `PRODUCT_NAME`, bundle id `com.willhammond.lumen` (tests `…lumenTests`), Keychain service `com.willhammond.lumen`, log prefixes, prompts, Swift identifiers (`LumenAnalytics`, `isLumenCursorEnabled`, `.lumenDismissPanel`), harness module `LumenLogic`. Kept on purpose: the `leanring-buddy` directory, scheme and Swift module name (`PRODUCT_MODULE_NAME = leanring_buddy` is now explicit), the upstream credit in README/LICENSE, and the old plans/specs (historical).
- The GitHub repo is now `willhammondhimself/lumen` (old URLs redirect) and the local folder is `~/code/lumen` (renamed 2026-10-19). Xcode's DerivedData for the old path is stale; the first Cmd+R from the new folder builds fresh.
- **Consequences for Will on first Cmd+R:** macOS sees a new app, so re-grant Microphone, Accessibility, Screen Recording and Screen Content; re-enter API keys (the Keychain service changed); UserDefaults start fresh (provider, voice and model fall back to the local defaults). Remove the old Clicky entry from System Settings → General → Login Items, and quit any running Clicky (`pgrep -fl Clicky.app`).
- `ApplicationSupportFolderMigration` moves `~/Library/Application Support/Clicky` to `.../Lumen` on first access of either storage path, so memory notes and the Kokoro models survive. If both folders exist nothing is moved. Existing `PROFILE.md` text still says "clicky"; edit by hand.
- `TEST_HOST` in the test targets pointed at a non-existent `leanring-buddy.app` while the product was named Clicky; it now points at `Lumen.app`. Unverified until Will runs Cmd+U.
- **Skins built 2026-10-19** (plan `docs/superpowers/plans/2026-10-19-skins.md`, ledger rulings in the final report): Ember / Instrument / Marginalia, default Marginalia with Ember's motion; picker in AI Settings → Appearance; panel, menu bar icon, overlay companion, marks and bubbles follow the skin live. Pointing snaps to the Accessibility element under the model's point (fallback 44×28 box). Upstream onboarding (Farza video, music, email field, DM button, replay link, pointing demo) and assets removed; interim first run = permissions → Start → skinned welcome → "press control + option" prompt. App icon: "Glass lens" (a liquid-glass lens over a cursor arrow), picked by Will from the icon board https://claude.ai/artifact/5pbkoB67bG4F79ZqeDR5s2 after rejecting the ink-dot icon; regenerate with `swift tools/app-icon/render-app-icon.swift leanring-buddy/Assets.xcassets/AppIcon.appiconset`. macOS caches icons, so System Settings may show the old one until a relaunch or `killall Dock`. A proper Lumen onboarding is still to be designed.
- **What Will checks on Cmd+R (skins):** switch skins live (panel, menu bar icon and companion change at once); ask "where's the export button" in Finder/Xcode/Safari and see the mark hug the button in each skin; try an Electron app and a canvas app for the fallback box; check the companion reads on light and dark windows; nothing says Clicky or Farza. Console prints `🎯 Target rect: accessibilityElement|fallbackBox (…)`.

**Memory (2026-10-17, implemented, not yet run by Will):**
- `~/Library/Application Support/Lumen/Memory/PROFILE.md` (starter prefilled about Will; `- ` bullets under `## About me / Projects / Tools / Preferences / Notes`) and `notes/YYYY-MM-DD.md` (`HH:MM · App · summary` lines) plus `notes/index.json` (embeddings).
- Every question: profile whole + today's note whole + top-8 past lines by `embeddinggemma` cosine (≥ 0.3; calibrated 2026-10-17 — relevant lines score ≈0.45–0.5, unrelated ≤0.2, with the EmbeddingGemma task prefixes) appended to the system prompt (8,000-char cap). Falls back to profile + yesterday whole when the models aren't ready or Ollama is down (5 s retrieval timeout).
- Writes: model emits `[REMEMBER:Section:fact]` / `[FORGET:text]` (stripped before TTS; `MemoryTagParser` runs before the POINT parser). "remember that …" at the start of a question is the fallback. FORGET removes the closest profile line (embedding ≥ 0.4 — paraphrases score 0.45–0.6, absent facts ≤ 0.25 — else substring) and Lumen says "forgot: …"; a `forgot:` paper-trail line goes to today's note.
- After each reply, the Ollama chat model (already loaded; same `keep_alive` -1, no `num_ctx`, so Ollama doesn't reload it) summarises the exchange into one note line in the background, then the new line is embedded. With a cloud chat provider, or when that request fails, the raw `question → first sentence` line is written instead: no local model is loaded just for summaries. Until 2026-10-19 this was `gemma4:e2b`, dropped because a fourth model made Ollama (max three loaded) evict embeddinggemma, adding ~0.8 s before every reply; blind judging of 20 exchanges preferred gemma4:26b's summaries 49–9 (2 ties), at 724 ms vs 390 ms median, off the reply path.
- `embeddinggemma` is pulled from Ollama at launch when missing (status row under AI Settings → Memory, Retry on failure). Memory always talks to Ollama even when chat is on a cloud provider (settings URL when provider is Ollama, else `http://127.0.0.1:11434`).
- Panel: "Remember things" toggle (default on), status row with profile fact count, "Open memory folder", "Forget today".
- Cold-path reset: delete the `Memory/` folder and `ollama rm embeddinggemma`. An existing `gemma4:e2b` is left on disk (Lumen no longer uses it; `ollama rm gemma4:e2b` frees 4.6 GB by hand).
- Three Ollama models are pinned with `keep_alive: -1` (26b chat + embeddinggemma + `qwen3-vl:4b-instruct` for precise pointing): Ollama's limit here is three loaded, so adding a fourth makes them evict each other.

What Will should check on first Cmd+R: starter PROFILE.md appears (open folder button); status row goes pulling → ready; "remember that …" lands in the profile; "forget …" speaks "forgot: …"; a question about yesterday's work gets a retrieved note line (console logs `🧠 Memory: N retrieved note entries`); toggle off → no `🧠 Memory block` log line; quit Ollama with a cloud chat provider → status row says unreachable and replies still work.

### Commits

On `feature/direct-providers` (upstream `a80fa80` + direct providers, Keychain, settings panel, Ollama fixes — see git log).

On `feature/kokoro-tts`:

| Commit | What |
|---|---|
| `50a43ad` | `tools/logic-tests/` SwiftPM harness: pure-logic files symlinked in, `swift test` from the terminal |
| `d740540` | `SentenceSplitter` (+12 tests) |
| `15eaac0` | `KokoroVoiceCatalog` (+5 tests) |
| `0b53651` | `KokoroOperatingSystemSupport` (+4 tests) |
| `24a06ba` | `TextToSpeechProviderKind.kokoro` (new default), `kokoroVoice` setting, voice picker, settings observation |
| `fbd35a4` | FluidAudio 0.17.7 package dependency (pbxproj + Package.resolved) |
| `4f7ef0e`, `4627bc4` | `SentenceAudioQueuePlayer` (+4 tests) and a Swift 6 capture fix |
| `22198c3` | `KokoroVoiceEngine` + `tools/typecheck.sh` |
| `88fdcdd` | `KokoroTTSClient` + factory case with warm-up |
| `5a32ced` | Model status row with Retry in AI Settings |
| `6115278` | Throwaway warm-up synthesis after load (first real synthesis was ~9 s otherwise) |
| `e89e1b8` | Player test suite on the main actor (Xcode test target has no main-actor default); harness test target now mirrors that |
| fix pass | `KokoroModelLoadCoordinator` (single in-flight load, retry on a new voice), `KokoroSentenceSynthesizing` protocol, `TTSClientFactory.swift` split out, cancelled-reply `isPlaying` fix; +10 tests (36 total) |

Review findings deferred as minor (see the plan's ledger in git history of this file's commit): the `.loading` status copy says "downloading… ~300 MB" even on warm loads; an unknown stored voice code shows a blank picker; no `AVAudioEngineConfigurationChange` handling in the queue player; no sample-rate guard before `scheduleBuffer`.

### Settings model

All in the panel's **AI Settings**, persisted in UserDefaults via `AppSettings`; keys in Keychain via `SecretsStore`:
- Chat: `ChatProviderKind` = ollama (default) | openRouter | anthropicDirect | custom; base URL + model text fields
- STT: `SpeechToTextProviderKind` = apple (default) | assemblyAI | openAI
- TTS: `TextToSpeechProviderKind` = kokoro (default) | apple | elevenLabs; Kokoro voice picker (28 voices, default `bm_george`) with model-status row; Apple voice picker; ElevenLabs voice ID

Kokoro models live in `~/Library/Application Support/Lumen/Models` (~380 MB after first run); FluidAudio keeps its English pronunciation assets (~40 MB) in `~/.cache/fluidaudio/Models/kokoro` regardless of the directory setting. Delete both to re-test the cold path.

## Conventions that bite

- **Never run `xcodebuild` from the terminal** — resets TCC grants. Will builds with Cmd+R. Typecheck with `tools/typecheck.sh` (handles the FluidAudio module once Xcode has built once).
- **Terminal tests:** `cd tools/logic-tests && swift test`. After adding a new symlink, delete `tools/logic-tests/.build` once (SwiftPM caches the source list).
- **Timing-sensitive test:** `KokoroTTSClientTests.aCancelledReplyDoesNotMarkTheNextReplyAsFinished` waits fixed 60 ms sleeps for real `AVAudioEngine` playback to finish; it passed twice on 2026-10-17 and failed consistently on 2026-10-18 (same on the base branch, load average ≈5). Not a memory-branch regression. Fix candidate: poll `isPlaying` with a deadline instead of fixed sleeps, as `MemoryModelProvisionerTests.waitUntil` does.
- **Reading Xcode output without copy-paste:** build logs are `~/Library/Developer/Xcode/DerivedData/leanring-buddy-*/Logs/Build/*.xcactivitylog` (gzip); the console of a *finished* run is in `Logs/Launch/Run-*.xcresult` via `xcrun xcresulttool get log --path <xcresult> --type console`. Xcode's MCP server (`xcrun mcpbridge`) is registered for Claude Code at user scope; Will still needs to enable it in Xcode → Settings → Intelligence, then it can build/test/read issues through Xcode.
- **Stray instances:** the app registers itself as a login item (`registerAsLoginItemIfNeeded`), and an instance from an earlier Xcode run kept running for hours alongside the new one — both answer the hotkey, so you hear two replies (the old one spoke an "i couldn't reach the model" error). Check `pgrep -fl Lumen.app` when behaviour looks doubled.
- Xcode project uses **synchronized folders**: new `.swift` files in `leanring-buddy/` are picked up automatically; no pbxproj edits.
- SourceKit per-file "cannot find type" diagnostics are noise (no module context). Trust the typecheck script.
- Don't rename the `leanring-buddy` dir/scheme. Don't fix upstream's known Swift-6 warnings.
- Commit messages: conventional, no AI attribution lines (Will's global rule).
- Default actor isolation is MainActor: unannotated types are main-actor. Pure helpers that tests call are `nonisolated enum`s.
- macOS 26.4–26.5: Kokoro is disabled by `KokoroOperatingSystemSupport` (Apple BNNS crash bug per FluidAudio; fixed in 26.6). Will is on 26.3.

## NEXT FEATURE: wake word

Per the roadmap agreed in the brainstorm: memory (done, above), then skins (approved), a new Lumen onboarding, Echo-style activity features (timeline, focus sessions + distraction guard, focus stats, contextual hints), then **wake word** (Porcupine or openWakeWord; FluidAudio has VAD and Parakeet STT), then proactive triggers (narrow, opt-in — HeyClicky removed theirs for annoyance/privacy), then background tasks (Cua/Peekaboo). Run the superpowers brainstorming skill (architectural path) first; Will likes being grilled with AskUserQuestion.

Also parked: a Jev/OpenJev-style "chooser" model (one-pass option scoring) for accessibility-tree pointing and local/cloud routing; `qwen3-vl` Ollama tag for better pointing; Chatterbox voice cloning and Parakeet STT via the same FluidAudio package.

## Research artifacts from the earlier session (not persisted elsewhere)

Three deep-research reports on HeyClicky (what it does, weekly ship log v1.0→v1.0.53, open-source architecture incl. exact system prompt and pointing math) were produced as workflow outputs under that session's `tasks/` dir. Key takeaways already applied: pointing tag grammar, 1280-px JPEG capture, HeyClicky's PROFILE.md/VOLATILE.md memory design (for the memory feature), and that HeyClicky removed proactive agents for annoyance/privacy reasons (v1.0.46) — design proactive narrowly.
