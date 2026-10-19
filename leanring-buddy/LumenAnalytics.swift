//
//  LumenAnalytics.swift
//  leanring-buddy
//
//  Analytics are disabled in this fork. Upstream sent events to Farza's
//  PostHog project; this build phones home to nobody. The method names are
//  kept so call sites stay untouched and can be re-pointed at your own
//  analytics later if you ever want them.
//

import Foundation

enum LumenAnalytics {

    static func configure() {}
    static func trackAppOpened() {}
    static func trackOnboardingStarted() {}
    static func trackOnboardingReplayed() {}
    static func trackOnboardingVideoCompleted() {}
    static func trackOnboardingDemoTriggered() {}
    static func trackAllPermissionsGranted() {}
    static func trackPermissionGranted(permission: String) {}
    static func trackPushToTalkStarted() {}
    static func trackPushToTalkReleased() {}
    static func trackUserMessageSent(transcript: String) {}
    static func trackAIResponseReceived(response: String) {}
    static func trackElementPointed(elementLabel: String?) {}
    static func trackResponseError(error: String) {}
    static func trackTTSError(error: String) {}
}
