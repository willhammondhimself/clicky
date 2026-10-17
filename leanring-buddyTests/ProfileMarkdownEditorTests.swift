import Foundation
import Testing

#if canImport(leanring_buddy)
@testable import leanring_buddy
#else
@testable import ClickyLogic
#endif

struct ProfileMarkdownEditorTests {

    private let sampleProfile = """
    <!-- comment -->

    # Profile

    ## About me
    - studies physics

    ## Tools
    - uses xcode
    - uses ollama

    ## Notes

    """

    @Test func starterContainsTheFiveHeadingsInOrder() {
        let starter = ProfileMarkdownEditor.starterMarkdown()
        let headingPositions = ProfileSection.allCases.map { section in
            starter.range(of: section.heading)?.lowerBound
        }
        #expect(headingPositions.allSatisfy { $0 != nil })
        let orderedPositions = headingPositions.compactMap { $0 }
        #expect(orderedPositions == orderedPositions.sorted())
        #expect(starter.hasPrefix("<!--"))
    }

    @Test func appendsAfterTheLastBulletOfTheSection() {
        let updated = ProfileMarkdownEditor.appendingFact("uses zed", underSection: .tools, to: sampleProfile)
        #expect(updated.contains("- uses ollama\n- uses zed\n\n## Notes"))
        #expect(ProfileMarkdownEditor.factLines(in: updated) == ["studies physics", "uses xcode", "uses ollama", "uses zed"])
    }

    @Test func appendsUnderAnEmptyTrailingSection() {
        let updated = ProfileMarkdownEditor.appendingFact("ships friday", underSection: .notes, to: sampleProfile)
        #expect(updated.hasSuffix("## Notes\n- ships friday\n"))
    }

    @Test func createsAMissingSectionAtTheEnd() {
        let updated = ProfileMarkdownEditor.appendingFact("likes tea", underSection: .preferences, to: sampleProfile)
        #expect(updated.hasSuffix("## Preferences\n- likes tea\n"))
        #expect(ProfileMarkdownEditor.factLines(in: updated).contains("likes tea"))
    }

    @Test func exactDuplicateIsANoOp() {
        let updated = ProfileMarkdownEditor.appendingFact("uses xcode", underSection: .notes, to: sampleProfile)
        #expect(updated == sampleProfile)
    }

    @Test func unknownHeadingMapsToNotesAndKnownOnesMatchCaseInsensitively() {
        #expect(ProfileSection(matchingHeading: "gadgets") == .notes)
        #expect(ProfileSection(matchingHeading: "") == .notes)
        #expect(ProfileSection(matchingHeading: " about ME ") == .aboutMe)
        #expect(ProfileSection(matchingHeading: "Tools") == .tools)
    }

    @Test func removesOnlyAMatchingBulletLine() {
        let updated = ProfileMarkdownEditor.removingFactLine("uses xcode", from: sampleProfile)
        #expect(updated?.contains("uses xcode") == false)
        #expect(updated?.contains("- uses ollama") == true)
        #expect(ProfileMarkdownEditor.removingFactLine("Tools", from: sampleProfile) == nil)
        #expect(ProfileMarkdownEditor.removingFactLine("Profile", from: sampleProfile) == nil)
        #expect(ProfileMarkdownEditor.removingFactLine("not there", from: sampleProfile) == nil)
    }

    @Test func countsOnlyRealFactLines() {
        #expect(ProfileMarkdownEditor.factLineCount(in: sampleProfile) == 3)
        #expect(ProfileMarkdownEditor.factLineCount(in: sampleProfile + "\n- \n-\n") == 3)
        #expect(ProfileMarkdownEditor.factLineCount(in: ProfileMarkdownEditor.starterMarkdown()) > 0)
    }

    @Test func promptTextDropsTheCommentAndEmptyBullets() {
        let promptText = ProfileMarkdownEditor.textForPrompt(from: sampleProfile + "\n- \n")
        #expect(!promptText.contains("<!--"))
        #expect(!promptText.contains("- \n"))
        #expect(promptText.contains("## Tools\n- uses xcode\n- uses ollama"))
        #expect(!promptText.hasPrefix("\n"))
    }

    @Test func appendThenRemoveRestoresTheOriginal() {
        let appended = ProfileMarkdownEditor.appendingFact("uses zed", underSection: .tools, to: sampleProfile)
        let restored = ProfileMarkdownEditor.removingFactLine("uses zed", from: appended)
        #expect(restored == sampleProfile)
    }
}
