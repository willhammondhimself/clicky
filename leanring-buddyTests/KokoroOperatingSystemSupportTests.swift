import Foundation
import Testing

#if canImport(leanring_buddy)
@testable import leanring_buddy
#else
@testable import LumenLogic
#endif

struct KokoroOperatingSystemSupportTests {

    private func version(_ major: Int, _ minor: Int, _ patch: Int = 0) -> OperatingSystemVersion {
        OperatingSystemVersion(majorVersion: major, minorVersion: minor, patchVersion: patch)
    }

    @Test func blocksTheTwoKnownCrashingBuilds() {
        #expect(KokoroOperatingSystemSupport.blockingReason(for: version(26, 4)) != nil)
        #expect(KokoroOperatingSystemSupport.blockingReason(for: version(26, 5, 1)) != nil)
    }

    @Test func allowsEveryOtherBuild() {
        #expect(KokoroOperatingSystemSupport.blockingReason(for: version(26, 3)) == nil)
        #expect(KokoroOperatingSystemSupport.blockingReason(for: version(26, 6)) == nil)
        #expect(KokoroOperatingSystemSupport.blockingReason(for: version(27, 0)) == nil)
        #expect(KokoroOperatingSystemSupport.blockingReason(for: version(15, 4)) == nil)
    }

    @Test func blockingReasonNamesTheBuildAndTheFix() {
        let reason = KokoroOperatingSystemSupport.blockingReason(for: version(26, 4)) ?? ""
        #expect(reason.contains("26.4"))
        #expect(reason.contains("26.6"))
    }

    @Test func version3RuntimeIsAvailableOnThisMac() {
        // The harness and the app both run on macOS 15+ in practice.
        #expect(KokoroOperatingSystemSupport.supportsVersion3Runtime() == true)
    }
}
