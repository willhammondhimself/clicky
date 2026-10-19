//
//  EmberSkinViews.swift
//  leanring-buddy
//
//  Ember: a small warm orb. It breathes when idle, sends out ripples while
//  listening, has satellites orbiting while thinking and pulses while
//  speaking. It points with a warm outline that hugs the element; the glow is
//  only a soft fill inside that outline, never a replacement for it.
//

import SwiftUI

struct EmberCompanionView: View {
    let theme: SkinTheme
    let visualState: CompanionVisualState
    let microphoneAudioPowerLevel: CGFloat
    let animationTime: Double

    private let orbDiameter: CGFloat = 18

    var body: some View {
        let primaryColor = Color(hex: theme.companionPrimaryHex)
        let secondaryColor = Color(hex: theme.companionSecondaryHex)
        let haloColor = Color(hex: theme.companionHaloHex)

        ZStack {
            if visualState == .listening {
                ForEach(0..<2, id: \.self) { rippleIndex in
                    let ripplePhase = SkinMotion.cyclePhase(time: animationTime, period: 1.6, offset: Double(rippleIndex) * 0.8)
                    Circle()
                        .stroke(primaryColor.opacity(0.85 * (1 - ripplePhase)), lineWidth: 1.5)
                        .frame(width: orbDiameter, height: orbDiameter)
                        .scaleEffect(1 + 2.4 * ripplePhase * (1 + microphoneAudioPowerLevel))
                }
            }

            if visualState == .thinking {
                ForEach(Array(satelliteOrbits.enumerated()), id: \.offset) { _, satelliteOrbit in
                    let orbitAngle = 2 * Double.pi * SkinMotion.cyclePhase(time: animationTime, period: satelliteOrbit.period) * satelliteOrbit.direction
                    Circle()
                        .fill(haloColor)
                        .frame(width: satelliteOrbit.diameter, height: satelliteOrbit.diameter)
                        .shadow(color: primaryColor, radius: 3)
                        .offset(x: satelliteOrbit.radius * cos(orbitAngle), y: satelliteOrbit.radius * sin(orbitAngle))
                }
            }

            Circle()
                .fill(
                    RadialGradient(
                        colors: [haloColor, primaryColor, secondaryColor],
                        center: UnitPoint(x: 0.35, y: 0.3),
                        startRadius: 0,
                        endRadius: orbDiameter * 0.75
                    )
                )
                .frame(width: orbDiameter, height: orbDiameter)
                .shadow(color: primaryColor.opacity(0.6), radius: visualState == .speaking ? 14 : 9)
                .scaleEffect(orbScale)
        }
    }

    private var orbScale: CGFloat {
        switch visualState {
        case .speaking: return 1 + 0.28 * SkinMotion.pulse(time: animationTime, period: 0.45)
        case .idle: return 1 + 0.1 * SkinMotion.pulse(time: animationTime, period: 4)
        case .flying: return 1.05
        case .listening, .thinking: return 1
        }
    }

    private struct SatelliteOrbit {
        let radius: CGFloat
        let period: Double
        let direction: Double
        let diameter: CGFloat
    }

    private var satelliteOrbits: [SatelliteOrbit] {
        [
            SatelliteOrbit(radius: 20, period: 1.8, direction: 1, diameter: 5),
            SatelliteOrbit(radius: 16, period: 2.7, direction: -1, diameter: 4),
            SatelliteOrbit(radius: 26, period: 3.6, direction: 1, diameter: 5),
        ]
    }
}

struct EmberPointingMarkView: View {
    let theme: SkinTheme
    let targetRect: CGRect
    let now: Date
    let appearedAt: Date

    var body: some View {
        let markColor = Color(hex: theme.markPrimaryHex)
        let outlineRect = targetRect.insetBy(dx: -6, dy: -6)
        let fadeInProgress = SkinMotion.oneShotProgress(now: now, startDate: appearedAt, duration: 0.4)

        RoundedRectangle(cornerRadius: 8, style: .continuous)
            .fill(markColor.opacity(0.15))
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(markColor, lineWidth: 2)
            )
            .shadow(color: Color(hex: theme.companionHaloHex).opacity(0.9), radius: 2)
            .frame(width: outlineRect.width, height: outlineRect.height)
            .position(x: outlineRect.midX, y: outlineRect.midY)
            .opacity(fadeInProgress)
    }
}
