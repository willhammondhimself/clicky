//
//  PointingGroundingRequest.swift
//  leanring-buddy
//
//  The question Lumen asks a second, small vision model to find the exact
//  spot to point at, and how its answer is read. The chat model's [POINT]
//  coordinates are often off: on ScreenSpot-v2 (247 macOS + web screenshots
//  at Lumen's 1280 px size) qwen3-vl:4b-instruct hit 86% of targets with the
//  prompt below vs gemma4:26b's 66%. It runs only after speech has started
//  (sharing the GPU with the chat model nearly doubled the reply time), so
//  the companion flies to the chat model's point first and moves when this
//  answer arrives.
//

import CoreGraphics
import Foundation

nonisolated enum PointingGroundingRequest {
    /// The benchmarked grounding model, pulled from Ollama at launch.
    static let modelName = "qwen3-vl:4b-instruct"
    static let requiredModels = [modelName]

    /// Verbatim from the benchmark; changing it invalidates the 86%.
    static let systemPrompt = "You locate user interface elements in a screenshot. Reply with only [POINT:x,y] where x,y are integers on a 0-1000 grid over the image: 0,0 is the top-left corner, 1000,1000 the bottom-right."

    static func userText(forLabel elementLabel: String) -> String {
        "point at the element for: " + elementLabel.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// The chat model's `[POINT]` label is the only description of the
    /// target the grounding model gets, so an empty one or "none" is not
    /// worth a request.
    static func isGroundableLabel(_ elementLabel: String?) -> Bool {
        guard let trimmedLabel = elementLabel?.trimmingCharacters(in: .whitespacesAndNewlines),
              !trimmedLabel.isEmpty else { return false }
        return trimmedLabel.lowercased() != "none"
    }

    /// How far past 0...1000 a coordinate may be and still count as a point
    /// at the screen's edge (5% of the grid). Further out is most likely a
    /// pixel coordinate, which clamping would turn into a confident point at
    /// the wrong edge, so it is rejected instead.
    static let gridOvershootTolerance: CGFloat = 50

    /// The grid point in "[POINT:x,y]" (anywhere in the reply, an optional
    /// ":label" after it is ignored) or a reply that is only "x,y" (optionally
    /// in parentheses). Decimals are accepted. Nil for anything else or for a
    /// point too far off the grid.
    static func gridPoint(fromModelReply modelReply: String) -> CGPoint? {
        let trimmedReply = modelReply.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedReply.isEmpty else { return nil }

        let numberPattern = #"(-?\d+(?:\.\d+)?)"#
        let pointTagPattern = #"\[POINT:\s*"# + numberPattern + #"\s*,\s*"# + numberPattern + #"\s*(?::[^\]]*)?\]"#
        let barePairPattern = #"^\(?\s*"# + numberPattern + #"\s*,\s*"# + numberPattern + #"\s*\)?$"#

        guard let coordinateStrings = firstCoordinatePair(matching: pointTagPattern, in: trimmedReply)
                ?? firstCoordinatePair(matching: barePairPattern, in: trimmedReply),
              let gridX = Double(coordinateStrings.x),
              let gridY = Double(coordinateStrings.y) else { return nil }

        let allowedRange = -gridOvershootTolerance...(PointingGeometry.pointingGridSize + gridOvershootTolerance)
        guard allowedRange.contains(CGFloat(gridX)), allowedRange.contains(CGFloat(gridY)) else { return nil }

        return CGPoint(
            x: min(max(CGFloat(gridX), 0), PointingGeometry.pointingGridSize),
            y: min(max(CGFloat(gridY), 0), PointingGeometry.pointingGridSize)
        )
    }

    private static func firstCoordinatePair(matching pattern: String, in text: String) -> (x: String, y: String)? {
        guard let regularExpression = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]),
              let match = regularExpression.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              let xRange = Range(match.range(at: 1), in: text),
              let yRange = Range(match.range(at: 2), in: text) else { return nil }
        return (String(text[xRange]), String(text[yRange]))
    }
}
