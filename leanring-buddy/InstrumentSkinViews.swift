//
//  InstrumentSkinViews.swift
//  leanring-buddy
//
//  Instrument: a gauge ring with tick marks and a signal-orange core. Ticks
//  step while listening, an orange sector sweeps while thinking, the core
//  pulses while speaking. It points by snapping four corner brackets onto the
//  element and showing the element's x/y in screen points.
//

import SwiftUI

struct InstrumentCompanionView: View {
    let theme: SkinTheme
    let visualState: CompanionVisualState
    let microphoneAudioPowerLevel: CGFloat
    let animationTime: Double

    private let tickRingDiameter: CGFloat = 28
    private let innerRingDiameter: CGFloat = 20
    private let tickCount = 24

    var body: some View {
        let ringColor = Color(hex: theme.companionPrimaryHex)
        let signalColor = Color(hex: theme.companionSecondaryHex)
        let haloColor = Color(hex: theme.companionHaloHex)
        let tickCircumference = Double.pi * tickRingDiameter
        let tickSpacing = tickCircumference / Double(tickCount)

        ZStack {
            Circle()
                .stroke(ringColor, style: StrokeStyle(lineWidth: 3, dash: [1.2, tickSpacing - 1.2]))
                .frame(width: tickRingDiameter, height: tickRingDiameter)
                .rotationEffect(.degrees(360 * SkinMotion.cyclePhase(time: animationTime, period: tickRotationPeriod)))

            Circle()
                .stroke(ringColor, lineWidth: 1.5)
                .frame(width: innerRingDiameter, height: innerRingDiameter)

            if visualState == .thinking {
                QuarterSectorShape()
                    .fill(signalColor.opacity(0.25))
                    .overlay(QuarterSectorShape().stroke(signalColor, lineWidth: 1.5))
                    .frame(width: innerRingDiameter, height: innerRingDiameter)
                    .rotationEffect(.degrees(360 * SkinMotion.cyclePhase(time: animationTime, period: 0.9)))
            }

            Circle()
                .fill(signalColor)
                .frame(width: 4, height: 4)
                .scaleEffect(coreScale)
        }
        // Thin light outline so the dark ring reads on dark windows.
        .shadow(color: haloColor, radius: 0.8)
        .shadow(color: haloColor.opacity(0.7), radius: 1.6)
        .scaleEffect(ringScale)
    }

    private var tickRotationPeriod: Double {
        switch visualState {
        case .listening: return 3
        case .speaking: return 8
        default: return 24
        }
    }

    private var ringScale: CGFloat {
        switch visualState {
        case .listening:
            // Steps between two sizes twice a second; louder speech steps further.
            let isExpandedStep = SkinMotion.cyclePhase(time: animationTime, period: 1.0) >= 0.5
            return isExpandedStep ? 1 + 0.14 * (1 + microphoneAudioPowerLevel) : 1
        case .flying:
            return 0.9
        default:
            return 1
        }
    }

    private var coreScale: CGFloat {
        guard visualState == .speaking else { return 1 }
        let isExpandedStep = SkinMotion.cyclePhase(time: animationTime, period: 0.6) >= 0.5
        return isExpandedStep ? 1.9 : 1
    }
}

/// A 90° pie slice from 12 o'clock to 3 o'clock.
private struct QuarterSectorShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let center = CGPoint(x: rect.midX, y: rect.midY)
        path.move(to: center)
        path.addArc(center: center, radius: rect.width / 2, startAngle: .degrees(-90), endAngle: .degrees(0), clockwise: false)
        path.closeSubpath()
        return path
    }
}

/// Four L-shaped corners around the rect.
private struct CornerBracketsShape: Shape {
    let bracketLength: CGFloat

    func path(in rect: CGRect) -> Path {
        var path = Path()
        let corners: [(CGPoint, CGFloat, CGFloat)] = [
            (CGPoint(x: rect.minX, y: rect.minY), 1, 1),
            (CGPoint(x: rect.maxX, y: rect.minY), -1, 1),
            (CGPoint(x: rect.minX, y: rect.maxY), 1, -1),
            (CGPoint(x: rect.maxX, y: rect.maxY), -1, -1),
        ]
        for (cornerPoint, horizontalDirection, verticalDirection) in corners {
            path.move(to: CGPoint(x: cornerPoint.x + horizontalDirection * bracketLength, y: cornerPoint.y))
            path.addLine(to: cornerPoint)
            path.addLine(to: CGPoint(x: cornerPoint.x, y: cornerPoint.y + verticalDirection * bracketLength))
        }
        return path
    }
}

struct InstrumentPointingMarkView: View {
    let theme: SkinTheme
    let targetRect: CGRect
    let accessibilityTopLeft: CGPoint
    let now: Date
    let appearedAt: Date

    var body: some View {
        let signalColor = Color(hex: theme.markPrimaryHex)
        let inkColor = Color(hex: theme.companionPrimaryHex)
        let bracketRect = targetRect.insetBy(dx: -6, dy: -6)
        // Snap in over 0.3 s in three discrete steps, like a gauge settling.
        let snapProgress = SkinMotion.oneShotProgress(now: now, startDate: appearedAt, duration: 0.3)
        let steppedSnapProgress = (snapProgress * 3).rounded(.down) / 3
        let bracketScale = 1.5 - 0.5 * steppedSnapProgress

        ZStack(alignment: .topLeading) {
            CornerBracketsShape(bracketLength: 14)
                .stroke(inkColor.opacity(0.6), lineWidth: 4)
            CornerBracketsShape(bracketLength: 14)
                .stroke(signalColor, lineWidth: 2)

            Text("x \(Int(accessibilityTopLeft.x.rounded()))  y \(Int(accessibilityTopLeft.y.rounded()))")
                .font(.skinFont(size: 10, weight: .medium, design: .monospaced))
                .foregroundColor(inkColor)
                .padding(.horizontal, 6)
                .padding(.vertical, 1)
                .background(Rectangle().fill(signalColor))
                .offset(y: -18)
                .opacity(snapProgress >= 1 ? 1 : 0)
        }
        .frame(width: bracketRect.width, height: bracketRect.height)
        .scaleEffect(bracketScale)
        .opacity(snapProgress > 0 ? 1 : 0)
        .position(x: bracketRect.midX, y: bracketRect.midY)
    }
}
