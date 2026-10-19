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
