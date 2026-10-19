# Kokoro Local TTS Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a "Kokoro (local)" text-to-speech provider that synthesizes replies on-device through the FluidAudio Swift package, plays them gaplessly sentence by sentence, and becomes the default voice.

**Architecture:** A main-actor singleton `KokoroVoiceEngine` owns the one Kokoro model manager and its download/compile state. A `SentenceAudioQueuePlayer` wraps `AVAudioEngine` for gapless playback of 24 kHz buffers. A thin `KokoroTTSClient` conforms to the existing `TTSClient` protocol, splits replies with the pure `SentenceSplitter`, and falls back to the Apple voice when the model cannot load. Settings, the factory, and the panel gain the new provider and a voice picker with a model-status row.

**Tech Stack:** Swift 5 language mode with `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`, SwiftUI/AppKit, AVFoundation, Combine, FluidAudio 0.17.7 (CoreML/ANE Kokoro-82M), Swift Testing. A small SwiftPM harness under `tools/logic-tests/` runs the pure-logic tests from the terminal.

**Spec:** `docs/superpowers/specs/2026-10-14-kokoro-tts-design.md`

## Global Constraints

- **Never run `xcodebuild` from the terminal.** It invalidates TCC permissions. Will builds with Cmd+R and runs the Xcode test target with Cmd+U. Terminal verification is `swift test` inside `tools/logic-tests/` plus the `swiftc -typecheck` command below.
- Typecheck of app sources (works until a file imports FluidAudio):
  `cd ~/code/lumen && xcrun swiftc -typecheck -sdk "$(xcrun --show-sdk-path --sdk macosx)" -target arm64-apple-macos14.2 -parse-as-library -default-isolation MainActor leanring-buddy/*.swift`
  Expected: zero errors. One pre-existing warning "no async operations occur within await" in `OpenAICompatibleChatClient.swift` is known and ignored.
- Every unannotated type is main-actor isolated. Pure helpers that tests or non-main code call are declared `nonisolated enum`.
- Naming: clarity over concision, no single-letter names, no abbreviations in parameter names (repo `AGENTS.md`).
- Commit messages: conventional (`feat:`, `test:`, `docs:`, `build:`), imperative, **no AI attribution or Co-Authored-By lines**.
- Do not rename the `leanring-buddy` directory/scheme. Do not touch upstream's known Swift 6 warnings.
- Package pin: `https://github.com/FluidInference/FluidAudio` at **exactly 0.17.7**, product `FluidAudio`, linked to the app target only.
- Deployment target stays `14.2`. The v3 runtime is selected at runtime with `#available(macOS 15, *)`.
- Default Kokoro voice: `bm_george`. Fresh-install TTS default: `.kokoro`. Stored settings are always respected.
- Model directory: `~/Library/Application Support/Lumen/Models`.
- macOS 26.4 and 26.5: Kokoro is disabled (`unavailable`) and the Apple voice is used.
- Copy for the user-facing strings is lowercase-casual like the rest of the panel where noted; status strings are given verbatim in the tasks.

## Review Focus

1. **Replies with decimal numbers or ellipses** ("costs 3.5 percent… wait, really?") must not be cut mid-number and must treat "…"/"..." as a single boundary. Pinned in Task 2 tests `doesNotSplitDecimalNumbers` and `treatsEllipsisAsOneBoundary`.
2. **A long reply with no punctuation at all** (local models sometimes stream one run-on line) must become one chunk, not be dropped. Pinned in Task 2 test `keepsUnpunctuatedRunOnAsSingleChunk`.
3. **Hotkey pressed during the first-run download** must not result in speech starting after the user has moved on. `KokoroTTSClient.speakText` checks `Task.checkCancellation()` after the load await (Task 9) and the manual checklist exercises it (Task 11, step 5).
4. **`stop()` while buffers are still scheduled** must not leave `isPlaying` stuck true or go negative when late completion callbacks arrive. Pinned in Task 7 test `stopDiscardsPendingCompletions`.
5. **A voice code in UserDefaults that the catalog does not know** (hand-edited or from a future version) must still render a label and must fall back to the Apple voice rather than crash. Pinned in Task 3 test `labelFallsBackToRawCodeForUnknownVoice` and by the `failed` path in Task 9.

---

## File map

| Path | Responsibility |
|---|---|
| `tools/logic-tests/Package.swift` (create) | Terminal test harness: SwiftPM package whose sources and tests are symlinks into the app and test folders. |
| `tools/logic-tests/Sources/LumenLogic/*.swift` (symlinks) | `SentenceSplitter.swift`, `KokoroVoiceCatalog.swift`, `KokoroOperatingSystemSupport.swift`, `SentenceAudioQueuePlayer.swift`. |
| `tools/logic-tests/Tests/LumenLogicTests/*.swift` (symlinks) | The matching test files from `leanring-buddyTests/`. |
| `leanring-buddy/SentenceSplitter.swift` (create) | Pure: reply text → sentence chunks sized for the Kokoro fast path. |
| `leanring-buddy/KokoroVoiceCatalog.swift` (create) | Pure: the 28 American/British voice codes, labels, ordering, default. |
| `leanring-buddy/KokoroOperatingSystemSupport.swift` (create) | Pure: which macOS builds block Kokoro; whether the v3 runtime is available. |
| `leanring-buddy/SentenceAudioQueuePlayer.swift` (create) | Gapless playback of PCM buffers via `AVAudioEngine` + `AVAudioPlayerNode`; `isPlaying`, `stop()`. |
| `leanring-buddy/KokoroVoiceEngine.swift` (create) | Singleton owning `KokoroAneManager`, load state, and sentence → buffer synthesis. Imports FluidAudio. |
| `leanring-buddy/KokoroTTSClient.swift` (create) | `TTSClient` conformance: split, synthesize, enqueue, Apple fallback. |
| `leanring-buddy/AppSettings.swift` (modify) | `TextToSpeechProviderKind.kokoro`, `kokoroVoice` setting, new default. |
| `leanring-buddy/TTSClient.swift` (modify) | Factory case for Kokoro plus warm-up. |
| `leanring-buddy/CompanionManager.swift` (modify, lines 95–116) | Observe `kokoroVoice` so clients rebuild when the voice changes. |
| `leanring-buddy/CompanionPanelView.swift` (modify, lines 633–647 and the helpers after 740) | Kokoro voice picker, model status row with Retry, footer copy. |
| `leanring-buddy.xcodeproj/project.pbxproj` (modify) | FluidAudio package reference and product link. |
| `leanring-buddyTests/SentenceSplitterTests.swift`, `KokoroVoiceCatalogTests.swift`, `KokoroOperatingSystemSupportTests.swift`, `SentenceAudioQueuePlayerTests.swift` (create) | Swift Testing suites; run by Xcode (Cmd+U) and by the harness. |
| `AGENTS.md`, `README.md`, `docs/HANDOFF.md`, `.gitignore`, spec (modify) | Documentation and ignore rule for the harness build dir. |

---

### Task 1: Terminal test harness

**Files:**
- Create: `tools/logic-tests/Package.swift`
- Create: `tools/logic-tests/Sources/LumenLogic/.gitkeep` (placeholder removed in Task 2)
- Create: `tools/logic-tests/Tests/LumenLogicTests/HarnessSmokeTests.swift`
- Modify: `.gitignore`

**Interfaces:**
- Produces: a package named `LumenLogic` whose target settings mirror the app (`.swiftLanguageMode(.v5)`, `.defaultIsolation(MainActor.self)`). Later tasks drop symlinks into `Sources/LumenLogic/` and `Tests/LumenLogicTests/`.
- Test files in `leanring-buddyTests/` import the module conditionally so the same file compiles in Xcode and in the harness:
  ```swift
  #if canImport(leanring_buddy)
  @testable import leanring_buddy
  #else
  @testable import LumenLogic
  #endif
  ```

- [ ] **Step 1: Create the package manifest**

```swift
// swift-tools-version: 6.2
//
// Terminal test harness for Lumen's pure-logic files. The app itself can
// only be built from Xcode (running xcodebuild from the terminal resets the
// app's TCC permissions), so files with no AppKit/FluidAudio dependency are
// symlinked into this package and tested with `swift test`.
//
// Settings mirror the app target: Swift 5 language mode with main-actor
// default isolation, so code that compiles here compiles in the app.

import PackageDescription

let mirroredAppTargetSettings: [SwiftSetting] = [
    .swiftLanguageMode(.v5),
    .defaultIsolation(MainActor.self),
]

let package = Package(
    name: "LumenLogic",
    platforms: [.macOS(.v14)],
    targets: [
        .target(
            name: "LumenLogic",
            swiftSettings: mirroredAppTargetSettings
        ),
        .testTarget(
            name: "LumenLogicTests",
            dependencies: ["LumenLogic"],
            swiftSettings: mirroredAppTargetSettings
        ),
    ]
)
```

Save as `tools/logic-tests/Package.swift`.

- [ ] **Step 2: Add a placeholder source and a smoke test**

`tools/logic-tests/Sources/LumenLogic/HarnessPlaceholder.swift`:
```swift
// Removed once the first real file is symlinked in (Task 2). SwiftPM needs
// at least one source file to build the target.
nonisolated enum HarnessPlaceholder {}
```

