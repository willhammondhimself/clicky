//
//  SkinContrast.swift
//  leanring-buddy
//
//  WCAG 2 contrast ratio between two "#RRGGBB" colours, and the colour a glass
//  panel ends up when its tint is laid over the wallpaper (glass blurs what is
//  behind it, so an average wallpaper colour is a fair stand-in). Used by tests
//  to keep every skin's panel text readable over any wallpaper.
//

import Foundation

nonisolated enum SkinContrast {
    /// (lighter + 0.05) / (darker + 0.05), from 1 (same colour) to 21.
    static func contrastRatio(foregroundHex: String, backgroundHex: String) -> Double {
        let foregroundLuminance = relativeLuminance(ofHex: foregroundHex)
        let backgroundLuminance = relativeLuminance(ofHex: backgroundHex)
        let lighterLuminance = max(foregroundLuminance, backgroundLuminance)
        let darkerLuminance = min(foregroundLuminance, backgroundLuminance)
        return (lighterLuminance + 0.05) / (darkerLuminance + 0.05)
    }

    static func blendedHex(tintHex: String, wallpaperHex: String, tintOpacity: Double) -> String {
        let tintChannels = channelValues(ofHex: tintHex)
        let wallpaperChannels = channelValues(ofHex: wallpaperHex)
        let blendedChannels = zip(tintChannels, wallpaperChannels).map { tintChannel, wallpaperChannel in
            Int((Double(tintChannel) * tintOpacity + Double(wallpaperChannel) * (1 - tintOpacity)).rounded())
        }
        return "#" + blendedChannels.map { String(format: "%02X", $0) }.joined()
    }

    /// WCAG 2 relative luminance of an sRGB colour.
    private static func relativeLuminance(ofHex hex: String) -> Double {
        let linearChannels = channelValues(ofHex: hex).map { channel -> Double in
            let encodedChannel = Double(channel) / 255
            return encodedChannel <= 0.03928 ? encodedChannel / 12.92 : pow((encodedChannel + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * linearChannels[0] + 0.7152 * linearChannels[1] + 0.0722 * linearChannels[2]
    }

    private static func channelValues(ofHex hex: String) -> [Int] {
        let digits = Array(hex.dropFirst())
        return stride(from: 0, to: 6, by: 2).map { channelStart in
            Int(String(digits[channelStart...channelStart + 1]), radix: 16) ?? 0
        }
    }
}
