# Clicky (Will's fork)

A fork of [farzaa/clicky](https://github.com/farzaa/clicky) — the MIT-licensed April 2026 prototype of what became [HeyClicky](https://www.heyclicky.com/). Hold a hotkey, ask a question out loud, and an AI buddy that can see your screen answers by voice and flies a little cursor to the button it's talking about.

![Clicky — an ai buddy that lives on your mac](clicky-demo.gif)

## What's different in this fork

Upstream routed every API call through a Cloudflare Worker that held the keys. This fork:

- **Calls providers directly.** No Worker, no Cloudflare account. API keys go in the in-app **AI Settings** panel and are stored in the macOS Keychain.
- **Is provider-agnostic.** The chat model can be any OpenAI-compatible endpoint (OpenRouter, Ollama, LM Studio, vLLM…) or Anthropic directly. One OpenRouter key reaches Haiku 5.5, DeepSeek, GLM, Qwen-VL, Gemini, etc.
- **Runs fully offline by default.** Fresh install = Apple Speech (STT) → Ollama on localhost (vision LLM) → Apple voices (TTS). Zero accounts needed. AssemblyAI and ElevenLabs are opt-in toggles.
- **Phones home to nobody.** Upstream's PostHog telemetry, FormSpark email capture and Sparkle update feed are removed.

Everything else — the overlay, pointing animation, screen capture, push-to-talk — is Farza's code.

## Setup

### Prerequisites

- macOS 14.2+ (ScreenCaptureKit). Developed on macOS 26 / Xcode 26.
- For the offline default: [Ollama](https://ollama.com) with a vision-capable model, e.g. `ollama pull gemma4:26b` (18 GB, needs ~24 GB RAM) or a smaller `qwen3-vl` tag.
- Optional: an [OpenRouter](https://openrouter.ai/keys) key for cloud models.

### Build

```bash
open leanring-buddy.xcodeproj
```

In Xcode: select the `leanring-buddy` scheme (the typo is intentional, long story), set your signing team under Signing & Capabilities, **Cmd + R**.

Do not build with `xcodebuild` from the terminal — it invalidates the TCC permission grants and you'll have to re-grant everything.

### First run

1. The app appears in the menu bar (no dock icon). Click it and grant the four permissions: Microphone, Accessibility, Screen Recording, Screen Content.
2. Expand **AI Settings** in the panel:
   - **Provider** — `Ollama (local)` with model `gemma4:26b` is the default. Switch to `OpenRouter`, paste a key, click Save; the model defaults to `anthropic/claude-haiku-5.5`.
   - **Speech to text** — Apple (local) by default. AssemblyAI / OpenAI need a key.
   - **Text to speech** — Apple (local) by default. For a less robotic voice, download an *Enhanced* or *Premium* voice in System Settings → Accessibility → Spoken Content → System Voice → Manage Voices, then pick it in the Voice menu. ElevenLabs needs a key.
3. Hold **Control + Option**, ask something about your screen, release.

Keys are read from the Keychain (service `com.willhammond.clicky`). `.env.example` documents them but is never read by the app.

## Architecture

Menu bar app (`LSUIElement`) with two `NSPanel`s — the control panel and a full-screen transparent cursor overlay. Push-to-talk streams mic audio to the configured transcription provider; the transcript plus a JPEG of every screen goes to the configured chat client; the reply is parsed for a trailing `[POINT:x,y:label:screenN]` tag, spoken via the configured TTS client, and the cursor flies to the coordinate.

```
leanring-buddy/
  CompanionManager.swift            # state machine: push-to-talk → screenshot → chat → TTS → pointing
  AppSettings.swift                 # provider / model / voice choices (UserDefaults)
  SecretsStore.swift                # API keys (Keychain)
  ChatClient.swift                  # protocol + factory
  OpenAICompatibleChatClient.swift  # OpenRouter / Ollama / any /chat/completions server
  ClaudeAPI.swift                   # Anthropic Messages API (direct)
  TTSClient.swift                   # protocol + factory
  AppleSpeechTTSClient.swift        # AVSpeechSynthesizer (default)
  ElevenLabsTTSClient.swift         # ElevenLabs (direct)
  BuddyTranscriptionProvider.swift  # STT protocol + factory (Apple / AssemblyAI / OpenAI)
  CompanionPanelView.swift          # menu bar panel incl. AI Settings
  OverlayWindow.swift               # cursor overlay + pointing animation
```

See `AGENTS.md` for the full file map and conventions.

## License

MIT — see `LICENSE`. Original work © 2026 Farza.