`tools/logic-tests/Tests/LumenLogicTests/HarnessSmokeTests.swift`:
```swift
import Testing

struct HarnessSmokeTests {
    @Test func harnessRuns() {
        #expect(1 + 1 == 2)
    }
}
```

- [ ] **Step 3: Run the harness**

Run: `cd ~/code/lumen/tools/logic-tests && swift test 2>&1 | tail -3`
Expected: `✔ Test run with 1 test in 1 suite passed`.

- [ ] **Step 4: Ignore the build directory**

Append to `.gitignore`:
```
tools/logic-tests/.build/
```

- [ ] **Step 5: Commit**

```bash
cd ~/code/lumen
git add tools/logic-tests .gitignore
git commit -m "build: add terminal test harness for pure-logic files"
```

---

### Task 2: SentenceSplitter

**Files:**
- Create: `leanring-buddy/SentenceSplitter.swift`
- Create: `leanring-buddyTests/SentenceSplitterTests.swift`
- Create symlinks: `tools/logic-tests/Sources/LumenLogic/SentenceSplitter.swift` → `../../../../leanring-buddy/SentenceSplitter.swift`; `tools/logic-tests/Tests/LumenLogicTests/SentenceSplitterTests.swift` → `../../../../leanring-buddyTests/SentenceSplitterTests.swift`
- Delete: `tools/logic-tests/Sources/LumenLogic/HarnessPlaceholder.swift`

**Interfaces:**
- Produces: `nonisolated enum SentenceSplitter { static func split(_ text: String) -> [String] }`, constants `minimumChunkCharacterCount = 20`, `maximumChunkCharacterCount = 300`.

- [ ] **Step 1: Write the failing tests**

`leanring-buddyTests/SentenceSplitterTests.swift`:
```swift
import Testing

#if canImport(leanring_buddy)
@testable import leanring_buddy
#else
@testable import LumenLogic
#endif

struct SentenceSplitterTests {

    @Test func splitsOnTerminalPunctuationFollowedBySpace() {
        let chunks = SentenceSplitter.split("the run button is top left. click it to start the build! want me to point again?")
        #expect(chunks == [
            "the run button is top left.",
            "click it to start the build!",
            "want me to point again?",
        ])
    }

    @Test func splitsOnNewlines() {
        let chunks = SentenceSplitter.split("first line of the answer here\nsecond line of the answer here")
        #expect(chunks == ["first line of the answer here", "second line of the answer here"])
    }

    @Test func mergesShortFragmentIntoFollowingChunk() {
        let chunks = SentenceSplitter.split("ok. the save button is in the top right of the window.")
        #expect(chunks == ["ok. the save button is in the top right of the window."])
    }

    @Test func mergesTrailingShortFragmentIntoPreviousChunk() {
        let chunks = SentenceSplitter.split("the save button is in the top right of the window. done.")
        #expect(chunks == ["the save button is in the top right of the window. done."])
    }

    @Test func keepsAbbreviationWithFollowingText() {
        // "e.g." is under 20 characters, so it is merged forward instead of
        // becoming its own 80 ms synthesis call.
        let chunks = SentenceSplitter.split("e.g. the toolbar at the top has the button you need.")
        #expect(chunks == ["e.g. the toolbar at the top has the button you need."])
    }

    @Test func doesNotSplitDecimalNumbers() {
        let chunks = SentenceSplitter.split("the fee is 3.5 percent of the total, which is shown on the right side.")
        #expect(chunks.count == 1)
    }

    @Test func treatsEllipsisAsOneBoundary() {
        let chunks = SentenceSplitter.split("hmm... i think the button you want is the blue one in the corner. click it now to continue.")
        #expect(chunks == [
            "hmm... i think the button you want is the blue one in the corner.",
            "click it now to continue.",
        ])
    }

    @Test func keepsClosingQuoteWithSentence() {
        let chunks = SentenceSplitter.split("it says \"build succeeded.\" now press the run button at the top.")
        #expect(chunks == ["it says \"build succeeded.\"", "now press the run button at the top."])
    }

    @Test func splitsOverlongChunkAtLastCommaBeforeLimit() {
        let longClause = String(repeating: "word ", count: 50).trimmingCharacters(in: .whitespaces) // 249 chars
        let text = "\(longClause), \(longClause)."
        let chunks = SentenceSplitter.split(text)
        #expect(chunks.count == 2)
        #expect(chunks[0].hasSuffix(","))
        #expect(chunks[1].hasSuffix("."))
    }

    @Test func keepsUnpunctuatedRunOnAsSingleChunk() {
        let runOn = String(repeating: "word ", count: 80).trimmingCharacters(in: .whitespaces) // 399 chars, no commas
        let chunks = SentenceSplitter.split(runOn)
        #expect(chunks == [runOn])
    }

    @Test func returnsEmptyForWhitespaceOnlyInput() {
        #expect(SentenceSplitter.split("   \n  ") == [])
        #expect(SentenceSplitter.split("") == [])
    }

    @Test func trimsSurroundingWhitespace() {
        let chunks = SentenceSplitter.split("   the answer is on the left side of the screen.   ")
        #expect(chunks == ["the answer is on the left side of the screen."])
    }
}
```

- [ ] **Step 2: Wire the symlinks and run the tests to verify they fail**

```bash
cd ~/code/lumen/tools/logic-tests
rm Sources/LumenLogic/HarnessPlaceholder.swift
ln -s ../../../../leanring-buddy/SentenceSplitter.swift Sources/LumenLogic/SentenceSplitter.swift
ln -s ../../../../leanring-buddyTests/SentenceSplitterTests.swift Tests/LumenLogicTests/SentenceSplitterTests.swift
swift test 2>&1 | tail -5
```
Expected: build error, "cannot find 'SentenceSplitter' in scope" (the source symlink dangles until Step 3).

- [ ] **Step 3: Implement the splitter**

`leanring-buddy/SentenceSplitter.swift`:
```swift
//
//  SentenceSplitter.swift
//  leanring-buddy
//
//  Splits a spoken reply into sentence-sized chunks for the Kokoro TTS
//  client. Kokoro's fast vocoder path covers up to five seconds of audio per
//  call, and synthesizing sentence by sentence lets playback start after the
//  first ~80 ms instead of after the whole reply. Pure and nonisolated so it
//  can be unit-tested from the terminal harness.
//

import Foundation

nonisolated enum SentenceSplitter {
    /// Pieces shorter than this are merged into a neighbour so "ok." does not
    /// become its own synthesis call.
    static let minimumChunkCharacterCount = 20

    /// Pieces longer than this are split at the last comma before the limit
    /// so each chunk stays within roughly five seconds of speech.
    static let maximumChunkCharacterCount = 300

    static func split(_ text: String) -> [String] {
        let trimmedText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedText.isEmpty else { return [] }

        let sentencePieces = splitOnSentenceBoundaries(trimmedText)
        let mergedPieces = mergeShortPieces(sentencePieces)
        return mergedPieces.flatMap(splitOverlongPiece)
    }

    // MARK: - Sentence boundaries

    private static func isSentenceTerminator(_ character: Character) -> Bool {
        character == "." || character == "?" || character == "!" || character == "…"
    }

    /// Quote and bracket characters that may trail a sentence terminator and
    /// should stay attached to the sentence they close.
    private static func isClosingPunctuation(_ character: Character) -> Bool {
        "\"'”’)]".contains(character)
    }

    /// Splits on newlines, and on runs of `. ? ! …` (plus any closing quotes)
    /// that are followed by whitespace or the end of the text. A terminator
    /// followed directly by a non-space character ("3.5", "e.g.x") does not
    /// split, which keeps decimals intact.
    private static func splitOnSentenceBoundaries(_ text: String) -> [String] {
        let characters = Array(text)
        var pieces: [String] = []
        var currentPiece = ""
        var index = 0

        while index < characters.count {
            let character = characters[index]

            if character == "\n" {
                pieces.append(currentPiece)
                currentPiece = ""
                index += 1
                continue
            }

            currentPiece.append(character)

            guard isSentenceTerminator(character) else {
                index += 1
                continue
            }

            // Absorb the rest of the terminator run ("...", "?!") and any
            // closing quotes so they end up in this piece.
            var lookaheadIndex = index + 1
            while lookaheadIndex < characters.count,
                  isSentenceTerminator(characters[lookaheadIndex]) || isClosingPunctuation(characters[lookaheadIndex]) {
                currentPiece.append(characters[lookaheadIndex])
                lookaheadIndex += 1
            }

            let reachedEndOfText = lookaheadIndex >= characters.count
            let nextCharacterIsWhitespace = !reachedEndOfText && characters[lookaheadIndex].isWhitespace
            if reachedEndOfText || nextCharacterIsWhitespace {
                pieces.append(currentPiece)
                currentPiece = ""
            }
            index = lookaheadIndex
        }

        pieces.append(currentPiece)

        return pieces
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    // MARK: - Short pieces

    /// Carries pieces shorter than `minimumChunkCharacterCount` forward into
    /// the next piece. A short piece at the very end is appended to the
    /// previous one.
    private static func mergeShortPieces(_ pieces: [String]) -> [String] {
        var mergedPieces: [String] = []
        var pendingShortPrefix = ""

        for piece in pieces {
            let candidate = pendingShortPrefix.isEmpty ? piece : pendingShortPrefix + " " + piece
            if candidate.count < minimumChunkCharacterCount {
                pendingShortPrefix = candidate
            } else {
                mergedPieces.append(candidate)
                pendingShortPrefix = ""
            }
        }

        if !pendingShortPrefix.isEmpty {
            if mergedPieces.isEmpty {
                mergedPieces.append(pendingShortPrefix)
            } else {
                mergedPieces[mergedPieces.count - 1] += " " + pendingShortPrefix
            }
        }

        return mergedPieces
    }

    // MARK: - Overlong pieces

    /// Splits at the last comma before `maximumChunkCharacterCount`. A piece
    /// with no comma in range is left whole; the Kokoro library still chunks
    /// anything over 510 phonemes on its own.
    private static func splitOverlongPiece(_ piece: String) -> [String] {
        guard piece.count > maximumChunkCharacterCount else { return [piece] }

        let characters = Array(piece)
        let searchRange = 0..<maximumChunkCharacterCount
        guard let lastCommaIndex = searchRange.reversed().first(where: { characters[$0] == "," }) else {
            return [piece]
        }

        let headPiece = String(characters[...lastCommaIndex]).trimmingCharacters(in: .whitespaces)
        let tailPiece = String(characters[(lastCommaIndex + 1)...]).trimmingCharacters(in: .whitespaces)

        var result = [headPiece]
        if !tailPiece.isEmpty {
            result.append(contentsOf: splitOverlongPiece(tailPiece))
        }
        return result
    }
}
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `cd ~/code/lumen/tools/logic-tests && swift test 2>&1 | tail -4`
Expected: `✔ Test run with 13 tests in 2 suites passed` (12 splitter tests + the smoke test).

- [ ] **Step 5: Typecheck the app sources**

Run the typecheck command from Global Constraints.
Expected: zero errors.

- [ ] **Step 6: Commit**

```bash
cd ~/code/lumen
git add leanring-buddy/SentenceSplitter.swift leanring-buddyTests/SentenceSplitterTests.swift tools/logic-tests
git commit -m "feat: add sentence splitter for chunked text-to-speech"
```

---

### Task 3: KokoroVoiceCatalog

**Files:**
- Create: `leanring-buddy/KokoroVoiceCatalog.swift`
- Create: `leanring-buddyTests/KokoroVoiceCatalogTests.swift`
- Create symlinks into `tools/logic-tests/` for both (same pattern as Task 2).

**Interfaces:**
- Produces:
  ```swift
  nonisolated struct KokoroVoiceOption: Identifiable, Equatable, Sendable { let id: String; let label: String }
  nonisolated enum KokoroVoiceCatalog {
      static let defaultVoice: String            // "bm_george"
      static let voiceCodes: [String]            // 28 American + British codes
      static func availableVoices() -> [KokoroVoiceOption]   // British first, then American, by name
      static func label(forVoiceCode voiceCode: String) -> String
  }
  ```

- [ ] **Step 1: Write the failing tests**

`leanring-buddyTests/KokoroVoiceCatalogTests.swift`:
```swift
import Testing

