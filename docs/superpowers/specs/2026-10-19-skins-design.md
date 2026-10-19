# Lumen skins and precise pointing — design

Date: 2026-10-19. Branch: `feature/lumen-rename` (the rename is already committed there; skins build on it).
Visual reference: the "Lumen look board" artifact (https://claude.ai/artifact/15FWvd8tkiGFErGtzUHHrn), cards A Ember, B Instrument, C Marginalia.

## Why

Lumen was renamed from Clicky and should no longer look like it: the blue triangle cursor, the triangle menu bar icon, the blue-on-black panel and the triangle app icon are all upstream's identity. Will wants Lumen to be the final layer of his stack, watching what he does and helping with very little inference, and he wants its look to be his own. He also liked the idea that the look is switchable.

Pointing matters more than decoration. Lumen will later click things for Will and run background tasks, so the way it marks a target must show exactly which element it means. Will rejected the glow-style pointing from the Ember card for that reason ("didn't make a lot of sense", "would be hard with this sort of glow") and asked for the Instrument brackets to be "more accurate".

## What Will decided

- **Three switchable skins:** Ember, Instrument, Marginalia. Aperture is dropped.
- **Default skin:** Marginalia with Ember's motion. Ink-dot companion; while listening an ink aura ripples out; while thinking small ink dots orbit it; while speaking it pulses; it points by drawing a loose ink circle around the target and swiping a translucent yellow highlighter across it. The panel uses Ember's glass card shape in Marginalia's paper and ink colours.
- **Pointing must be precise** in every skin and must hug the real element, not float near a point.
- **Instrument keeps the x/y coordinate readout** on its brackets.

## Goals

1. A skin is chosen in the panel (AI Settings → Appearance) and applies immediately, without restarting.
2. Each skin defines: the on-screen companion in each state (idle, listening, thinking, speaking, flying, pointing), the pointing mark drawn at the target, the speech/pointing bubble, the menu bar icon, and the control panel's colours, type and container.
3. Pointing marks are drawn around the target element's real bounds whenever macOS Accessibility can provide them, and fall back gracefully to a small mark around the point when it cannot.
4. No upstream (Clicky/Farza) identity is visible anywhere in the running app.
5. Lumen gets one new app icon of its own.

## Non-goals

- Aperture, user-made skins, per-skin app icons.
- Speaking animation driven by the TTS audio level (v1 uses a time-based pulse; see "Left to the builder").
- Clicking or acting on the target element. This design only finds and marks it, but it should produce the element rect in a form a future click action can reuse.
- Echo-style activity features, wake word, background tasks (they are next on the roadmap, separately).
- Removing dead code that does not affect the look (`ElementLocationDetector`, `CompanionResponseOverlay`) beyond what the work touches.

## Anti-goals (it fails even if it technically works)

- A pointing mark that leaves the user unsure which control is meant.
- Anything that needs a new permission, a network call, or a cloud model.
- A skin switch that needs a restart, resets settings, or rebuilds the chat/TTS clients.
- The companion stuttering or the overlay dropping frames while pointing (Accessibility calls must not run on the main actor's hot path).

## Constraints

- Never run `xcodebuild` (it resets TCC permissions). Verify with `tools/typecheck.sh` and `cd tools/logic-tests && swift test`; Will runs Cmd+R and Cmd+U.
- Deployment target is macOS 14.2; Will runs macOS 26.3. Default actor isolation is MainActor; pure helpers that tests call are `nonisolated`.
- Naming: clarity over concision (see `AGENTS.md`). Do not rename the `leanring-buddy` directory, scheme or module. Do not fix the known Swift 6 warnings.
- Pure logic lives in Foundation-only files symlinked into the `LumenLogic` harness with Swift Testing suites in `leanring-buddyTests/`.
- Local-first: no new network dependencies; no bundled third-party fonts (licensing and size) unless unavoidable.

## How it fits the current code (facts from the code map)

- The overlay is `BlueCursorView` in `OverlayWindow.swift`, built per screen in `OverlayWindowManager.showOverlay` (the single construction point). The companion is three sibling views cross-faded by `companionManager.voiceState`: a 16 pt `Triangle` (idle and responding), `BlueCursorWaveformView` (listening, driven by `currentAudioPowerLevel`), `BlueCursorSpinnerView` (processing). Responding has no visual of its own. All colour comes from `DS.Colors.overlayCursorBlue`, used 11 times.
- Flight is a Timer-stepped quadratic bezier (`animateBezierFlightArc`) with tangent rotation (+90°, assumes a tip-up glyph) and a scale pulse. At the target, nothing is drawn: the triangle stops at the point plus (+8, +12) and a typed bubble shows a random phrase for 3 s, then it flies back.
- `[POINT:x,y:label:screenN]` is parsed in `CompanionManager.parsePointingCoordinates`; x,y are on a ≤1280 px screenshot, scaled to display points, flipped to AppKit global and published as `detectedElementScreenLocation` + `detectedElementDisplayFrame`. The label is parsed but not published.
- The pipeline forces `voiceState = .idle` before pointing only so the triangle shows during flight.
- Accessibility permission is already required and granted; the app is not sandboxed. No code queries the element at a point today.
- `DS` is all `static let`; `CompanionPanelView` uses `DS.Colors` 93 times, has 70 hard-coded `.system(size:)` fonts and 9 literal colours. The panel container is a SwiftUI `RoundedRectangle` filled with opaque `#101211`; the `NSPanel` itself is clear and borderless, 320 pt wide.
- The menu bar icon is a hand-drawn triangle template image set once in `MenuBarPanelManager.createStatusItem()`.
- Settings follow the `AppSettings` pattern (String-raw enum, `settings.*` key, `@Published` with `didSet`). `bindSettingsObservation` merges seven publishers behind a hand-counted `.dropFirst(7)`; a skin setting must not join that merge.

## The design

### 1. Skin selection

- New `LumenSkin` enum (`ember`, `instrument`, `marginalia`) with `displayName`, persisted as `settings.skin` in `AppSettings`, default `.marginalia`. Observed on its own, never through the client-rebuild merge.
- Panel: a new "APPEARANCE" subsection in AI Settings with a skin picker (the existing `settingsPickerRow` style, plus its `displayName(for:)` chain).
- Changing the skin updates the overlay, panel and menu bar icon live.

### 2. Skin definition

One place per skin declares everything visual (builder chooses the exact shape; a protocol or a struct of tokens plus view builders are both fine):

| | Ember | Instrument | Marginalia (default) |
|---|---|---|---|
| Companion | warm orb (cream → amber → coral radial), soft glow | thin ring with tick marks, signal-orange core | ink dot (#1b1535 on light, paper-coloured on dark screens: see below) |
| Listening | aura ripples, mic-level scaled | ticks step/pulse with mic level | ink aura ripples, mic-level scaled |
| Thinking | 2–3 satellites orbit | orange sweep arc rotates | small ink dots orbit (Ember's motion in ink) |
| Speaking | orb pulses | core pulses | dot pulses |
| Flying | orb with short trail, no rotation | ring, no rotation | dot, no rotation |
| Pointing mark | warm rounded outline hugging the element bounds + faint inner glow (the glow never replaces the outline) | four orange corner brackets snapped to the bounds + readout "x 812 y 340" (element top-left in screen points) | loose hand-drawn ink circle around the bounds + 50 % yellow highlighter across the element |
| Bubble | rounded glass pill, rounded system font | square-cornered, monospaced | paper card, serif |
| Panel | dark plum glass card, rounded system font, coral accent | light instrument grey, 1 pt ink border, hard offset shadow, monospaced, orange accent | glass card in paper and ink, serif system font (New York), ink accent with yellow highlight |
| Menu bar icon (template) | filled circle with a thin outer ring | ring with ticks and a dot | ink dot with a short pen stroke |

Colours, sizes and timings come from the look board cards; the board's CSS is the reference for each value.

Readability on any wallpaper: an ink dot vanishes on dark windows. Each skin's companion and marks carry a contrasting halo (Marginalia: thin paper-coloured outline around ink strokes; Instrument: a dark 1 pt outline around orange; Ember already glows).

Fonts: system designs only (`.serif` = New York, `.monospaced` = SF Mono, `.rounded` = SF Pro Rounded). No bundled fonts.

Liquid glass: on macOS 26 use the system glass effect for the glass-card skins; on 14.2–15 fall back to `.ultraThinMaterial` with the skin tint.

### 3. Overlay changes

- Replace the triangle, waveform and spinner with one skin-provided companion view that receives: voice state, mic level, navigation mode (following / flying / pointing), flight progress, and whether TTS is speaking.
- Speaking gets its own state for the companion: while `voiceState == .responding` (and during pointing, while TTS is playing) the companion shows its speaking animation. The pipeline's "force `.idle` before pointing" hack is replaced by the companion showing correctly in flight regardless of voice state.
- Flight keeps the existing bezier path and timing; skins decide whether the glyph rotates (none of the three do) and whether it scales.
- At the target, the companion parks just outside the element's bounds (bottom-left corner by default, flipped to stay on screen) instead of at point + (8, 12), and the skin's pointing mark is drawn around the bounds. The mark animates in (Marginalia draws its circle then swipes the highlighter; Instrument snaps the brackets; Ember fades the outline in), holds while the bubble is shown (today 3 s), then fades before the fly-back.
- Bubble text: the element label from the `[POINT]` tag when there is one (for example "Export"), otherwise today's short phrases. The label becomes published alongside the location.
- The three duplicated bubble styles (welcome, onboarding prompt, pointing) become one skinned bubble.

### 4. Precise pointing (element bounds)

A new resolver turns the global point into an element rect:

1. Convert the AppKit global point to Accessibility space (top-left origin of the primary display: `y_ax = primaryScreenHeight − y`).
2. `AXUIElementCopyElementAtPosition` on the system-wide element with a short messaging timeout (≈150 ms), off the main actor.
3. Read position and size; if the hit is Lumen's own process, a whole window, scroll area, web area, split group or similarly large container (or covers more than about a quarter of the display), walk no further and treat it as a miss. If the hit is tiny (e.g. a text run inside a button), walk up parents until a reasonably sized control is found.
4. Clip the rect to the display frame.
5. Convert back to AppKit global and publish it as the target rect next to the existing location. Optionally compare the element's title/description with the tag's label to pick between candidates.
6. On a miss, publish a fallback rect: a small box (about 44 × 28 pt) centred on the point, so every skin still draws its mark in the right place.

The rect is also the hand-off point for future clicking.

The selection rules (role filter, size thresholds, walk-up, clipping, coordinate flips, fallback box) are pure functions with harness tests; the AX calls themselves are a thin wrapper.

### 5. Removing upstream identity

Visible in the running app today and replaced or removed:
- Blue triangle companion, triangle menu bar icon, blue bubble fills (replaced by skins).
- App icon: the blue triangle (replaced by one new Lumen icon, see 6).
- Onboarding: the welcome types "hey! i'm lumen" in a blue bubble (kept, skinned). The onboarding video streamed from upstream's Mux account (Farza's video), its background music `ff.mp3`, the email capture ("Drop your email…", sends nowhere), the "Got feedback? DM me" button linking to Farza's X account, and "Watch Onboarding Again": **see open questions**.
- System prompts that describe "a small blue triangle cursor" / "a small blue cursor buddy" become look-neutral ("you can point at things on the user's screen").
- Dictation key terms "makesomething", "Learning Buddy", "Codex" (upstream leftovers) are removed or replaced with "Lumen".
- Unused upstream assets (steve.jpg, Codex/makesomething screenshots, discord/google logos, enter.mp3, eshop.mp3) and the makesomething `appcast.xml` are deleted.
- The upstream copyright line in `LICENSE` and the credit in `README.md` stay (MIT requires the notice).

### 6. App icon

One icon for Lumen, in the default look: an ink dot with its listening aura on a paper-lilac squircle, rendered at all `AppIcon.appiconset` sizes by a script so it can be regenerated. Will reviews it on a small look board before it replaces the triangle.

## Verification

- Harness tests for: skin setting default and persistence key, skin catalog completeness (every skin defines every element), element-rect selection rules and coordinate conversions (multi-display, displays left of/above primary), fallback box, bubble text choice (label vs phrase).
- `tools/typecheck.sh` → 0 errors.
- Will, Cmd+R: switch skins live; ask "where's the export button" in a native app (Finder, Xcode, Safari) and see the mark hug the button in each skin; try an Electron app and a canvas app to see the fallback mark; check the companion is visible on light and dark windows; check the menu bar icon follows the skin; check nothing says Clicky or Farza.

## Left to the builder

- Exact Swift shape of a skin (protocol vs token struct) and how the panel reads skin tokens (environment value is the expected route since `DS` is static).
- Whether the speaking pulse is purely time-based or nudged by TTS sentence boundaries (no audio-level plumbing in v1).
- Exact timings and sizes, starting from the look board.
- Whether to add a "Preview" button next to the skin picker that plays the companion states at the cursor.
- Probing a few nearby points when the first hit misses.

## Open questions (Will's)

1. Upstream onboarding: delete the Farza video, music, email capture, DM button and "Watch Onboarding Again" outright and keep a short skinned welcome, or replace them with a new Lumen onboarding?
