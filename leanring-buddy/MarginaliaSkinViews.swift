//
//  MarginaliaSkinViews.swift
//  leanring-buddy
//
//  Marginalia, the default skin, drawn with Ember's motion: an ink dot that
//  sends out ink ripples while listening, has small ink dots orbiting while
//  thinking and pulses while speaking. It points by drawing a loose ink
//  circle around the element and then swiping a translucent highlighter
//  across it. Every ink stroke carries a thin paper-coloured halo so it stays
//  visible on dark windows.
//

import SwiftUI

struct MarginaliaCompanionView: View {
    let theme: SkinTheme
    let visualState: CompanionVisualState
    let microphoneAudioPowerLevel: CGFloat
    let animationTime: Double

    private let dotDiameter: CGFloat = 12

    var body: some View {
        let inkColor = Color(hex: theme.companionPrimaryHex)
        let paperColor = Color(hex: theme.companionHaloHex)

        ZStack {
            if visualState == .listening {
                ForEach(0..<2, id: \.self) { rippleIndex in
                    let ripplePhase = SkinMotion.cyclePhase(time: animationTime, period: 1.6, offset: Double(rippleIndex) * 0.8)
                    ZStack {
                        Circle().stroke(paperColor.opacity(0.7 * (1 - ripplePhase)), lineWidth: 3.5)
                        Circle().stroke(inkColor.opacity(0.85 * (1 - ripplePhase)), lineWidth: 1.5)
                    }
                    .frame(width: dotDiameter, height: dotDiameter)
                    .scaleEffect(1 + 2.4 * ripplePhase * (1 + microphoneAudioPowerLevel))
                }
            }

            if visualState == .thinking {
                ForEach(Array(satelliteOrbits.enumerated()), id: \.offset) { _, satelliteOrbit in
                    let orbitAngle = 2 * Double.pi * SkinMotion.cyclePhase(time: animationTime, period: satelliteOrbit.period) * satelliteOrbit.direction
                    Circle()
                        .fill(inkColor)
                        .overlay(Circle().stroke(paperColor, lineWidth: 1))
                        .frame(width: 4, height: 4)
                        .offset(x: satelliteOrbit.radius * cos(orbitAngle), y: satelliteOrbit.radius * sin(orbitAngle))
                }
            }

            Circle()
                .fill(inkColor)
                .overlay(Circle().stroke(paperColor, lineWidth: 1.5))
                .frame(width: dotDiameter, height: dotDiameter)
                .scaleEffect(dotScale)
                .offset(wobbleOffset)
        }
    }

    private var dotScale: CGFloat {
        switch visualState {
        case .speaking: return 1 + 0.3 * SkinMotion.pulse(time: animationTime, period: 0.45)
        default: return 1
        }
    }

    private var wobbleOffset: CGSize {
        guard visualState == .idle else { return .zero }
        let wobbleAmount = SkinMotion.pulse(time: animationTime, period: 3.4)
        return CGSize(width: 1.5 * wobbleAmount, height: -2 * wobbleAmount)
    }

    private struct SatelliteOrbit {
        let radius: CGFloat
        let period: Double
        let direction: Double
    }

    private var satelliteOrbits: [SatelliteOrbit] {
        [
            SatelliteOrbit(radius: 16, period: 1.8, direction: 1),
            SatelliteOrbit(radius: 12, period: 2.7, direction: -1),
            SatelliteOrbit(radius: 21, period: 3.6, direction: 1),
        ]
    }
}

/// A loose, slightly overshooting loop around the rect, like a circle drawn
/// by hand in a margin: a bit more than one full turn with a gently varying
/// radius, so the end passes the start.
private struct HandDrawnLoopShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let horizontalRadius = rect.width / 2
        let verticalRadius = rect.height / 2
        let startAngle = Double.pi * 0.85
        let totalTurn = 2 * Double.pi * 1.12
        let segmentCount = 96

        for segmentIndex in 0...segmentCount {
            let progress = Double(segmentIndex) / Double(segmentCount)
            let angle = startAngle + totalTurn * progress
            let radiusWobble = 1 + 0.045 * sin(3 * angle) - 0.035 * progress
            let point = CGPoint(
                x: center.x + horizontalRadius * radiusWobble * cos(angle),
                y: center.y + verticalRadius * radiusWobble * sin(angle)
            )
            if segmentIndex == 0 {
                path.move(to: point)
            } else {
                path.addLine(to: point)
            }
        }
        return path
    }
}

struct MarginaliaPointingMarkView: View {
    let theme: SkinTheme
    let targetRect: CGRect
    let now: Date
    let appearedAt: Date

    var body: some View {
        let inkColor = Color(hex: theme.markPrimaryHex)
        let paperColor = Color(hex: theme.companionHaloHex)
        let highlighterColor = Color(hex: theme.markHighlightHex ?? "#FFE14D")
        let loopRect = targetRect.insetBy(dx: -10, dy: -10)
        let highlightRect = targetRect.insetBy(dx: -2, dy: -2)
        let drawProgress = SkinMotion.oneShotProgress(now: now, startDate: appearedAt, duration: 0.9)
        let swipeProgress = SkinMotion.oneShotProgress(now: now, startDate: appearedAt, delay: 0.9, duration: 0.5)

        ZStack {
            Rectangle()
                .fill(highlighterColor.opacity(0.5))
                .frame(width: highlightRect.width, height: highlightRect.height)
                .scaleEffect(x: swipeProgress, y: 1, anchor: .leading)
                .position(x: highlightRect.midX, y: highlightRect.midY)

            HandDrawnLoopShape()
                .trim(from: 0, to: drawProgress)
                .stroke(paperColor, style: StrokeStyle(lineWidth: 4.5, lineCap: .round, lineJoin: .round))
                .frame(width: loopRect.width, height: loopRect.height)
                .position(x: loopRect.midX, y: loopRect.midY)

            HandDrawnLoopShape()
                .trim(from: 0, to: drawProgress)
                .stroke(inkColor, style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
                .frame(width: loopRect.width, height: loopRect.height)
                .position(x: loopRect.midX, y: loopRect.midY)
        }
    }
}