#if canImport(leanring_buddy)
@testable import leanring_buddy
#else
@testable import LumenLogic
#endif

struct KokoroVoiceCatalogTests {

    @Test func defaultVoiceIsBritishMaleGeorge() {
        #expect(KokoroVoiceCatalog.defaultVoice == "bm_george")
        #expect(KokoroVoiceCatalog.voiceCodes.contains("bm_george"))
    }

    @Test func labelsDescribeAccentAndGender() {
        #expect(KokoroVoiceCatalog.label(forVoiceCode: "bm_george") == "George (British, male)")
        #expect(KokoroVoiceCatalog.label(forVoiceCode: "af_heart") == "Heart (American, female)")
        #expect(KokoroVoiceCatalog.label(forVoiceCode: "bf_isabella") == "Isabella (British, female)")
    }

    @Test func labelFallsBackToRawCodeForUnknownVoice() {
        #expect(KokoroVoiceCatalog.label(forVoiceCode: "zz_mystery") == "zz_mystery")
        #expect(KokoroVoiceCatalog.label(forVoiceCode: "") == "")
    }

    @Test func availableVoicesListsBritishBeforeAmericanAlphabetically() {
        let voices = KokoroVoiceCatalog.availableVoices()
        #expect(voices.count == 28)
        #expect(voices.first?.id == "bf_alice")
        let firstAmericanIndex = voices.firstIndex { $0.id.hasPrefix("a") }
        let lastBritishIndex = voices.lastIndex { $0.id.hasPrefix("b") }
        #expect(firstAmericanIndex != nil && lastBritishIndex != nil)
        #expect(lastBritishIndex! < firstAmericanIndex!)
        #expect(voices.contains(KokoroVoiceOption(id: "bm_george", label: "George (British, male)")))
    }

    @Test func availableVoicesOnlyContainsAmericanAndBritishCodes() {
        let voices = KokoroVoiceCatalog.availableVoices()
        #expect(voices.allSatisfy { $0.id.hasPrefix("af_") || $0.id.hasPrefix("am_") || $0.id.hasPrefix("bf_") || $0.id.hasPrefix("bm_") })
    }
}
```

- [ ] **Step 2: Add the symlinks and run to verify failure**

```bash
cd ~/code/lumen/tools/logic-tests
ln -s ../../../../leanring-buddy/KokoroVoiceCatalog.swift Sources/LumenLogic/KokoroVoiceCatalog.swift
ln -s ../../../../leanring-buddyTests/KokoroVoiceCatalogTests.swift Tests/LumenLogicTests/KokoroVoiceCatalogTests.swift
swift test 2>&1 | tail -3
```
Expected: build error "cannot find 'KokoroVoiceCatalog' in scope".

- [ ] **Step 3: Implement the catalog**

`leanring-buddy/KokoroVoiceCatalog.swift`:
```swift
//
//  KokoroVoiceCatalog.swift
//  leanring-buddy
//
//  The Kokoro voices Lumen offers in the voice picker, with readable
//  labels. Voice codes follow Kokoro's convention: first letter is the
//  accent (a = American, b = British), second is the gender (f/m), then the
//  name. The list is the English subset of FluidAudio's
//  `KokoroAneConstants.englishVoices` as of 0.17.7, copied here so this file
//  stays free of the FluidAudio import and testable from the terminal.
//

import Foundation

nonisolated struct KokoroVoiceOption: Identifiable, Equatable, Sendable {
    /// The Kokoro voice code, e.g. `bm_george`. Stored in settings.
    let id: String
    /// Picker label, e.g. "George (British, male)".
    let label: String
}

nonisolated enum KokoroVoiceCatalog {
    /// Highest-rated British male voice in the Kokoro voice grades; closest
    /// to the JARVIS-style voice Will asked for.
    static let defaultVoice = "bm_george"

    static let voiceCodes: [String] = [
        "af_alloy", "af_aoede", "af_bella", "af_heart", "af_jessica", "af_kore",
        "af_nicole", "af_nova", "af_river", "af_sarah", "af_sky",
        "am_adam", "am_echo", "am_eric", "am_fenrir", "am_liam", "am_michael",
        "am_onyx", "am_puck", "am_santa",
        "bf_alice", "bf_emma", "bf_isabella", "bf_lily",
        "bm_daniel", "bm_fable", "bm_george", "bm_lewis",
    ]

    /// British voices first (the default is British), then American, each
    /// group alphabetical by name.
    static func availableVoices() -> [KokoroVoiceOption] {
        voiceCodes
            .map { KokoroVoiceOption(id: $0, label: label(forVoiceCode: $0)) }
            .sorted { lhs, rhs in
                let lhsIsBritish = lhs.id.hasPrefix("b")
                let rhsIsBritish = rhs.id.hasPrefix("b")
                if lhsIsBritish != rhsIsBritish {
                    return lhsIsBritish
                }
                return lhs.label < rhs.label
            }
    }

    /// "bm_george" → "George (British, male)". Unknown shapes come back
    /// unchanged so a hand-edited setting still renders something.
    static func label(forVoiceCode voiceCode: String) -> String {
        let parts = voiceCode.split(separator: "_", maxSplits: 1)
        guard parts.count == 2, parts[0].count == 2 else { return voiceCode }

        let accentLetter = parts[0].first!
        let genderLetter = parts[0].last!
        let accent: String
        switch accentLetter {
        case "a": accent = "American"
        case "b": accent = "British"
        default: return voiceCode
        }
        let gender: String
        switch genderLetter {
        case "f": gender = "female"
        case "m": gender = "male"
        default: return voiceCode
        }

        let name = parts[1].prefix(1).uppercased() + parts[1].dropFirst()
        return "\(name) (\(accent), \(gender))"
    }
}
```

- [ ] **Step 4: Run the tests**

Run: `cd ~/code/lumen/tools/logic-tests && swift test 2>&1 | tail -3`
Expected: all pass (18 tests in 3 suites).

- [ ] **Step 5: Typecheck app sources, then commit**

Run the typecheck command. Expected: zero errors.

```bash
cd ~/code/lumen
git add leanring-buddy/KokoroVoiceCatalog.swift leanring-buddyTests/KokoroVoiceCatalogTests.swift tools/logic-tests
git commit -m "feat: add Kokoro voice catalog with readable labels"
```

---

### Task 4: KokoroOperatingSystemSupport

**Files:**
- Create: `leanring-buddy/KokoroOperatingSystemSupport.swift`
- Create: `leanring-buddyTests/KokoroOperatingSystemSupportTests.swift`
- Create symlinks into `tools/logic-tests/` for both.

**Interfaces:**
- Produces:
  ```swift
  nonisolated enum KokoroOperatingSystemSupport {
      static func blockingReason(for version: OperatingSystemVersion) -> String?
      static func supportsVersion3Runtime() -> Bool
  }
  ```

- [ ] **Step 1: Write the failing tests**

`leanring-buddyTests/KokoroOperatingSystemSupportTests.swift`:
```swift
import Foundation
import Testing

