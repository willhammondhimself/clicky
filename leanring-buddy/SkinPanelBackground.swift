//
//  SkinPanelBackground.swift
//  leanring-buddy
//
//  The control panel's card, drawn per skin. Glass skins (Ember, Marginalia)
//  use the system glass effect on macOS 26 and a frosted fill before that;
//  Instrument is a solid instrument-grey card with a 1 pt ink border and a
//  hard offset shadow. The panel window is exactly the size of its content,
//  so the hard shadow is drawn inside that frame (the card is inset by the
//  shadow offset) rather than spilling outside where it would be clipped.
//

import SwiftUI

struct SkinPanelBackground: View {
    let theme: SkinTheme

    var body: some View {
        let cardShape = RoundedRectangle(cornerRadius: theme.panelCornerRadius, style: .continuous)
        let backgroundColor = Color(hex: theme.panelBackgroundHex)
        let borderColor = Color(hex: theme.panelBorderHex)

        if theme.panelHardShadowOffset > 0 {
            let shadowOffset = theme.panelHardShadowOffset
            ZStack(alignment: .topLeading) {
                cardShape
                    .fill(Color(hex: theme.panelTextPrimaryHex).opacity(0.9))
                    .padding(.leading, shadowOffset)
                    .padding(.top, shadowOffset)
                cardShape
                    .fill(backgroundColor)
                    .overlay(cardShape.stroke(borderColor, lineWidth: theme.panelBorderWidth))
                    .padding(.trailing, shadowOffset)
                    .padding(.bottom, shadowOffset)
            }
        } else {
            ZStack {
                if theme.usesGlassPanel {
                    glassFill(cardShape: cardShape, backgroundColor: backgroundColor)
                } else {
                    cardShape.fill(backgroundColor)
                }
                cardShape.stroke(borderColor, lineWidth: theme.panelBorderWidth)
            }
            .shadow(color: Color.black.opacity(0.35), radius: 18, x: 0, y: 10)
        }
    }

    @ViewBuilder
    private func glassFill(cardShape: RoundedRectangle, backgroundColor: Color) -> some View {
        if #available(macOS 26.0, *) {
            cardShape
                .fill(backgroundColor.opacity(0.35))
                .glassEffect(.regular.tint(backgroundColor.opacity(theme.glassTintOpacity)), in: cardShape)
        } else {
            ZStack {
                cardShape.fill(.ultraThinMaterial)
                cardShape.fill(backgroundColor.opacity(theme.glassTintOpacity))
            }
        }
    }
}
