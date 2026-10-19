// Renders Lumen's app icon at every size AppIcon.appiconset uses.
//
//   swift tools/app-icon/render-app-icon.swift <output-directory>
//
// The icon is the default skin (Marginalia) in its listening state: an ink
// dot with two fading aura rings on a paper-lilac macOS squircle. Drawn with
// CoreGraphics so it can be regenerated without a design tool.

import AppKit
import CoreGraphics
import Foundation

let outputPixelSizes = [16, 32, 64, 128, 256, 512, 1024]

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

    // Apple's macOS icon grid: the squircle sits inside a 10 % margin.
    let gridInset = side * 0.10
    let squircleRect = CGRect(x: gridInset, y: gridInset, width: side - gridInset * 2, height: side - gridInset * 2)
    let cornerRadius = squircleRect.width * 0.224
    let squirclePath = CGPath(roundedRect: squircleRect, cornerWidth: cornerRadius, cornerHeight: cornerRadius, transform: nil)

    // Soft drop shadow under the squircle.
    context.saveGState()
    context.setShadow(offset: CGSize(width: 0, height: -side * 0.01), blur: side * 0.025, color: CGColor(srgbRed: 0.1, green: 0.08, blue: 0.2, alpha: 0.35))
    context.addPath(squirclePath)
    context.setFillColor(CGColor(srgbRed: 0.86, green: 0.85, blue: 0.93, alpha: 1))
    context.fillPath()
    context.restoreGState()

    // Paper-lilac vertical gradient #DCD8EC (top) → #CFD0E6 (bottom).
    context.saveGState()
    context.addPath(squirclePath)
    context.clip()
    let paperGradient = CGGradient(
        colorsSpace: CGColorSpace(name: CGColorSpace.sRGB),
        colors: [
            CGColor(srgbRed: 0xDC / 255, green: 0xD8 / 255, blue: 0xEC / 255, alpha: 1),
            CGColor(srgbRed: 0xCF / 255, green: 0xD0 / 255, blue: 0xE6 / 255, alpha: 1),
        ] as CFArray,
        locations: [0, 1]
    )!
    context.drawLinearGradient(paperGradient, start: CGPoint(x: 0, y: squircleRect.maxY), end: CGPoint(x: 0, y: squircleRect.minY), options: [])
    context.restoreGState()

    // Ink dot (#1B1535) at 18 % of the size, with two aura rings.
    let center = CGPoint(x: side / 2, y: side / 2)
    let dotRadius = side * 0.09
    let ringStrokeWidth = max(side * 0.016, 1)
    let auraRings: [(radiusMultiplier: CGFloat, opacity: CGFloat)] = [(1.8, 0.6), (2.6, 0.25)]
    for auraRing in auraRings {
        let ringRadius = dotRadius * auraRing.radiusMultiplier
        context.setStrokeColor(CGColor(srgbRed: 0x1B / 255, green: 0x15 / 255, blue: 0x35 / 255, alpha: auraRing.opacity))
        context.setLineWidth(ringStrokeWidth)
        context.strokeEllipse(in: CGRect(x: center.x - ringRadius, y: center.y - ringRadius, width: ringRadius * 2, height: ringRadius * 2))
    }
    context.setFillColor(CGColor(srgbRed: 0x1B / 255, green: 0x15 / 255, blue: 0x35 / 255, alpha: 1))
    context.fillEllipse(in: CGRect(x: center.x - dotRadius, y: center.y - dotRadius, width: dotRadius * 2, height: dotRadius * 2))

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
