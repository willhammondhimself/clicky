import Testing

#if canImport(leanring_buddy)
@testable import leanring_buddy
#else
@testable import LumenLogic
#endif

struct SkinContrastTests {

    @Test func blackOnWhiteIsTwentyOneToOne() {
        #expect(abs(SkinContrast.contrastRatio(foregroundHex: "#000000", backgroundHex: "#FFFFFF") - 21) < 0.01)
    }

    @Test func contrastIsSymmetric() {
        let forward = SkinContrast.contrastRatio(foregroundHex: "#1B1535", backgroundHex: "#F7F6FB")
        let backward = SkinContrast.contrastRatio(foregroundHex: "#F7F6FB", backgroundHex: "#1B1535")
        #expect(abs(forward - backward) < 0.0001)
    }

    @Test func blendMixesTheTintOverTheWallpaper() {
        #expect(SkinContrast.blendedHex(tintHex: "#FFFFFF", wallpaperHex: "#000000", tintOpacity: 0.5) == "#808080")
        #expect(SkinContrast.blendedHex(tintHex: "#F7F6FB", wallpaperHex: "#123456", tintOpacity: 1) == "#F7F6FB")
    }

    @Test func glassSkinsUseAnEightyFivePercentTint() {
        #expect(SkinTheme.theme(for: .ember).glassTintOpacity == 0.85)
        #expect(SkinTheme.theme(for: .marginalia).glassTintOpacity == 0.85)
    }

    /// Glass lets the wallpaper through. Every line of panel text must still
    /// meet WCAG AA (4.5:1) with the tint over a black, grey or white
    /// wallpaper, the worst cases for light and dark glass.
    @Test func everyPanelTextColourIsReadableOverAnyWallpaper() {
        let worstCaseWallpaperHexes = ["#000000", "#808080", "#FFFFFF"]
        for skin in LumenSkin.allCases {
            let theme = SkinTheme.theme(for: skin)
            let tintOpacity = theme.usesGlassPanel ? theme.glassTintOpacity : 1
            let textHexes = [
                ("primary", theme.panelTextPrimaryHex),
                ("secondary", theme.panelTextSecondaryHex),
                ("tertiary", theme.panelTextTertiaryHex),
            ]
            for wallpaperHex in worstCaseWallpaperHexes {
                let panelHex = SkinContrast.blendedHex(tintHex: theme.panelBackgroundHex, wallpaperHex: wallpaperHex, tintOpacity: tintOpacity)
                for (textName, textHex) in textHexes {
                    let ratio = SkinContrast.contrastRatio(foregroundHex: textHex, backgroundHex: panelHex)
                    #expect(ratio >= 4.5, "\(skin) \(textName) \(textHex) over \(wallpaperHex): \(ratio)")
                }
            }
        }
    }
}