#if canImport(leanring_buddy)
@testable import leanring_buddy
#else
@testable import LumenLogic
#endif

struct KokoroOperatingSystemSupportTests {

    private func version(_ major: Int, _ minor: Int, _ patch: Int = 0) -> OperatingSystemVersion {
        OperatingSystemVersion(majorVersion: major, minorVersion: minor, patchVersion: patch)
    }

    @Test func blocksTheTwoKnownCrashingBuilds() {
        #expect(KokoroOperatingSystemSupport.blockingReason(for: version(26, 4)) != nil)
        #expect(KokoroOperatingSystemSupport.blockingReason(for: version(26, 5, 1)) != nil)
    }

    @Test func allowsEveryOtherBuild() {
        #expect(KokoroOperatingSystemSupport.blockingReason(for: version(26, 3)) == nil)
        #expect(KokoroOperatingSystemSupport.blockingReason(for: version(26, 6)) == nil)
        #expect(KokoroOperatingSystemSupport.blockingReason(for: version(27, 0)) == nil)
        #expect(KokoroOperatingSystemSupport.blockingReason(for: version(15, 4)) == nil)
    }

    @Test func blockingReasonNamesTheBuildAndTheFix() {
        let reason = KokoroOperatingSystemSupport.blockingReason(for: version(26, 4)) ?? ""
        #expect(reason.contains("26.4"))
        #expect(reason.contains("26.6"))
    }

    @Test func version3RuntimeIsAvailableOnThisMac() {
        // The harness and the app both run on macOS 15+ in practice.
        #expect(KokoroOperatingSystemSupport.supportsVersion3Runtime() == true)
    }
}
```

- [ ] **Step 2: Symlink and run to verify failure**

```bash
cd ~/code/lumen/tools/logic-tests
ln -s ../../../../leanring-buddy/KokoroOperatingSystemSupport.swift Sources/LumenLogic/KokoroOperatingSystemSupport.swift
ln -s ../../../../leanring-buddyTests/KokoroOperatingSystemSupportTests.swift Tests/LumenLogicTests/KokoroOperatingSystemSupportTests.swift
swift test 2>&1 | tail -3
```
Expected: build error "cannot find 'KokoroOperatingSystemSupport' in scope".

- [ ] **Step 3: Implement**

`leanring-buddy/KokoroOperatingSystemSupport.swift`:
```swift
//
//  KokoroOperatingSystemSupport.swift
//  leanring-buddy
//
//  Which macOS builds can run Kokoro safely. FluidAudio's own notes
//  (KokoroAneManager.osAdvisory) record an Apple BNNS bug on macOS 26.4 and
//  26.5 that crashes synthesis in-process with EXC_BAD_ACCESS — not something
//  a catch block can handle — and that 26.6 fixes it. On those builds Lumen
//  refuses to load Kokoro and speaks with the Apple voice instead.
//

import Foundation

nonisolated enum KokoroOperatingSystemSupport {
    /// A user-facing reason when Kokoro must stay off on this macOS build,
    /// or nil when it is fine to load.
    static func blockingReason(for version: OperatingSystemVersion) -> String? {
        guard version.majorVersion == 26, (4...5).contains(version.minorVersion) else {
            return nil
        }
        return "kokoro is off on macOS 26.\(version.minorVersion): an Apple audio bug can crash the app there (fixed in 26.6). using the Apple voice instead."
    }

    /// The hybrid ANE/GPU "v3" Kokoro runtime needs macOS 15. The app's
    /// deployment target is 14.2, so this is a runtime check.
    static func supportsVersion3Runtime() -> Bool {
        if #available(macOS 15, *) {
            return true
        }
        return false
    }
}
```

- [ ] **Step 4: Run the tests, typecheck, commit**

Run: `cd ~/code/lumen/tools/logic-tests && swift test 2>&1 | tail -3` → all pass (22 tests in 4 suites).
Run the typecheck command → zero errors.

```bash
cd ~/code/lumen
git add leanring-buddy/KokoroOperatingSystemSupport.swift leanring-buddyTests/KokoroOperatingSystemSupportTests.swift tools/logic-tests
git commit -m "feat: add macOS build guard for Kokoro synthesis"
```

---

### Task 5: Settings, factory stub, and voice picker

**Files:**
- Modify: `leanring-buddy/AppSettings.swift` (enum at lines 92–111, `Keys` at 120–128, properties after 169, `init` at 173–191)
- Modify: `leanring-buddy/TTSClient.swift` (factory at lines 24–37)
- Modify: `leanring-buddy/CompanionManager.swift` (lines 95–116, `bindSettingsObservation`)
- Modify: `leanring-buddy/CompanionPanelView.swift` (switch at 633–640; add a helper after `appleVoicePickerRow` which ends at line 757)

**Interfaces:**
- Produces: `TextToSpeechProviderKind.kokoro` (raw value `"kokoro"`, displayName `"Kokoro (local)"`, `secretKey` nil); `AppSettings.kokoroVoice: String` (`Keys.kokoroVoice = "settings.kokoroVoice"`, default `KokoroVoiceCatalog.defaultVoice`); fresh-install TTS default `.kokoro`.
- The factory's `.kokoro` case temporarily returns the Apple client so the project compiles; Task 9 replaces it.

- [ ] **Step 1: Add the enum case and setting**

In `AppSettings.swift`, replace the `TextToSpeechProviderKind` enum with:
```swift
enum TextToSpeechProviderKind: String, CaseIterable, Identifiable {
    case kokoro
    case apple
    case elevenLabs = "elevenlabs"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .kokoro: return "Kokoro (local)"
        case .apple: return "Apple (local)"
        case .elevenLabs: return "ElevenLabs"
        }
    }

    var secretKey: SecretsStore.Key? {
        switch self {
        case .kokoro, .apple: return nil
        case .elevenLabs: return .elevenLabs
        }
    }
}
```

Add to `Keys`:
```swift
        static let kokoroVoice = "settings.kokoroVoice"
```

Add after the `elevenLabsVoiceID` property:
```swift
    /// Kokoro voice code, e.g. `bm_george`. See `KokoroVoiceCatalog`.
    @Published var kokoroVoice: String {
        didSet { userDefaults.set(kokoroVoice, forKey: Keys.kokoroVoice) }
    }
```

In `init`, change the TTS default and read the new key:
```swift
        textToSpeechProviderKind = userDefaults.string(forKey: Keys.textToSpeechProvider)
            .flatMap(TextToSpeechProviderKind.init(rawValue:)) ?? .kokoro
```
and after the `elevenLabsVoiceID = …` line:
```swift
        kokoroVoice = userDefaults.string(forKey: Keys.kokoroVoice) ?? KokoroVoiceCatalog.defaultVoice
```

Update the file header comment's default line to read `Apple Speech (STT) → Ollama on localhost (vision LLM) → Kokoro (TTS)`.

- [ ] **Step 2: Stub the factory case**

In `TTSClient.swift`, inside `makeClient`:
```swift
        case .kokoro:
            // Temporary: replaced by KokoroTTSClient once the engine exists.
            return AppleSpeechTTSClient(voiceIdentifier: appSettings.appleVoiceIdentifier)
```

- [ ] **Step 3: Observe the new setting in CompanionManager**

Replace the `voiceSettingsChanged` publisher and the `dropFirst(6)` in `bindSettingsObservation`:
```swift
        let voiceSettingsChanged = Publishers.Merge4(
            appSettings.$textToSpeechProviderKind.map { _ in () },
            appSettings.$appleVoiceIdentifier.map { _ in () },
            appSettings.$elevenLabsVoiceID.map { _ in () },
            appSettings.$kokoroVoice.map { _ in () }
        )

        Publishers.Merge(chatSettingsChanged, voiceSettingsChanged)
            .dropFirst(7) // skip the initial value each of the seven publishers emits on subscribe
```
Also update the comment on `textToSpeechClient` (line 78) to `/// Text-to-speech backend (Kokoro on-device by default; Apple and ElevenLabs selectable).`

- [ ] **Step 4: Add the voice picker to the panel**

