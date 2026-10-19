//
//  MicrophoneSelection.swift
//  leanring-buddy
//
//  Which microphone push-to-talk records from. By default Lumen uses the
//  MacBook's built-in mic even when AirPods are macOS's default input:
//  opening the AirPods mic switches them to their low-quality headset mode
//  (which also degrades Lumen's voice) and the route change stopped
//  recording. "System default" hands the choice back to macOS; with the lid
//  closed there is no built-in mic, so macOS chooses then too.
//

import Foundation

nonisolated enum MicrophonePreference: String, CaseIterable, Identifiable {
    case builtIn
    case systemDefault

    static let defaultPreference: MicrophonePreference = .builtIn

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .builtIn: return "MacBook mic"
        case .systemDefault: return "System default"
        }
    }
}

nonisolated enum AudioInputTransport: Equatable {
    case builtIn
    case bluetooth
    case other
}

nonisolated struct AudioInputDeviceInfo: Equatable {
    let deviceIdentifier: UInt32
    let name: String
    let transport: AudioInputTransport
}

nonisolated enum MicrophoneSelection {
    /// The Core Audio device to record from, or nil to leave the recording
    /// on macOS's default input.
    static func inputDeviceIdentifier(
        preference: MicrophonePreference,
        availableInputDevices: [AudioInputDeviceInfo]
    ) -> UInt32? {
        guard preference == .builtIn else { return nil }
        return availableInputDevices.first(where: { $0.transport == .builtIn })?.deviceIdentifier
    }
}
