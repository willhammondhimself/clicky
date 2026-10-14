# HANDOFF — read this first after a context reset

Last updated: 2026-10-15. Branch `feature/kokoro-tts` (off `feature/direct-providers`), pushed to `willhammondhimself/clicky`.

## Where we are

The fork builds and the core loop works end to end, fully offline, on Will's M4 Pro (48 GB):
hold Ctrl+Option → Apple Speech (on-device) → screenshot → `gemma4:26b` on Ollama → **Kokoro** British male voice (on-device) + cursor flies to the right element.

Will verified in the real app on 2026-10-15: cold first run (model downloaded at launch, question asked before it was ready → spinner → Kokoro spoke), warm relaunch, faster first reply after the warm-up change, interrupt mid-sentence, multi-sentence replies with no gaps, no error voice. Not yet tried by Will: switching Kokoro voices, switching back to Apple/ElevenLabs, offline with cached models, Cmd+U in Xcode.

Design + plan for the Kokoro work: `docs/superpowers/specs/2026-10-14-kokoro-tts-design.md`, `docs/superpowers/plans/2026-10-14-kokoro-tts.md`.

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

### Settings model

All in the panel's **AI Settings**, persisted in UserDefaults via `AppSettings`; keys in Keychain via `SecretsStore`:
- Chat: `ChatProviderKind` = ollama (default) | openRouter | anthropicDirect | custom; base URL + model text fields
- STT: `SpeechToTextProviderKind` = apple (default) | assemblyAI | openAI
- TTS: `TextToSpeechProviderKind` = kokoro (default) | apple | elevenLabs; Kokoro voice picker (28 voices, default `bm_george`) with model-status row; Apple voice picker; ElevenLabs voice ID

Kokoro models live in `~/Library/Application Support/Clicky/Models` (~380 MB after first run). Delete that folder to re-test the cold path.

## Conventions that bite

- **Never run `xcodebuild` from the terminal** — resets TCC grants. Will builds with Cmd+R. Typecheck with `tools/typecheck.sh` (handles the FluidAudio module once Xcode has built once).
- **Terminal tests:** `cd tools/logic-tests && swift test`. After adding a new symlink, delete `tools/logic-tests/.build` once (SwiftPM caches the source list).
- **Reading Xcode output without copy-paste:** build logs are `~/Library/Developer/Xcode/DerivedData/leanring-buddy-*/Logs/Build/*.xcactivitylog` (gzip); the console of a *finished* run is in `Logs/Launch/Run-*.xcresult` via `xcrun xcresulttool get log --path <xcresult> --type console`. Xcode's MCP server (`xcrun mcpbridge`) is registered for Claude Code at user scope; Will still needs to enable it in Xcode → Settings → Intelligence, then it can build/test/read issues through Xcode.
- **Stray instances:** the app registers itself as a login item (`registerAsLoginItemIfNeeded`), and an instance from an earlier Xcode run kept running for hours alongside the new one — both answer the hotkey, so you hear two replies (the old one spoke an "i couldn't reach the model" error). Check `pgrep -fl Clicky.app` when behaviour looks doubled.
- Xcode project uses **synchronized folders**: new `.swift` files in `leanring-buddy/` are picked up automatically; no pbxproj edits.
- SourceKit per-file "cannot find type" diagnostics are noise (no module context). Trust the typecheck script.
- Don't rename the `leanring-buddy` dir/scheme. Don't fix upstream's known Swift-6 warnings.
- Commit messages: conventional, no AI attribution lines (Will's global rule).
- Default actor isolation is MainActor: unannotated types are main-actor. Pure helpers that tests call are `nonisolated enum`s.
- macOS 26.4–26.5: Kokoro is disabled by `KokoroOperatingSystemSupport` (Apple BNNS crash bug per FluidAudio; fixed in 26.6). Will is on 26.3.

## NEXT FEATURE: memory

Per the roadmap agreed in the brainstorm: **memory** (profile + daily notes + a "remember this" tool, modelled on HeyClicky's PROFILE.md/VOLATILE.md injected into the system prompt), then wake word (Porcupine or openWakeWord; FluidAudio has VAD and Parakeet STT), then proactive triggers (narrow, opt-in — HeyClicky removed theirs for annoyance/privacy), then background tasks (Cua/Peekaboo). Run the superpowers brainstorming skill (architectural path) first.

Also parked: a Jev/OpenJev-style "chooser" model (one-pass option scoring) for accessibility-tree pointing and local/cloud routing; `qwen3-vl` Ollama tag for better pointing; Chatterbox voice cloning and Parakeet STT via the same FluidAudio package.

## Research artifacts from the earlier session (not persisted elsewhere)

Three deep-research reports on HeyClicky (what it does, weekly ship log v1.0→v1.0.53, open-source architecture incl. exact system prompt and pointing math) were produced as workflow outputs under that session's `tasks/` dir. Key takeaways already applied: pointing tag grammar, 1280-px JPEG capture, HeyClicky's PROFILE.md/VOLATILE.md memory design (for the memory feature), and that HeyClicky removed proactive agents for annoyance/privacy reasons (v1.0.46) — design proactive narrowly.