In `CompanionPanelView.swift`, change the switch:
```swift
                switch appSettings.textToSpeechProviderKind {
                case .kokoro:
                    kokoroVoicePickerRow
                case .apple:
                    appleVoicePickerRow
                case .elevenLabs:
                    apiKeyRow(for: .elevenLabs)
                    settingsTextFieldRow(title: "Voice ID", text: $appSettings.elevenLabsVoiceID, placeholder: AppSettings.defaultElevenLabsVoiceID)
                }
```
Add after `appleVoicePickerRow`:
```swift
    private var kokoroVoicePickerRow: some View {
        HStack {
            Text("Voice")
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(DS.Colors.textSecondary)
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
```
Change the footer text at line 642 to:
`"Keys are stored in your macOS Keychain. Leave everything on Ollama + Kokoro to run fully offline."`

- [ ] **Step 5: Typecheck**

Run the typecheck command. Expected: zero errors. (If the panel switch complains about exhaustiveness, every case above is required.)

- [ ] **Step 6: Commit**

```bash
cd ~/code/lumen
git add leanring-buddy/AppSettings.swift leanring-buddy/TTSClient.swift leanring-buddy/CompanionManager.swift leanring-buddy/CompanionPanelView.swift
git commit -m "feat: add Kokoro text-to-speech setting and voice picker"
```

---

### Task 6: FluidAudio package dependency (needs Will's Cmd+R)

**Files:**
- Modify: `leanring-buddy.xcodeproj/project.pbxproj`
- Commit after Will's build: `leanring-buddy.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved` (Xcode creates it)

**Interfaces:**
- Produces: `import FluidAudio` compiles in the app target. The three new object IDs below are unique in the file (verified: `grep -c 28F22D0 project.pbxproj` is 0 today).

- [ ] **Step 1: Add a PBXBuildFile section at the top of `objects`**

Insert immediately after the line `	objects = {` (line 7) and its blank line, before `/* Begin PBXContainerItemProxy section */`:
```
/* Begin PBXBuildFile section */
		28F22D0C2F56440300A0FC59 /* FluidAudio in Frameworks */ = {isa = PBXBuildFile; productRef = 28F22D0B2F56440300A0FC59 /* FluidAudio */; };
/* End PBXBuildFile section */

```

- [ ] **Step 2: Link the product in the app target's Frameworks phase**

Replace the app target's Frameworks phase (object `28F22CBC2F56440300A0FC59`, lines 51–57) `files = ( );` with:
```
			files = (
				28F22D0C2F56440300A0FC59 /* FluidAudio in Frameworks */,
			);
```
Leave the two test targets' Frameworks phases empty.

- [ ] **Step 3: Declare the product dependency on the app target**

In the `leanring-buddy` PBXNativeTarget (object `28F22CBE2F56440300A0FC59`), replace `packageProductDependencies = ( );` with:
```
			packageProductDependencies = (
				28F22D0B2F56440300A0FC59 /* FluidAudio */,
			);
```

- [ ] **Step 4: Register the package on the project**

In the PBXProject object, replace `packageReferences = ( );` with:
```
			packageReferences = (
				28F22D0A2F56440300A0FC59 /* XCRemoteSwiftPackageReference "FluidAudio" */,
			);
```

- [ ] **Step 5: Add the two package sections before the closing of `objects`**

Insert after `/* End XCConfigurationList section */` and before the `	};` that closes `objects`:
```
/* Begin XCRemoteSwiftPackageReference section */
		28F22D0A2F56440300A0FC59 /* XCRemoteSwiftPackageReference "FluidAudio" */ = {
			isa = XCRemoteSwiftPackageReference;
			repositoryURL = "https://github.com/FluidInference/FluidAudio";
			requirement = {
				kind = exactVersion;
				version = 0.17.7;
			};
		};
/* End XCRemoteSwiftPackageReference section */

/* Begin XCSwiftPackageProductDependency section */
		28F22D0B2F56440300A0FC59 /* FluidAudio */ = {
			isa = XCSwiftPackageProductDependency;
			package = 28F22D0A2F56440300A0FC59 /* XCRemoteSwiftPackageReference "FluidAudio" */;
			productName = FluidAudio;
		};
/* End XCSwiftPackageProductDependency section */
```

- [ ] **Step 6: Sanity-check the plist syntax**

Run: `plutil -lint ~/code/lumen/leanring-buddy.xcodeproj/project.pbxproj`
Expected: `project.pbxproj: OK`.

- [ ] **Step 7: CHECKPOINT — ask Will to build**

Tell Will: "Open the project in Xcode and press Cmd+R. Xcode will resolve and download FluidAudio 0.17.7 (one binary xcframework included). Confirm the build succeeds and the app still speaks with the Apple voice. Then tell me." Do not continue to Task 7 until he confirms. If resolution fails, the error text decides the fix (usually a network hiccup: File → Packages → Resolve Package Versions).

- [ ] **Step 8: Commit the project change and the resolved file**

```bash
cd ~/code/lumen
git add leanring-buddy.xcodeproj/project.pbxproj leanring-buddy.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved
git commit -m "build: add FluidAudio 0.17.7 package dependency"
```

- [ ] **Step 9: Record the FluidAudio module path for later typechecks**

Run:
```bash
find ~/Library/Developer/Xcode/DerivedData -path "*leanring-buddy*" -name "FluidAudio.swiftmodule" -type d 2>/dev/null | head -1
```
Note the directory that contains it (its parent). Later tasks call it `$FLUIDAUDIO_MODULE_DIR`. If the typecheck with `-I "$FLUIDAUDIO_MODULE_DIR"` fails with "missing required module 'NemoTextProcessing'", add `-F "$(dirname "$FLUIDAUDIO_MODULE_DIR")"` and, if still failing, treat Will's Cmd+R as the compile check for files that import FluidAudio.

---

### Task 7: SentenceAudioQueuePlayer

**Files:**
- Create: `leanring-buddy/SentenceAudioQueuePlayer.swift`
- Create: `leanring-buddyTests/SentenceAudioQueuePlayerTests.swift`
- Create symlinks into `tools/logic-tests/` for both.

**Interfaces:**
- Produces:
  ```swift
  @MainActor final class SentenceAudioQueuePlayer {
      static let sampleRate: Double  // 24_000
      static func makeBuffer(samples: [Float], sampleRate: Double) -> AVAudioPCMBuffer?
      func enqueue(_ buffer: AVAudioPCMBuffer) throws
      var isPlaying: Bool
      func stop()
  }
  ```

- [ ] **Step 1: Write the failing tests**

`leanring-buddyTests/SentenceAudioQueuePlayerTests.swift`:
```swift
import AVFoundation
import Testing

#if canImport(leanring_buddy)
@testable import leanring_buddy
#else
@testable import LumenLogic
#endif

struct SentenceAudioQueuePlayerTests {

    private func silentBuffer(seconds: Double) -> AVAudioPCMBuffer {
        let sampleCount = Int(seconds * SentenceAudioQueuePlayer.sampleRate)
        return SentenceAudioQueuePlayer.makeBuffer(
            samples: [Float](repeating: 0, count: sampleCount),
            sampleRate: SentenceAudioQueuePlayer.sampleRate
        )!
    }

    private func waitUntilNotPlaying(_ player: SentenceAudioQueuePlayer, timeoutSeconds: Double) async -> Bool {
        let deadline = Date().addingTimeInterval(timeoutSeconds)
        while player.isPlaying && Date() < deadline {
            try? await Task.sleep(nanoseconds: 50_000_000)
        }
        return !player.isPlaying
    }

    @Test func makeBufferCopiesSamplesAtTheRequestedRate() {
        let buffer = SentenceAudioQueuePlayer.makeBuffer(samples: [0.25, -0.25, 0.5], sampleRate: 24_000)
        #expect(buffer != nil)
        #expect(buffer?.frameLength == 3)
        #expect(buffer?.format.sampleRate == 24_000)
        #expect(buffer?.format.channelCount == 1)
        #expect(buffer?.floatChannelData?[0][2] == 0.5)
    }

    @Test func makeBufferReturnsNilForEmptySamples() {
        #expect(SentenceAudioQueuePlayer.makeBuffer(samples: [], sampleRate: 24_000) == nil)
    }

    @Test func isPlayingTracksQueuedBuffersUntilTheyFinish() async throws {
        let player = SentenceAudioQueuePlayer()
        #expect(player.isPlaying == false)

        try player.enqueue(silentBuffer(seconds: 0.1))
        try player.enqueue(silentBuffer(seconds: 0.1))
        #expect(player.isPlaying == true)

        let finished = await waitUntilNotPlaying(player, timeoutSeconds: 3)
        #expect(finished == true)
    }

    @Test func stopDiscardsPendingCompletions() async throws {
        let player = SentenceAudioQueuePlayer()
        try player.enqueue(silentBuffer(seconds: 1.0))
        #expect(player.isPlaying == true)

        player.stop()
        #expect(player.isPlaying == false)

        // Late completion callbacks from the stopped buffer must not disturb
        // a new queue.
        try player.enqueue(silentBuffer(seconds: 0.2))
        #expect(player.isPlaying == true)
        let finished = await waitUntilNotPlaying(player, timeoutSeconds: 3)
        #expect(finished == true)
        #expect(player.isPlaying == false)
    }
}
```

