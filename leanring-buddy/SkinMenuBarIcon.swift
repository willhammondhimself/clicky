//
//  SkinMenuBarIcon.swift
//  leanring-buddy
//
//  The menu bar icon for each skin, drawn as an 18×18 template image so
//  macOS tints it for light and dark menu bars.
//

import AppKit

enum SkinMenuBarIcon {
    static func makeTemplateImage(for skin: LumenSkin) -> NSImage {
        let iconSize = NSSize(width: 18, height: 18)
        let image = NSImage(size: iconSize, flipped: false) { drawingRect in
            NSColor.black.setFill()
            NSColor.black.setStroke()
            let center = NSPoint(x: drawingRect.midX, y: drawingRect.midY)

            switch skin {
            case .ember:
                circlePath(center: center, radius: 5).fill()
                let outerRing = circlePath(center: center, radius: 8)
                outerRing.lineWidth = 1
                outerRing.stroke()

            case .instrument:
                let tickCount = 12
                for tickIndex in 0..<tickCount {
                    let angle = 2 * Double.pi * Double(tickIndex) / Double(tickCount)
                    let tick = NSBezierPath()
                    tick.move(to: NSPoint(x: center.x + 6.6 * cos(angle), y: center.y + 6.6 * sin(angle)))
                    tick.line(to: NSPoint(x: center.x + 8.4 * cos(angle), y: center.y + 8.4 * sin(angle)))
                    tick.lineWidth = 1.2
                    tick.stroke()
                }
                let innerRing = circlePath(center: center, radius: 4.6)
                innerRing.lineWidth = 1
                innerRing.stroke()
                circlePath(center: center, radius: 2).fill()

            case .marginalia:
                circlePath(center: NSPoint(x: center.x - 1.5, y: center.y - 1.5), radius: 4.5).fill()
                let penStroke = NSBezierPath()
                penStroke.move(to: NSPoint(x: center.x + 2.8, y: center.y + 3))
                penStroke.curve(
                    to: NSPoint(x: center.x + 7.5, y: center.y + 7.2),
                    controlPoint1: NSPoint(x: center.x + 4.5, y: center.y + 5.4),
                    controlPoint2: NSPoint(x: center.x + 6, y: center.y + 6.4)
                )
                penStroke.lineWidth = 1.6
                penStroke.lineCapStyle = .round
                penStroke.stroke()
            }
            return true
        }
        image.isTemplate = true
        return image
    }

    private static func circlePath(center: NSPoint, radius: CGFloat) -> NSBezierPath {
        NSBezierPath(ovalIn: NSRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2))
    }
}
