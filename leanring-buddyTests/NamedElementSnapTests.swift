import CoreGraphics
import Testing

#if canImport(leanring_buddy)
@testable import leanring_buddy
#else
@testable import LumenLogic
#endif

struct NamedElementSnapTests {

    // MARK: - Label matching

    @Test func fillerWordsDoNotCount() {
        #expect(NamedElementSnap.labelMatchScore(pointingLabel: "resign button", elementLabel: "Resign") == 1)
        #expect(NamedElementSnap.labelMatchScore(pointingLabel: "the settings icon", elementLabel: "Settings") == 1)
    }

    @Test func partialMatchesScoreTheShareOfMeaningfulWordsFound() {
        #expect(NamedElementSnap.labelMatchScore(pointingLabel: "offer draw", elementLabel: "½ Draw") == 0.5)
    }

    @Test func unrelatedOrEmptyLabelsScoreZero() {
        #expect(NamedElementSnap.labelMatchScore(pointingLabel: "resign button", elementLabel: "New Game") == 0)
        #expect(NamedElementSnap.labelMatchScore(pointingLabel: "resign button", elementLabel: "") == 0)
        #expect(NamedElementSnap.labelMatchScore(pointingLabel: "button", elementLabel: "Resign") == 0)
    }

    @Test func matchingIgnoresCaseAndPunctuation() {
        #expect(NamedElementSnap.labelMatchScore(pointingLabel: "New-Game", elementLabel: "new game") == 1)
    }

    // MARK: - Choosing a nearby element

    private func candidate(_ label: String, _ frame: CGRect, distance: CGFloat) -> LabeledElementCandidate {
        LabeledElementCandidate(label: label, frameInAppKitGlobal: frame, distanceFromPoint: distance)
    }

    @Test func snapsToTheMatchingButtonTheModelJustMissed() {
        // gemma4:26b's points landed ~20-40 px below the Resign button.
        let resign = candidate("Resign", CGRect(x: 850, y: 200, width: 110, height: 36), distance: 26)
        let moveList = candidate("1. e4 e5", CGRect(x: 850, y: 300, width: 370, height: 300), distance: 0)
        let chosen = NamedElementSnap.chooseElement(pointingLabel: "resign button", candidates: [moveList, resign])
        #expect(chosen == resign)
    }

    @Test func prefersTheBetterMatchThenTheNearer() {
        let draw = candidate("½ Draw", CGRect(x: 0, y: 0, width: 10, height: 10), distance: 5)
        let offerDraw = candidate("Offer draw", CGRect(x: 20, y: 0, width: 10, height: 10), distance: 40)
        #expect(NamedElementSnap.chooseElement(pointingLabel: "offer draw", candidates: [draw, offerDraw]) == offerDraw)

        let nearSave = candidate("Save", CGRect(x: 0, y: 0, width: 10, height: 10), distance: 10)
        let farSave = candidate("Save", CGRect(x: 50, y: 0, width: 10, height: 10), distance: 60)
        #expect(NamedElementSnap.chooseElement(pointingLabel: "save button", candidates: [farSave, nearSave]) == nearSave)
    }

    @Test func ignoresMatchesBeyondEightyPointsOrBelowHalfAMatch() {
        let farResign = candidate("Resign", CGRect(x: 0, y: 0, width: 10, height: 10), distance: 81)
        let weakMatch = candidate("Draw", CGRect(x: 0, y: 0, width: 10, height: 10), distance: 5)
        #expect(NamedElementSnap.chooseElement(pointingLabel: "resign button", candidates: [farResign]) == nil)
        #expect(NamedElementSnap.chooseElement(pointingLabel: "offer a draw now", candidates: [weakMatch]) == nil)
    }

    @Test func noLabelMeansNoSnap() {
        let resign = candidate("Resign", CGRect(x: 0, y: 0, width: 10, height: 10), distance: 0)
        #expect(NamedElementSnap.chooseElement(pointingLabel: nil, candidates: [resign]) == nil)
        #expect(NamedElementSnap.chooseElement(pointingLabel: "none", candidates: [resign]) == nil)
    }

    // MARK: - Where to look

    @Test func samplePointsCoverAGridOutToEightyPoints() {
        let samplePoints = NamedElementSnap.samplePoints(around: CGPoint(x: 100, y: 100))
        #expect(samplePoints.count == 25)
        #expect(samplePoints.first == CGPoint(x: 100, y: 100))
        #expect(samplePoints.contains(CGPoint(x: 20, y: 180)))
        #expect(samplePoints.contains(CGPoint(x: 180, y: 20)))
    }

    @Test func distanceIsZeroInsideAFrameAndToTheNearestEdgeOutside() {
        let frame = CGRect(x: 0, y: 0, width: 100, height: 50)
        #expect(NamedElementSnap.distance(from: CGPoint(x: 10, y: 10), to: frame) == 0)
        #expect(NamedElementSnap.distance(from: CGPoint(x: 130, y: 90), to: frame) == 50)
    }
}
