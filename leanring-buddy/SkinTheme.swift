//
//  SkinTheme.swift
//  leanring-buddy
//
//  Colour, type and shape tokens for each skin, as plain values so they can be
//  unit-tested without SwiftUI. Colours are "#RRGGBB" strings, turned into
//  SwiftUI colours by Color(hex:). Values come from the "Lumen look board"
//  (cards A Ember, B Instrument, C Marginalia); panel text passes WCAG AA over
//  any wallpaper at the glass tint (SkinContrastTests).
//
//  Each skin has one fixed palette: skins do not follow macOS light/dark mode.
//  The companion halo keeps the companion and its marks visible on any window.
//

import Foundation

nonisolated enum SkinFontDesign: Equatable {
    /// New York.
    case serif
    /// SF Mono.
    case monospaced
    /// SF Pro Rounded.
    case rounded
}

nonisolated struct SkinTheme: Equatable {
    let panelBackgroundHex: String
    let panelTextPrimaryHex: String
    let panelTextSecondaryHex: String
    let panelTextTertiaryHex: String
    let panelBorderHex: String
    let panelAccentHex: String
    let panelOnAccentHex: String
    let panelControlFillHex: String
    let panelCornerRadius: Double
    let panelBorderWidth: Double
    /// Offset of a hard, unblurred drop shadow; 0 means a soft shadow instead.
    let panelHardShadowOffset: Double
    /// Glass card (system glass on macOS 26, frosted material before that).
    let usesGlassPanel: Bool
    /// How much of the glass is the panel colour versus the wallpaper behind
    /// it (1 = opaque). Ignored by skins without a glass panel.
    let glassTintOpacity: Double
    /// The card is light, so the panel's system controls (pickers, text
    /// fields, switches) are drawn in the light appearance even in dark mode.
    let isLightPanel: Bool
    let fontDesign: SkinFontDesign
    let companionPrimaryHex: String
    let companionSecondaryHex: String
    /// Contrasting outline/glow drawn around the companion and its marks.
    let companionHaloHex: String
    let markPrimaryHex: String
    /// Highlighter colour swiped across the target (Marginalia only).
    let markHighlightHex: String?
    let bubbleBackgroundHex: String
    let bubbleTextHex: String

    static func theme(for skin: LumenSkin) -> SkinTheme {
        switch skin {
        case .ember:
            return SkinTheme(
                panelBackgroundHex: "#261B2E",
                panelTextPrimaryHex: "#F7EBE6",
                panelTextSecondaryHex: "#D8C6CF",
                panelTextTertiaryHex: "#BBA9B9",
                panelBorderHex: "#3A2C44",
                panelAccentHex: "#FF9A6B",
                panelOnAccentHex: "#261B2E",
                panelControlFillHex: "#33263D",
                panelCornerRadius: 20,
                panelBorderWidth: 1,
                panelHardShadowOffset: 0,
                usesGlassPanel: true,
                glassTintOpacity: 0.85,
                isLightPanel: false,
                fontDesign: .rounded,
                companionPrimaryHex: "#FFB36B",
                companionSecondaryHex: "#FF6F61",
                companionHaloHex: "#FFF3D6",
                markPrimaryHex: "#FF9A6B",
                markHighlightHex: nil,
                bubbleBackgroundHex: "#261B2E",
                bubbleTextHex: "#F7EBE6"
            )
        case .instrument:
            return SkinTheme(
                panelBackgroundHex: "#EEF1EF",
                panelTextPrimaryHex: "#1A1D1C",
                panelTextSecondaryHex: "#3B4240",
                panelTextTertiaryHex: "#666E6B",
                panelBorderHex: "#1A1D1C",
                panelAccentHex: "#FF5A1F",
                panelOnAccentHex: "#EEF1EF",
                panelControlFillHex: "#DDE2DF",
                panelCornerRadius: 3,
                panelBorderWidth: 1,
                panelHardShadowOffset: 4,
                usesGlassPanel: false,
                glassTintOpacity: 1,
                isLightPanel: true,
                fontDesign: .monospaced,
                companionPrimaryHex: "#1A1D1C",
                companionSecondaryHex: "#FF5A1F",
                companionHaloHex: "#EEF1EF",
                markPrimaryHex: "#FF5A1F",
                markHighlightHex: nil,
                bubbleBackgroundHex: "#1A1D1C",
                bubbleTextHex: "#EEF1EF"
            )
        case .marginalia:
            return SkinTheme(
                panelBackgroundHex: "#F7F6FB",
                panelTextPrimaryHex: "#1B1535",
                panelTextSecondaryHex: "#3D3560",
                panelTextTertiaryHex: "#5A5571",
                panelBorderHex: "#CDC8DF",
                panelAccentHex: "#1B1535",
                panelOnAccentHex: "#F7F6FB",
                panelControlFillHex: "#ECEAF3",
                panelCornerRadius: 20,
                panelBorderWidth: 1,
                panelHardShadowOffset: 0,
                usesGlassPanel: true,
                glassTintOpacity: 0.85,
                isLightPanel: true,
                fontDesign: .serif,
                companionPrimaryHex: "#1B1535",
                companionSecondaryHex: "#1B1535",
                companionHaloHex: "#F7F6FB",
                markPrimaryHex: "#1B1535",
                markHighlightHex: "#FFE14D",
                bubbleBackgroundHex: "#F7F6FB",
                bubbleTextHex: "#1B1535"
            )
        }
    }
}
