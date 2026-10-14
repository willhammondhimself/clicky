//
//  KokoroModelLoadState.swift
//  leanring-buddy
//
//  Where the Kokoro voice model is in its lifecycle. Published by
//  KokoroVoiceEngine (via KokoroModelLoadCoordinator) and shown in the
//  AI Settings status row.
//

import Foundation

nonisolated enum KokoroModelLoadState: Equatable, Sendable {
    case notLoaded
    case loading
    case ready
    case failed(message: String)
    /// This macOS build cannot run Kokoro safely; see KokoroOperatingSystemSupport.
    case unavailable(reason: String)
}
