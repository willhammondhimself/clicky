// Renders Lumen's app icon at every size AppIcon.appiconset uses.
//
//   swift tools/app-icon/render-app-icon.swift <output-directory>
//
// The icon is "Glass lens" (direction F on the Lumen icon board): a
// liquid-glass lens resting over a cursor arrow on a pale blue squircle.
// Drawn with CoreGraphics in the board's 1024-unit SVG coordinates (origin
// top-left), so it can be regenerated without a design tool.

import AppKit
import CoreGraphics
import Foundation

let outputPixelSizes = [16, 32, 64, 128, 256, 512, 1024]

func sRGBColor(hex: UInt32, alpha: CGFloat = 1) -> CGColor {
    CGColor(
        srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
        green: CGFloat((hex >> 8) & 0xFF) / 255,
        blue: CGFloat(hex & 0xFF) / 255,
        alpha: alpha
    )
}

func renderIcon(pixelSize: Int) -> CGImage? {
    let side = CGFloat(pixelSize)
    guard let context = CGContext(
        data: nil,
        width: pixelSize,
        height: pixelSize,
        bitsPerComponent: 8,
        bytesPerRow: 0,
        space: CGColorSpace(name: CGColorSpace.sRGB)!,
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    ) else { return nil }

    // Work in the board's 1024-unit space with y pointing down.
    context.translateBy(x: 0, y: side)
    context.scaleBy(x: side / 1024, y: -side / 1024)

    // Apple's macOS icon grid: an 824-unit squircle inside the 1024 canvas.
    let squircleRect = CGRect(x: 100, y: 100, width: 824, height: 824)
    let squirclePath = CGPath(roundedRect: squircleRect, cornerWidth: 185, cornerHeight: 185, transform: nil)

    // Soft drop shadow under the squircle (y-down space, so +y is downward).
    context.saveGState()
    context.setShadow(offset: CGSize(width: 0, height: -10 * side / 1024), blur: 26 * side / 1024, color: sRGBColor(hex: 0x1A2A44, alpha: 0.35))
    context.addPath(squirclePath)
    context.setFillColor(sRGBColor(hex: 0xC3D4EA))
    context.fillPath()
    context.restoreGState()

    // Pale blue diagonal gradient #E6EEF8 (top-left) → #9FBADB (bottom-right).
    context.saveGState()
    context.addPath(squirclePath)
    context.clip()
    let backgroundGradient = CGGradient(
        colorsSpace: CGColorSpace(name: CGColorSpace.sRGB),
        colors: [sRGBColor(hex: 0xE6EEF8), sRGBColor(hex: 0x9FBADB)] as CFArray,
        locations: [0, 1]
    )!
    context.drawLinearGradient(backgroundGradient, start: CGPoint(x: 100, y: 100), end: CGPoint(x: 924, y: 924), options: [])
    context.restoreGState()

    // Cursor arrow: ink fill with a white outline.
    let arrowPath = CGMutablePath()
    arrowPath.addLines(between: [
        CGPoint(x: 360, y: 280), CGPoint(x: 360, y: 700), CGPoint(x: 460, y: 604), CGPoint(x: 540, y: 768),
        CGPoint(x: 616, y: 734), CGPoint(x: 536, y: 574), CGPoint(x: 676, y: 574),
    ])
    arrowPath.closeSubpath()
    context.addPath(arrowPath)
    context.setFillColor(sRGBColor(hex: 0x1A1D1C))
    context.setStrokeColor(sRGBColor(hex: 0xFFFFFF))
    context.setLineWidth(18)
    context.setLineJoin(.round)
    context.drawPath(using: .fillStroke)

    // The glass lens: a translucent white disc with a bright rim.
    let lensCenter = CGPoint(x: 590, y: 560)
    let lensRadius: CGFloat = 200
    let lensRect = CGRect(x: lensCenter.x - lensRadius, y: lensCenter.y - lensRadius, width: lensRadius * 2, height: lensRadius * 2)
    context.setFillColor(sRGBColor(hex: 0xFFFFFF, alpha: 0.3))
    context.fillEllipse(in: lensRect)
    context.setStrokeColor(sRGBColor(hex: 0xFFFFFF, alpha: 0.95))
    context.setLineWidth(12)
    context.strokeEllipse(in: lensRect)

    // Specular highlight along the lens's upper-left inner edge.
    context.setStrokeColor(sRGBColor(hex: 0xFFFFFF, alpha: 0.9))
    context.setLineWidth(16)
    context.setLineCap(.round)
    context.addArc(
        center: lensCenter,
        radius: 150,
        startAngle: atan2(480 - lensCenter.y, 468 - lensCenter.x),
        endAngle: atan2(404 - lensCenter.y, 600 - lensCenter.x),
        clockwise: false
    )
    context.strokePath()

    return context.makeImage()
}

let arguments = CommandLine.arguments
guard arguments.count == 2 else {
    FileHandle.standardError.write("usage: swift render-app-icon.swift <output-directory>\n".data(using: .utf8)!)
    exit(1)
}
let outputDirectoryURL = URL(fileURLWithPath: arguments[1], isDirectory: true)
try FileManager.default.createDirectory(at: outputDirectoryURL, withIntermediateDirectories: true)

for pixelSize in outputPixelSizes {
    guard let iconImage = renderIcon(pixelSize: pixelSize) else {
        FileHandle.standardError.write("failed to render \(pixelSize)\n".data(using: .utf8)!)
        exit(1)
    }
    let bitmap = NSBitmapImageRep(cgImage: iconImage)
    let pngData = bitmap.representation(using: .png, properties: [:])!
    let fileURL = outputDirectoryURL.appendingPathComponent("\(pixelSize)-mac.png")
    try pngData.write(to: fileURL)
    print("wrote \(fileURL.path)")
}
