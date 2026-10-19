//
//  LumenSkin.swift
//  leanring-buddy
//
//  The switchable looks Lumen ships with. A skin decides how the on-screen
//  companion, its pointing mark, its speech bubble, the menu bar icon and the
//  control panel look; SkinTheme holds each skin's colours and type.
//

import Foundation

nonisolated enum LumenSkin: String, CaseIterable, Identifiable {
    /// Warm glowing orb on dark plum glass.
    case ember
    /// Gauge ring with corner brackets and an x/y readout, monospaced.
    case instrument
    /// Ink dot on paper, serif, points with a drawn circle and a highlighter.
    case marginalia

    /// Will's chosen default: Marginalia drawn with Ember's motion.
    static let defaultSkin: LumenSkin = .marginalia

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .ember: return "Ember"
        case .instrument: return "Instrument"
        case .marginalia: return "Marginalia"
        }
    }
}
