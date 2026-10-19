//
//  AccessibilityTreeActivation.swift
//  leanring-buddy
//
//  Which apps Lumen asks to build their Accessibility tree. Electron apps
//  (Claude, Slack, Discord, Notion, Obsidian…) skip building it until an
//  assistive client sets "AXManualAccessibility" on them; until then every
//  hit test returns one big scroll area and pointing falls back to a rough
//  box. Code editors built on Electron are left alone because the attribute
//  can switch them into their screen-reader-optimized mode.
//

nonisolated enum AccessibilityTreeActivation {
    /// VS Code and its forks: VS Code, VS Code Insiders, Cursor, VSCodium, Windsurf.
    static let excludedEditorBundleIdentifiers: Set<String> = [
        "com.microsoft.VSCode",
        "com.microsoft.VSCodeInsiders",
        "com.todesktop.230313mzl4w4u92",
        "com.vscodium",
        "com.exafunction.windsurf",
    ]

    /// An Electron app without a bundle identifier can't be an excluded
    /// editor, so it is asked too.
    static func shouldRequestAccessibilityTree(bundleIdentifier: String?, isElectronApp: Bool) -> Bool {
        guard isElectronApp else { return false }
        guard let bundleIdentifier else { return true }
        return !excludedEditorBundleIdentifiers.contains(bundleIdentifier)
    }
}
