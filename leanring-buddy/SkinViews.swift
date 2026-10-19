//
//  SkinViews.swift
//  leanring-buddy
//
//  The three views every skin provides, dispatched on the selected skin:
//  the on-screen companion, the mark drawn around a pointing target, and the
//  speech bubble. Per-skin drawing lives in EmberSkinViews, InstrumentSkinViews
//  and MarginaliaSkinViews. All continuous motion is driven by TimelineView,
//  so states need no timers and switching skins applies on the next frame.
//

import AppKit
import SwiftUI

extension Font {
    static func skinFont(size: CGFloat, weight: Font.Weight = .regular, design: SkinFontDesign) -> Font {
        switch design {
        case .serif: return .system(size: size, weight: weight, design: .serif)
        case .monospaced: return .system(size: size, weight: weight, design: .monospaced)
        case .rounded: return .system(size: size, weight: weight, design: .rounded)
        }
    }
}

/// Time helpers shared by the skin animations.
enum SkinMotion {
    /// Continuous motion freezes when the user asked macOS to reduce motion.
    static var shouldReduceMotion: Bool {
        NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
    }

    /// Position within a repeating cycle, 0 ..< 1.
    static func cyclePhase(time: Double, period: Double, offset: Double = 0) -> Double {
        let shifted = (time + offset).truncatingRemainder(dividingBy: period)
        return (shifted < 0 ? shifted + period : shifted) / period
    }

    /// Smooth 0 → 1 → 0 oscillation over one period.
    static func pulse(time: Double, period: Double) -> Double {
        (1 - cos(2 * Double.pi * cyclePhase(time: time, period: period))) / 2
    }

    /// Progress of a one-shot animation that started at `startDate`, 0 ... 1.
    static func oneShotProgress(now: Date, startDate: Date, delay: Double = 0, duration: Double) -> Double {
        let elapsed = now.timeIntervalSince(startDate) - delay
        return min(max(elapsed / duration, 0), 1)
    }
}

/// Centred on its own frame; the overlay positions it at the companion's point.
struct SkinCompanionView: View {
    let skin: LumenSkin
    let visualState: CompanionVisualState
    let microphoneAudioPowerLevel: CGFloat
    /// False on screens where the companion is hidden: the animation clock
    /// pauses there so idle overlays cost nothing.
    let isVisible: Bool

    static let frameSide: CGFloat = 60

    var body: some View {
        let theme = SkinTheme.theme(for: skin)
        let shouldReduceMotion = SkinMotion.shouldReduceMotion
        // Idle motion is slow (multi-second breathe/wobble), so 30 fps is
        // plenty; listening, thinking, speaking and flying run at full rate.
        let minimumFrameInterval: Double? = visualState == .idle ? 1.0 / 30.0 : nil
        TimelineView(.animation(minimumInterval: minimumFrameInterval, paused: shouldReduceMotion || !isVisible)) { timelineContext in
            let animationTime = shouldReduceMotion ? 0 : timelineContext.date.timeIntervalSinceReferenceDate
            Group {
                switch skin {
                case .ember:
                    EmberCompanionView(theme: theme, visualState: visualState, microphoneAudioPowerLevel: microphoneAudioPowerLevel, animationTime: animationTime)
                case .instrument:
                    InstrumentCompanionView(theme: theme, visualState: visualState, microphoneAudioPowerLevel: microphoneAudioPowerLevel, animationTime: animationTime)
                case .marginalia:
                    MarginaliaCompanionView(theme: theme, visualState: visualState, microphoneAudioPowerLevel: microphoneAudioPowerLevel, animationTime: animationTime)
                }
            }
        }
        .frame(width: Self.frameSide, height: Self.frameSide)
        .allowsHitTesting(false)
    }
}

/// Draws in the overlay's full-screen coordinate space around `targetRectInOverlay`.
/// Animates in from the moment it appears.
struct SkinPointingMarkView: View {
    let skin: LumenSkin
    let targetRectInOverlay: CGRect
    let targetRectInAppKitGlobal: CGRect

    @State private var appearedAt = Date()

    var body: some View {
        let theme = SkinTheme.theme(for: skin)
        TimelineView(.animation(minimumInterval: nil, paused: false)) { timelineContext in
            let now = SkinMotion.shouldReduceMotion ? appearedAt.addingTimeInterval(10) : timelineContext.date
            switch skin {
            case .ember:
                EmberPointingMarkView(theme: theme, targetRect: targetRectInOverlay, now: now, appearedAt: appearedAt)
            case .instrument:
                InstrumentPointingMarkView(
                    theme: theme,
                    targetRect: targetRectInOverlay,
                    accessibilityTopLeft: accessibilityTopLeft,
                    now: now,
                    appearedAt: appearedAt
                )
            case .marginalia:
                MarginaliaPointingMarkView(theme: theme, targetRect: targetRectInOverlay, now: now, appearedAt: appearedAt)
            }
        }
        .allowsHitTesting(false)
    }

    /// The element's top-left in Accessibility screen points (origin at the
    /// primary display's top-left): what a future click would use.
    private var accessibilityTopLeft: CGPoint {
        let primaryScreenHeight = NSScreen.screens.first(where: { $0.frame.origin == .zero })?.frame.height
            ?? NSScreen.screens.first?.frame.height
            ?? 0
        return PointingGeometry.accessibilityPoint(
            fromAppKitGlobalPoint: CGPoint(x: targetRectInAppKitGlobal.minX, y: targetRectInAppKitGlobal.maxY),
            primaryScreenHeight: primaryScreenHeight
        )
    }
}

struct SkinBubbleView: View {
    let skin: LumenSkin
    let text: String

    /// A capsule on one line; stays a soft rounded card when a reply wraps.
    private var emberBubbleShape: RoundedRectangle {
        RoundedRectangle(cornerRadius: 13, style: .continuous)
    }

    var body: some View {
        let theme = SkinTheme.theme(for: skin)
        let bubbleBackground = Color(hex: theme.bubbleBackgroundHex)
        let bubbleText = Color(hex: theme.bubbleTextHex)
        switch skin {
        case .ember:
            Text(text)
                .font(.skinFont(size: 12, weight: .semibold, design: theme.fontDesign))
                .foregroundColor(bubbleText)
                .padding(.horizontal, 11)
                .padding(.vertical, 5)
                .background(emberBubbleShape.fill(bubbleBackground.opacity(0.92)))
                .overlay(emberBubbleShape.stroke(Color(hex: theme.markPrimaryHex).opacity(0.45), lineWidth: 1))
                .shadow(color: Color(hex: theme.companionPrimaryHex).opacity(0.35), radius: 8)
        case .instrument:
            Text(text)
                .font(.skinFont(size: 11, weight: .medium, design: theme.fontDesign))
                .foregroundColor(bubbleText)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(RoundedRectangle(cornerRadius: 2).fill(bubbleBackground))
                .overlay(RoundedRectangle(cornerRadius: 2).stroke(Color(hex: theme.companionHaloHex).opacity(0.8), lineWidth: 1))
        case .marginalia:
            Text(text)
                .font(.skinFont(size: 13, design: theme.fontDesign).italic())
                .foregroundColor(bubbleText)
                .padding(.horizontal, 9)
                .padding(.vertical, 4)
                .background(RoundedRectangle(cornerRadius: 4).fill(bubbleBackground))
                .overlay(RoundedRectangle(cornerRadius: 4).stroke(Color(hex: theme.panelTextPrimaryHex), lineWidth: 1))
                .shadow(color: Color(hex: theme.panelTextPrimaryHex).opacity(0.18), radius: 0, x: 3, y: 3)
        }
    }
}