- [ ] **Step 2: Symlink and run to verify failure**

```bash
cd ~/code/lumen/tools/logic-tests
ln -s ../../../../leanring-buddy/SentenceAudioQueuePlayer.swift Sources/LumenLogic/SentenceAudioQueuePlayer.swift
ln -s ../../../../leanring-buddyTests/SentenceAudioQueuePlayerTests.swift Tests/LumenLogicTests/SentenceAudioQueuePlayerTests.swift
swift test 2>&1 | tail -3
```
Expected: build error "cannot find 'SentenceAudioQueuePlayer' in scope".

- [ ] **Step 3: Implement the player**

`leanring-buddy/SentenceAudioQueuePlayer.swift`:
```swift
//
//  SentenceAudioQueuePlayer.swift
//  leanring-buddy
//
//  Plays synthesized sentence buffers back to back with no gap. Kokoro hands
//  us one PCM buffer per sentence; AVAudioPlayerNode schedules them in order
//  and starts the next the instant the previous one ends, so a multi-sentence
//  reply sounds continuous even though each sentence was synthesized
//  separately. Also used by the transient-cursor logic through `isPlaying`.
//

import AVFoundation
import Foundation

@MainActor
final class SentenceAudioQueuePlayer {
    /// Kokoro's output rate. The mixer resamples to the output device.
    static let sampleRate: Double = 24_000

    private let audioEngine = AVAudioEngine()
    private let playerNode = AVAudioPlayerNode()
    private let playbackFormat: AVAudioFormat

    /// Buffers scheduled but not yet fully played. `isPlaying` is derived
    /// from it rather than from `playerNode.isPlaying`, which stays true
    /// while the node idles waiting for more data.
    private var scheduledBufferCount = 0

    /// Incremented by `stop()`. Completion callbacks captured with an older
    /// generation are ignored, so a stopped buffer's late callback cannot
    /// decrement the count of a newer queue.
    private var playbackGeneration = 0

    init() {
        playbackFormat = AVAudioFormat(standardFormatWithSampleRate: Self.sampleRate, channels: 1)!
        audioEngine.attach(playerNode)
        audioEngine.connect(playerNode, to: audioEngine.mainMixerNode, format: playbackFormat)
    }

    /// Wraps float samples in a mono PCM buffer. Returns nil for empty input.
    static func makeBuffer(samples: [Float], sampleRate: Double) -> AVAudioPCMBuffer? {
        guard !samples.isEmpty,
              let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 1),
              let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(samples.count)),
              let channelData = buffer.floatChannelData else {
            return nil
        }
        samples.withUnsafeBufferPointer { samplePointer in
            channelData[0].update(from: samplePointer.baseAddress!, count: samples.count)
        }
        buffer.frameLength = AVAudioFrameCount(samples.count)
        return buffer
    }

    /// Schedules `buffer` after anything already queued and starts playback
    /// if the node is idle. Throws if the audio engine cannot start (no
    /// output device, for example).
    func enqueue(_ buffer: AVAudioPCMBuffer) throws {
        if !audioEngine.isRunning {
            try audioEngine.start()
        }

        scheduledBufferCount += 1
        let generationWhenScheduled = playbackGeneration
        playerNode.scheduleBuffer(buffer, completionCallbackType: .dataPlayedBack) { [weak self] _ in
            Task { @MainActor in
                guard let self, self.playbackGeneration == generationWhenScheduled else { return }
                self.scheduledBufferCount = max(0, self.scheduledBufferCount - 1)
            }
        }

        if !playerNode.isPlaying {
            playerNode.play()
        }
    }

    var isPlaying: Bool {
        scheduledBufferCount > 0
    }

    /// Drops every queued buffer immediately. The engine stays running so the
    /// next reply starts without engine start-up latency.
    func stop() {
        playbackGeneration += 1
        scheduledBufferCount = 0
        playerNode.stop()
    }
}
```

- [ ] **Step 4: Run the tests**

Run: `cd ~/code/lumen/tools/logic-tests && swift test 2>&1 | tail -3`
Expected: all pass (26 tests in 5 suites). The two playback tests play about a second of silence through the default output device.

- [ ] **Step 5: Typecheck app sources, then commit**

Run the typecheck command (this file has no FluidAudio import, so the plain command still works). Expected: zero errors.

```bash
cd ~/code/lumen
git add leanring-buddy/SentenceAudioQueuePlayer.swift leanring-buddyTests/SentenceAudioQueuePlayerTests.swift tools/logic-tests
git commit -m "feat: add gapless sentence audio queue player"
```

---

### Task 8: KokoroVoiceEngine

**Files:**
- Create: `leanring-buddy/KokoroVoiceEngine.swift`

**Interfaces:**
- Consumes: `KokoroVoiceCatalog.defaultVoice`, `KokoroOperatingSystemSupport.blockingReason(for:)`, `KokoroOperatingSystemSupport.supportsVersion3Runtime()`, `SentenceAudioQueuePlayer.makeBuffer(samples:sampleRate:)`. From FluidAudio: `KokoroAneManager(variant:defaultVoice:directory:computeUnits:modelStore:version:)`, `initialize(preloadVoices:)`, `synthesizeDetailed(text:voice:speed:) -> KokoroAneSynthesisResult` (`samples: [Float]`, `sampleRate: Int`), `KokoroAneVersion.v3/.legacy`.
- Produces:
  ```swift
  @MainActor final class KokoroVoiceEngine: ObservableObject {
      enum LoadState: Equatable { case notLoaded, loading, ready, failed(message: String), unavailable(reason: String) }
      enum EngineError: LocalizedError { case modelNotReady, emptyAudio }
      static let shared: KokoroVoiceEngine
      static let modelsDirectory: URL
      @Published private(set) var loadState: LoadState
      func prepareIfNeeded(preloadingVoice voice: String) async
      func retryLoad(preloadingVoice voice: String) async
      func synthesizeSentence(_ sentence: String, voice: String) async throws -> AVAudioPCMBuffer
  }
  ```

- [ ] **Step 1: Implement the engine**

`leanring-buddy/KokoroVoiceEngine.swift`:
```swift
//
//  KokoroVoiceEngine.swift
//  leanring-buddy
//
//  Owns the single Kokoro model manager from FluidAudio. It is a singleton
//  because CompanionManager rebuilds its TTS client on every settings change
//  and the Kokoro models (~300 MB, compiled for the Neural Engine on first
//  use) must load once per app run, not once per client.
//
//  First run downloads the models from Hugging Face and compiles them, which
//  takes tens of seconds; later runs load in well under a second. The panel
//  observes `loadState` to show what is happening.
//

import AVFoundation
import Combine
import FluidAudio
import Foundation

@MainActor
final class KokoroVoiceEngine: ObservableObject {
    enum LoadState: Equatable {
        case notLoaded
        case loading
        case ready
        case failed(message: String)
        /// This macOS build cannot run Kokoro safely; see KokoroOperatingSystemSupport.
        case unavailable(reason: String)
    }

    enum EngineError: LocalizedError {
        case modelNotReady
        case emptyAudio

        var errorDescription: String? {
            switch self {
            case .modelNotReady: return "The Kokoro voice model is not loaded."
            case .emptyAudio: return "Kokoro returned no audio for that sentence."
            }
        }
    }

    static let shared = KokoroVoiceEngine()

    /// Everything Kokoro downloads lives here so it is easy to find and delete.
    static let modelsDirectory: URL = FileManager.default
        .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("Lumen/Models", isDirectory: true)

    @Published private(set) var loadState: LoadState

    private var kokoroManager: KokoroAneManager?
    private var inFlightLoadTask: Task<Void, Never>?
    /// Voice packs already fetched and converted, so switching back to one is instant.
    private var preloadedVoices: Set<String> = []

    private init() {
        if let blockingReason = KokoroOperatingSystemSupport.blockingReason(for: ProcessInfo.processInfo.operatingSystemVersion) {
            loadState = .unavailable(reason: blockingReason)
        } else {
            loadState = .notLoaded
        }
    }

    // MARK: - Loading

    /// Downloads (first time), compiles and loads the models plus `voice`'s
    /// pack. Returns when done or failed; never throws. Safe to call
    /// repeatedly — a load already in flight is awaited, and a voice already
    /// preloaded returns immediately.
    func prepareIfNeeded(preloadingVoice voice: String) async {
        if case .unavailable = loadState { return }

        if let inFlightLoadTask {
            await inFlightLoadTask.value
        }

        if case .ready = loadState, preloadedVoices.contains(voice) { return }
        if case .failed = loadState { return }

        let manager = kokoroManager ?? makeManager()
        kokoroManager = manager
        loadState = .loading

        let loadTask = Task { [weak self] in
            do {
                try await manager.initialize(preloadVoices: [voice])
                self?.preloadedVoices.insert(voice)
                self?.loadState = .ready
                print("🔊 Kokoro: model ready, voice \(voice) loaded")
            } catch {
                self?.loadState = .failed(message: "couldn't load the kokoro voice model: \(error.localizedDescription)")
                print("⚠️ Kokoro load failed: \(error)")
            }
        }
        inFlightLoadTask = loadTask
        await loadTask.value
        inFlightLoadTask = nil
    }

    /// Clears a `failed` state and tries again. Used by the Retry button.
    func retryLoad(preloadingVoice voice: String) async {
        if case .failed = loadState {
            loadState = .notLoaded
        }
        await prepareIfNeeded(preloadingVoice: voice)
    }

    // MARK: - Synthesis

    /// Text for one sentence → 24 kHz mono buffer. A voice that was not
    /// preloaded is fetched on demand by the library.
    func synthesizeSentence(_ sentence: String, voice: String) async throws -> AVAudioPCMBuffer {
        guard case .ready = loadState, let kokoroManager else {
            throw EngineError.modelNotReady
        }

        let synthesisResult = try await kokoroManager.synthesizeDetailed(text: sentence, voice: voice)
        guard let buffer = SentenceAudioQueuePlayer.makeBuffer(
            samples: synthesisResult.samples,
            sampleRate: Double(synthesisResult.sampleRate)
        ) else {
            throw EngineError.emptyAudio
        }
        return buffer
    }

    // MARK: - Manager

    private func makeManager() -> KokoroAneManager {
        let runtimeVersion: KokoroAneVersion = KokoroOperatingSystemSupport.supportsVersion3Runtime() ? .v3 : .legacy
        return KokoroAneManager(
            variant: .english,
            defaultVoice: KokoroVoiceCatalog.defaultVoice,
            directory: Self.modelsDirectory,
            version: runtimeVersion
        )
    }
}
```

