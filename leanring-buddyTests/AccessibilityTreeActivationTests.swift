import Testing

#if canImport(leanring_buddy)
@testable import leanring_buddy
#else
@testable import LumenLogic
#endif

struct AccessibilityTreeActivationTests {

    @Test func asksAnElectronAppLikeClaudeToBuildItsTree() {
        #expect(AccessibilityTreeActivation.shouldRequestAccessibilityTree(
            bundleIdentifier: "com.anthropic.claudefordesktop",
            isElectronApp: true
        ))
    }

    @Test func asksAnElectronAppWithoutABundleIdentifier() {
        #expect(AccessibilityTreeActivation.shouldRequestAccessibilityTree(
            bundleIdentifier: nil,
            isElectronApp: true
        ))
    }

    @Test(arguments: [
        "com.microsoft.VSCode",
        "com.microsoft.VSCodeInsiders",
        "com.todesktop.230313mzl4w4u92",
        "com.vscodium",
        "com.exafunction.windsurf",
    ])
    func neverAsksACodeEditorBecauseItCouldSwitchToScreenReaderMode(editorBundleIdentifier: String) {
        #expect(AccessibilityTreeActivation.excludedEditorBundleIdentifiers.contains(editorBundleIdentifier))
        #expect(!AccessibilityTreeActivation.shouldRequestAccessibilityTree(
            bundleIdentifier: editorBundleIdentifier,
            isElectronApp: true
        ))
    }

    @Test func neverAsksAnAppThatIsNotElectron() {
        #expect(!AccessibilityTreeActivation.shouldRequestAccessibilityTree(
            bundleIdentifier: "com.apple.Safari",
            isElectronApp: false
        ))
        #expect(!AccessibilityTreeActivation.shouldRequestAccessibilityTree(
            bundleIdentifier: nil,
            isElectronApp: false
        ))
    }
}
