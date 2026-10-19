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
