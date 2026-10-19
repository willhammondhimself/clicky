import CoreGraphics
import Testing

#if canImport(leanring_buddy)
@testable import leanring_buddy
#else
@testable import LumenLogic
#endif

struct PointingGroundingRequestTests {

    // MARK: - Prompt

    @Test func usesTheBenchmarkedModelAndPromptsVerbatim() {
        // These exact strings scored 86% on ScreenSpot-v2; changing them
        // invalidates that measurement.
        #expect(PointingGroundingRequest.modelName == "qwen3-vl:4b-instruct")
        #expect(PointingGroundingRequest.systemPrompt == "You locate user interface elements in a screenshot. Reply with only [POINT:x,y] where x,y are integers on a 0-1000 grid over the image: 0,0 is the top-left corner, 1000,1000 the bottom-right.")
        #expect(PointingGroundingRequest.userText(forLabel: "save button") == "point at the element for: save button")
    }

    @Test func userTextTrimsTheLabel() {
        #expect(PointingGroundingRequest.userText(forLabel: "  search bar \n") == "point at the element for: search bar")
    }

    @Test func onlyARealLabelIsWorthGrounding() {
        #expect(PointingGroundingRequest.isGroundableLabel("color inspector"))
        #expect(!PointingGroundingRequest.isGroundableLabel(nil))
        #expect(!PointingGroundingRequest.isGroundableLabel(""))
        #expect(!PointingGroundingRequest.isGroundableLabel("   "))
        #expect(!PointingGroundingRequest.isGroundableLabel("none"))
        #expect(!PointingGroundingRequest.isGroundableLabel(" None "))
    }

    // MARK: - Reply parsing

    @Test func parsesThePointTagTheModelIsAskedFor() {
        #expect(PointingGroundingRequest.gridPoint(fromModelReply: "[POINT:512,87]") == CGPoint(x: 512, y: 87))
        #expect(PointingGroundingRequest.gridPoint(fromModelReply: "[POINT: 512 , 87 ]\n") == CGPoint(x: 512, y: 87))
        #expect(PointingGroundingRequest.gridPoint(fromModelReply: "[point:512,87]") == CGPoint(x: 512, y: 87))
    }

    @Test func parsesAPointTagWithTrailingLabelOrSurroundingWords() {
        #expect(PointingGroundingRequest.gridPoint(fromModelReply: "[POINT:859,51:color inspector]") == CGPoint(x: 859, y: 51))
        #expect(PointingGroundingRequest.gridPoint(fromModelReply: "The save button is at [POINT:120,940].") == CGPoint(x: 120, y: 940))
    }

    @Test func parsesABarePairAndDecimals() {
        #expect(PointingGroundingRequest.gridPoint(fromModelReply: "512,87") == CGPoint(x: 512, y: 87))
        #expect(PointingGroundingRequest.gridPoint(fromModelReply: " (512, 87) ") == CGPoint(x: 512, y: 87))
        #expect(PointingGroundingRequest.gridPoint(fromModelReply: "[POINT:512.5,87.25]") == CGPoint(x: 512.5, y: 87.25))
        #expect(PointingGroundingRequest.gridPoint(fromModelReply: "0.5,999.9") == CGPoint(x: 0.5, y: 999.9))
    }

    @Test func clampsSlightOvershootOntoTheGrid() {
        // Up to 5% past the edge is a model rounding at the border, not a miss.
        #expect(PointingGroundingRequest.gridPoint(fromModelReply: "[POINT:1030,-20]") == CGPoint(x: 1000, y: 0))
        #expect(PointingGroundingRequest.gridPoint(fromModelReply: "[POINT:1050,1050]") == CGPoint(x: 1000, y: 1000))
    }

    @Test func rejectsPointsFarOffTheGrid() {
        // Pixel coordinates (a 1280-wide screenshot) instead of grid ones.
        #expect(PointingGroundingRequest.gridPoint(fromModelReply: "[POINT:1180,640]") == nil)
        #expect(PointingGroundingRequest.gridPoint(fromModelReply: "[POINT:400,-60]") == nil)
        #expect(PointingGroundingRequest.gridPoint(fromModelReply: "2400,300") == nil)
    }

    @Test func garbageAndEmptyRepliesGiveNoPoint() {
        #expect(PointingGroundingRequest.gridPoint(fromModelReply: "") == nil)
        #expect(PointingGroundingRequest.gridPoint(fromModelReply: "   \n") == nil)
        #expect(PointingGroundingRequest.gridPoint(fromModelReply: "[POINT:none]") == nil)
        #expect(PointingGroundingRequest.gridPoint(fromModelReply: "I can't find that element.") == nil)
        #expect(PointingGroundingRequest.gridPoint(fromModelReply: "[POINT:512]") == nil)
        // Numbers inside prose are not a bare pair.
        #expect(PointingGroundingRequest.gridPoint(fromModelReply: "there are 3,4 buttons") == nil)
    }
}
