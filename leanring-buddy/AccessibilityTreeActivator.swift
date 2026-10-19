//
//  AccessibilityTreeActivator.swift
//  leanring-buddy
//
//  Gets apps' Accessibility trees ready before the user asks, so pointing
//  can hug real elements. An Electron app needs ~1-2 s to build its tree
//  after "AXManualAccessibility" is set, too slow to do at pointing time, so
//  the request goes out whenever an app comes to the front. Chromium
//  browsers reject that attribute but switch their tree on once they see an
//  Accessibility query, so every activated app also gets one cheap read.
//  "AXEnhancedUserInterface" is never set: it disturbs window animations and
//  window managers. Accessibility IPC never runs on the main actor.
//

import AppKit
import ApplicationServices

final class AccessibilityTreeActivator {
    private nonisolated static let messagingTimeoutSeconds: Float = 0.15
    private nonisolated static let manualAccessibilityAttributeName = "AXManualAccessibility"

    private var isElectronAppByBundlePath: [String: Bool] = [:]
    /// Each process is asked once; a pid is forgotten when its app quits so
    /// a reused pid gets asked again.
    private var processIdentifiersAlreadyAskedForTree: Set<pid_t> = []
    private var applicationActivationObserver: NSObjectProtocol?
    private var applicationTerminationObserver: NSObjectProtocol?

    func start() {
        guard applicationActivationObserver == nil else { return }
        let workspaceNotificationCenter = NSWorkspace.shared.notificationCenter

        applicationActivationObserver = workspaceNotificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] activationNotification in
            let activatedApplication = activationNotification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
            MainActor.assumeIsolated {
                guard let activatedApplication else { return }
                self?.prepareAccessibilityTree(of: activatedApplication)
            }
        }

        applicationTerminationObserver = workspaceNotificationCenter.addObserver(
            forName: NSWorkspace.didTerminateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] terminationNotification in
            let terminatedApplication = terminationNotification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
            MainActor.assumeIsolated {
                guard let terminatedApplication else { return }
                self?.processIdentifiersAlreadyAskedForTree.remove(terminatedApplication.processIdentifier)
            }
        }

        // The app already in front when Lumen launches never posts an
        // activation, but the user may ask about it first.
        if let frontmostApplication = NSWorkspace.shared.frontmostApplication {
            prepareAccessibilityTree(of: frontmostApplication)
        }
    }

    private func prepareAccessibilityTree(of activatedApplication: NSRunningApplication) {
        let activatedProcessIdentifier = activatedApplication.processIdentifier
        guard activatedProcessIdentifier != getpid(), activatedProcessIdentifier > 0 else { return }

        let shouldSetManualAccessibility = AccessibilityTreeActivation.shouldRequestAccessibilityTree(
            bundleIdentifier: activatedApplication.bundleIdentifier,
            isElectronApp: isElectronApp(activatedApplication)
        ) && !processIdentifiersAlreadyAskedForTree.contains(activatedProcessIdentifier)
        if shouldSetManualAccessibility {
            processIdentifiersAlreadyAskedForTree.insert(activatedProcessIdentifier)
        }
        let applicationName = activatedApplication.localizedName ?? activatedApplication.bundleIdentifier ?? "pid \(activatedProcessIdentifier)"

        Task {
            let manualAccessibilityResult = await Task.detached(priority: .utility) {
                Self.askApplicationForAccessibilityTree(
                    processIdentifier: activatedProcessIdentifier,
                    shouldSetManualAccessibility: shouldSetManualAccessibility
                )
            }.value

            guard let manualAccessibilityResult else { return }
            print("♿️ Asked \(applicationName) to build its accessibility tree (\(Self.describe(manualAccessibilityResult)))")
            // Without the Accessibility permission (or if the app was still
            // launching) the request fails; forgetting the pid lets the
            // next activation try again.
            if manualAccessibilityResult != .success {
                processIdentifiersAlreadyAskedForTree.remove(activatedProcessIdentifier)
            }
        }
    }

    /// Electron apps embed "Electron Framework.framework". The check touches
    /// the disk, so its answer is kept per bundle path.
    private func isElectronApp(_ runningApplication: NSRunningApplication) -> Bool {
        guard let bundleURL = runningApplication.bundleURL else { return false }
        let bundlePath = bundleURL.path
        if let cachedAnswer = isElectronAppByBundlePath[bundlePath] {
            return cachedAnswer
        }
        let electronFrameworkPath = bundleURL
            .appendingPathComponent("Contents/Frameworks/Electron Framework.framework")
            .path
        let isElectron = FileManager.default.fileExists(atPath: electronFrameworkPath)
        isElectronAppByBundlePath[bundlePath] = isElectron
        return isElectron
    }

    /// Runs off the main actor. Returns the result of setting
    /// "AXManualAccessibility", or nil when it wasn't set.
    private nonisolated static func askApplicationForAccessibilityTree(
        processIdentifier: pid_t,
        shouldSetManualAccessibility: Bool
    ) -> AXError? {
        let applicationElement = AXUIElementCreateApplication(processIdentifier)
        AXUIElementSetMessagingTimeout(applicationElement, messagingTimeoutSeconds)

        var manualAccessibilityResult: AXError?
        if shouldSetManualAccessibility {
            manualAccessibilityResult = AXUIElementSetAttributeValue(
                applicationElement,
                manualAccessibilityAttributeName as CFString,
                kCFBooleanTrue
            )
        }

        // The value is thrown away; the query itself is what makes Chromium
        // turn its tree on.
        var focusedWindowValue: CFTypeRef?
        _ = AXUIElementCopyAttributeValue(applicationElement, kAXFocusedWindowAttribute as CFString, &focusedWindowValue)

        return manualAccessibilityResult
    }

    private static func describe(_ accessibilityResult: AXError) -> String {
        accessibilityResult == .success ? "ok" : "AXError \(accessibilityResult.rawValue)"
    }
}
