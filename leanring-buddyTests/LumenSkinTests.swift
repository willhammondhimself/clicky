import Foundation
import Testing

#if canImport(leanring_buddy)
@testable import leanring_buddy
#else
@testable import LumenLogic
#endif

struct LumenSkinTests {

    @Test func defaultSkinIsMarginalia() {
        #expect(LumenSkin.defaultSkin == .marginalia)
    }

    @Test func rawValuesAreStableForPersistence() {
        #expect(LumenSkin.allCases.map(\.rawValue) == ["ember", "instrument", "marginalia"])
    }

    @Test func displayNames() {
        #expect(LumenSkin.allCases.map(\.displayName) == ["Ember", "Instrument", "Marginalia"])
    }

    @Test func everyThemeTokenIsAValidHexColour() throws {
        let hexColourPattern = try Regex("^#[0-9A-F]{6}$")
        for skin in LumenSkin.allCases {
            let theme = SkinTheme.theme(for: skin)
            let hexTokens: [String?] = [
                theme.panelBackgroundHex, theme.panelTextPrimaryHex, theme.panelTextSecondaryHex,
                theme.panelTextTertiaryHex, theme.panelBorderHex, theme.panelAccentHex,
                theme.panelOnAccentHex, theme.panelControlFillHex, theme.companionPrimaryHex,
                theme.companionSecondaryHex, theme.companionHaloHex, theme.markPrimaryHex,
                theme.markHighlightHex, theme.bubbleBackgroundHex, theme.bubbleTextHex,
            ]
            for hexToken in hexTokens.compactMap({ $0 }) {
                #expect(hexToken.wholeMatch(of: hexColourPattern) != nil, "\(skin): \(hexToken)")
            }
        }
    }

    @Test func lightPanelSkinsAreInstrumentAndMarginalia() {
        // System controls in the panel must match the card, not macOS dark mode.
        #expect(!SkinTheme.theme(for: .ember).isLightPanel)
        #expect(SkinTheme.theme(for: .instrument).isLightPanel)
        #expect(SkinTheme.theme(for: .marginalia).isLightPanel)
    }

    @Test func skinCharacterTokens() {
        let ember = SkinTheme.theme(for: .ember)
        #expect(ember.fontDesign == .rounded)
        #expect(ember.usesGlassPanel)

        let instrument = SkinTheme.theme(for: .instrument)
        #expect(instrument.fontDesign == .monospaced)
        #expect(!instrument.usesGlassPanel)
        #expect(instrument.panelHardShadowOffset == 4)
        #expect(instrument.panelCornerRadius == 3)

        let marginalia = SkinTheme.theme(for: .marginalia)
        #expect(marginalia.fontDesign == .serif)
        #expect(marginalia.usesGlassPanel)
        #expect(marginalia.panelCornerRadius == 20)
        #expect(marginalia.markHighlightHex == "#FFE14D")
    }
}