- [ ] **Step 2: Typecheck with the FluidAudio module**

Run (with `$FLUIDAUDIO_MODULE_DIR` from Task 6 Step 9):
```bash
cd ~/code/lumen && xcrun swiftc -typecheck -sdk "$(xcrun --show-sdk-path --sdk macosx)" -target arm64-apple-macos14.2 -parse-as-library -default-isolation MainActor -I "$FLUIDAUDIO_MODULE_DIR" leanring-buddy/*.swift
```
Expected: zero errors. If the module cannot be found or NemoTextProcessing is missing, skip to Step 3 and rely on Will's build in Task 10.

- [ ] **Step 3: Commit**

```bash
cd ~/code/lumen
git add leanring-buddy/KokoroVoiceEngine.swift
git commit -m "feat: add Kokoro voice engine wrapping the FluidAudio model manager"
```

---

### Task 9: KokoroTTSClient and the real factory case

**Files:**
- Create: `leanring-buddy/KokoroTTSClient.swift`
- Modify: `leanring-buddy/TTSClient.swift` (replace the Task 5 stub)

**Interfaces:**
- Consumes: `TTSClient` protocol, `SentenceSplitter.split`, `KokoroVoiceEngine.shared` (`prepareIfNeeded`, `loadState`, `synthesizeSentence`), `SentenceAudioQueuePlayer`, `AppleSpeechTTSClient(voiceIdentifier:)`.
- Produces: `KokoroTTSClient(voice: String, appleFallbackVoiceIdentifier: String)` conforming to `TTSClient`.

- [ ] **Step 1: Implement the client**

`leanring-buddy/KokoroTTSClient.swift`:
```swift
//
//  KokoroTTSClient.swift
//  leanring-buddy
//
//  Text-to-speech through the on-device Kokoro model. Splits the reply into
//  sentences, synthesizes each through KokoroVoiceEngine and queues the
//  audio so playback starts after the first sentence (~80 ms) while the
//  rest are still being generated.
//
//  If the model cannot load (no network on first run, unsupported macOS
//  build) the reply is spoken with the Apple voice instead, so the user
//  always hears the answer.
//

import AVFoundation
import Foundation

@MainActor
final class KokoroTTSClient: TTSClient {
    private let voice: String
    private let voiceEngine: KokoroVoiceEngine
    private let queuePlayer = SentenceAudioQueuePlayer()
    private let appleFallbackClient: AppleSpeechTTSClient

    /// Synthesizes sentences two onward after `speakText` has returned.
    private var remainingSentencesTask: Task<Void, Never>?
    private var isSynthesizingRemainingSentences = false

    init(voice: String, appleFallbackVoiceIdentifier: String, voiceEngine: KokoroVoiceEngine = .shared) {
        self.voice = voice
        self.voiceEngine = voiceEngine
        self.appleFallbackClient = AppleSpeechTTSClient(voiceIdentifier: appleFallbackVoiceIdentifier)
    }

    // MARK: - TTSClient

    func speakText(_ text: String) async throws {
        stopPlayback()

        // On first run this is the model download + compile; the caller keeps
        // its spinner up until we return.
        await voiceEngine.prepareIfNeeded(preloadingVoice: voice)
        try Task.checkCancellation()

        switch voiceEngine.loadState {
        case .ready:
            break
        case .failed(let message):
            print("⚠️ Kokoro unavailable (\(message)); speaking with the Apple voice instead")
            try await appleFallbackClient.speakText(text)
            return
        case .unavailable(let reason):
            print("⚠️ \(reason)")
            try await appleFallbackClient.speakText(text)
            return
        case .notLoaded, .loading:
            // prepareIfNeeded only returns in a terminal state; treat anything
            // else as a failure rather than speaking nothing.
            print("⚠️ Kokoro in unexpected state \(voiceEngine.loadState); speaking with the Apple voice instead")
            try await appleFallbackClient.speakText(text)
            return
        }

        let sentences = SentenceSplitter.split(text)
        guard let firstSentence = sentences.first else { return }

        do {
            let firstBuffer = try await voiceEngine.synthesizeSentence(firstSentence, voice: voice)
            try Task.checkCancellation()
            try queuePlayer.enqueue(firstBuffer)
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            print("⚠️ Kokoro synthesis failed: \(error); speaking with the Apple voice instead")
            try await appleFallbackClient.speakText(text)
            return
        }

        print("🔊 Kokoro TTS: speaking \(sentences.count) sentence(s) with \(voice)")

        let remainingSentences = Array(sentences.dropFirst())
        guard !remainingSentences.isEmpty else { return }

        isSynthesizingRemainingSentences = true
        remainingSentencesTask = Task { [weak self] in
            guard let self else { return }
            defer { self.isSynthesizingRemainingSentences = false }

            for (sentenceIndex, sentence) in remainingSentences.enumerated() {
                guard !Task.isCancelled else { return }
                do {
                    let buffer = try await self.voiceEngine.synthesizeSentence(sentence, voice: self.voice)
                    guard !Task.isCancelled else { return }
                    try self.queuePlayer.enqueue(buffer)
                } catch {
                    guard !Task.isCancelled else { return }
                    print("⚠️ Kokoro synthesis failed mid-reply: \(error); finishing with the Apple voice")
                    let unspokenText = remainingSentences[sentenceIndex...].joined(separator: " ")
                    await self.finishWithAppleVoiceAfterQueueDrains(unspokenText)
                    return
                }
            }
        }
    }

    var isPlaying: Bool {
        queuePlayer.isPlaying || isSynthesizingRemainingSentences || appleFallbackClient.isPlaying
    }

    func stopPlayback() {
        remainingSentencesTask?.cancel()
        remainingSentencesTask = nil
        isSynthesizingRemainingSentences = false
        queuePlayer.stop()
        appleFallbackClient.stopPlayback()
    }

    // MARK: - Fallback

    /// Waits for the already-queued Kokoro audio to finish, then speaks the
    /// rest with the Apple voice so the two never overlap.
    private func finishWithAppleVoiceAfterQueueDrains(_ unspokenText: String) async {
        while queuePlayer.isPlaying && !Task.isCancelled {
            try? await Task.sleep(nanoseconds: 100_000_000)
        }
        guard !Task.isCancelled else { return }
        try? await appleFallbackClient.speakText(unspokenText)
    }
}
```

- [ ] **Step 2: Replace the factory stub**

In `TTSClient.swift`, replace the `.kokoro` case with:
```swift
        case .kokoro:
            // Start (or continue) loading the model now so the first reply
            // isn't stuck behind a cold load — same idea as OllamaModelWarmer.
            let kokoroVoice = appSettings.kokoroVoice
            Task {
                await KokoroVoiceEngine.shared.prepareIfNeeded(preloadingVoice: kokoroVoice)
            }
            return KokoroTTSClient(
                voice: kokoroVoice,
                appleFallbackVoiceIdentifier: appSettings.appleVoiceIdentifier
            )
```
Update the file header comment of `TTSClient.swift` to mention three backends: Kokoro (on-device, default), Apple, ElevenLabs.

- [ ] **Step 3: Typecheck**

Run the typecheck command with `-I "$FLUIDAUDIO_MODULE_DIR"` (Task 8 Step 2). Expected: zero errors. If the module path trick does not work on this machine, Will's build in Task 10 is the check.

- [ ] **Step 4: Commit**

```bash
cd ~/code/lumen
git add leanring-buddy/KokoroTTSClient.swift leanring-buddy/TTSClient.swift
git commit -m "feat: speak replies with the local Kokoro voice"
```

---

### Task 10: Model status row in the panel (then Will's first real run)

**Files:**
- Modify: `leanring-buddy/CompanionPanelView.swift` (`@ObservedObject` declarations near line 15; `case .kokoro:` from Task 5; add `kokoroModelStatusRow` after `kokoroVoicePickerRow`)

**Interfaces:**
- Consumes: `KokoroVoiceEngine.shared.loadState`, `retryLoad(preloadingVoice:)`, `appSettings.kokoroVoice`.

- [ ] **Step 1: Observe the engine**

Below `@ObservedObject private var appSettings = AppSettings.shared` add:
```swift
    @ObservedObject private var kokoroVoiceEngine = KokoroVoiceEngine.shared
```

- [ ] **Step 2: Show the status row under the picker**

Change the `.kokoro` case to:
```swift
                case .kokoro:
                    kokoroVoicePickerRow
                    kokoroModelStatusRow
```
Add after `kokoroVoicePickerRow`:
```swift
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
                .font(.system(size: 10, weight: .semibold))
                .foregroundColor(DS.Colors.textSecondary)
                .pointerCursor()
            case .unavailable(let reason):
                kokoroStatusText(reason)
            }
            Spacer()
        }
    }

    private func kokoroStatusText(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 10))
            .foregroundColor(DS.Colors.textTertiary)
            .fixedSize(horizontal: false, vertical: true)
    }
```

- [ ] **Step 3: Typecheck**

Run the typecheck command with `-I "$FLUIDAUDIO_MODULE_DIR"`. Expected: zero errors.

- [ ] **Step 4: Commit**

```bash
cd ~/code/lumen
git add leanring-buddy/CompanionPanelView.swift
git commit -m "feat: show Kokoro model download status with retry in AI Settings"
```

- [ ] **Step 5: CHECKPOINT — Will's first Kokoro run**

Tell Will: "Cmd+R. In the menu bar panel → AI Settings → Text to speech, pick **Kokoro (local)**. The status row should show 'downloading voice model…' then 'voice model ready' (first time takes up to a minute). Then hold Ctrl+Option and ask something. Paste the console log if anything is off." Fix anything that fails before moving on; the most likely issues are a Swift 6 isolation complaint in `KokoroVoiceEngine` (resolve by keeping FluidAudio calls inside the `Task` as written) or an audio-engine start error (check the default output device).

---

### Task 11: Manual verification checklist

**Files:** none. Will executes in the running app; the executor records results in the final report.

- [ ] **Step 1: Cold first run** — quit the app, `rm -rf ~/Library/Application\ Support/Lumen/Models`, Cmd+R, select Kokoro, ask a question immediately. Expected: spinner stays until the model is ready, then Kokoro speech; status row went downloading → ready.
- [ ] **Step 2: Warm relaunch** — quit, Cmd+R, ask. Expected: Kokoro speech within about half a second of the model's text finishing.
- [ ] **Step 3: Voice switch** — pick `Fable (British, male)`; ask again. Expected: new voice; status row briefly showed downloading for the new pack.
- [ ] **Step 4: Multi-sentence reply** — ask something that yields 3+ sentences ("explain what each button on this toolbar does"). Expected: no audible gaps.
- [ ] **Step 5: Interrupt** — hold the hotkey mid-sentence. Expected: speech stops instantly; new recording works; after the reply, transient cursor fades (no stuck `isPlaying`). Also: start a fresh cold run, press the hotkey during the download, release — expected: no speech starts later for the abandoned question.
- [ ] **Step 6: Provider round-trip** — switch TTS to Apple, ask; ElevenLabs (if key saved), ask; back to Kokoro, ask. Expected: each works.
- [ ] **Step 7: Offline** — Wi-Fi off, ask. Expected: Kokoro still speaks (models cached).
- [ ] **Step 8: Unit tests in Xcode** — Cmd+U. Expected: the four new suites pass alongside the existing ones.

---

### Task 12: Documentation

**Files:**
- Modify: `AGENTS.md` (Overview paragraph; Architecture "Text-to-Speech" line 19; Key Files table rows after line 52; Build & Run / Typechecking section)
- Modify: `README.md` (line 13, line 42, file tree lines 59–61)
- Modify: `docs/HANDOFF.md` ("Where we are", Settings model, remove "NEXT FEATURE" brief, add the next-feature pointer)
- Modify: `docs/superpowers/specs/2026-10-14-kokoro-tts-design.md` (two corrections below)

- [ ] **Step 1: AGENTS.md**

- Architecture TTS line → `- **Text-to-Speech**: pluggable `TTSClient` — `KokoroTTSClient` (on-device Kokoro-82M via the FluidAudio package, default), `AppleSpeechTTSClient` (AVSpeechSynthesizer) or `ElevenLabsTTSClient` (`eleven_flash_v2_5`, direct). Chosen in `AppSettings.textToSpeechProviderKind`.`
- Add Key Files rows (approximate line counts from the real files):
  - `KokoroVoiceEngine.swift` — singleton owning the FluidAudio `KokoroAneManager`; load state (`notLoaded/loading/ready/failed/unavailable`), model dir `~/Library/Application Support/Lumen/Models`, sentence → PCM buffer.
  - `KokoroTTSClient.swift` — `TTSClient` for Kokoro: sentence split → synthesize → gapless queue; Apple-voice fallback when the model can't load.
  - `SentenceAudioQueuePlayer.swift` — `AVAudioEngine`/`AVAudioPlayerNode` queue with generation-guarded `isPlaying`.
  - `SentenceSplitter.swift` — pure sentence chunker (20/300 char rules).
  - `KokoroVoiceCatalog.swift` — 28 American/British voice codes + labels; default `bm_george`.
  - `KokoroOperatingSystemSupport.swift` — blocks Kokoro on macOS 26.4–26.5; v3 runtime availability.
- Typechecking section: add the `-I "$FLUIDAUDIO_MODULE_DIR"` form and the note that files importing FluidAudio need it; add a "Terminal tests" paragraph: `cd tools/logic-tests && swift test` runs the pure-logic suites without Xcode.
- Overview: "spoken via the configured TTS provider (Kokoro on-device by default; Apple voices and ElevenLabs selectable)".

- [ ] **Step 2: README.md**

- Line 13 → `- **Runs fully offline by default.** Fresh install = Apple Speech (STT) → Ollama on localhost (vision LLM) → Kokoro (local neural TTS, one-time ~300 MB model download). Zero accounts needed. AssemblyAI and ElevenLabs are opt-in toggles.`
- Line 42 → `- **Text to speech** — Kokoro (local) by default: a British male voice out of the box, 28 voices in the menu, models download once from Hugging Face on first use. Apple voices need no download (pick an *Enhanced*/*Premium* voice in System Settings → Accessibility → Spoken Content for best results). ElevenLabs needs a key.`
- File tree: add `KokoroTTSClient.swift`, `KokoroVoiceEngine.swift`, `SentenceAudioQueuePlayer.swift`, `SentenceSplitter.swift`, `KokoroVoiceCatalog.swift` lines next to the TTS entries.

- [ ] **Step 3: HANDOFF.md**

Replace the "NEXT FEATURE" section with a short "Kokoro TTS — shipped" summary (files, what Will verified, the macOS 26.4/26.5 guard) and set the next feature pointer to **memory** (profile + daily notes + "remember this" tool), per the roadmap. Update the Settings model bullet for TTS: `kokoro (default) | apple | elevenLabs; Kokoro voice picker; Apple voice picker`. Add the commits from this plan to the table.

- [ ] **Step 4: Spec corrections**

In the spec, change "All 54 English voices selectable" and "lists all 54 English voices" to "the 28 American/British voices (FluidAudio's `englishVoices` list also contains other-language packs, which are excluded)", and change "`CompanionManager` is not modified" to "`CompanionManager` only gains the `kokoroVoice` publisher in `bindSettingsObservation`".

- [ ] **Step 5: Commit and push**

```bash
cd ~/code/lumen
git add AGENTS.md README.md docs/HANDOFF.md docs/superpowers/specs/2026-10-14-kokoro-tts-design.md
git commit -m "docs: document the Kokoro text-to-speech provider"
git push
```

---

## Self-review notes

- Spec coverage: components (Tasks 7–9), settings (5), factory + warm-up (9), panel picker + status + footer (5, 10), pbxproj (6), failure table (8–9: failed/unavailable/mid-reply/cancel; 5: rebuild calls `stopPlayback` already), tests (2, 3, 4, 7, 11), docs (12). Spec item "KokoroVoiceOption in AppSettings" moved to `KokoroVoiceCatalog` so it stays FluidAudio-free; the spec correction is in Task 12.
- Names used consistently: `prepareIfNeeded(preloadingVoice:)`, `retryLoad(preloadingVoice:)`, `synthesizeSentence(_:voice:)`, `SentenceAudioQueuePlayer.makeBuffer(samples:sampleRate:)`, `enqueue(_:)`, `stop()`, `isPlaying`, `KokoroVoiceCatalog.availableVoices()`, `label(forVoiceCode:)`, `defaultVoice`, `KokoroOperatingSystemSupport.blockingReason(for:)`, `supportsVersion3Runtime()`, `AppSettings.kokoroVoice`, `Keys.kokoroVoice`.
- Review Focus items 1, 2, 4, 5 have tests in Tasks 2, 2, 7, 3; item 3 is code in Task 9 plus manual step 5 in Task 11.
