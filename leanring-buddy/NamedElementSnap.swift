//
//  NamedElementSnap.swift
//  leanring-buddy
//
//  The model's point is often near the right control but just off it (on a
//  test screen, gemma4:26b landed 8-26 px from the buttons it named). Its
//  [POINT] label still says what it meant, so Lumen looks at the elements
//  within 80 points of the point and snaps to the one whose name matches
//  the label ("resign button" → the "Resign" button).
//  AccessibilityElementBoundsResolver gathers the nearby elements; this file
//  only decides, so it can be unit-tested.
//

import CoreGraphics

nonisolated struct LabeledElementCandidate: Equatable {
    /// The element's title, description or value as Accessibility reports it.
    let label: String
    let frameInAppKitGlobal: CGRect
    /// 0 when the point is inside the element.
    let distanceFromPoint: CGFloat
}

nonisolated enum NamedElementSnap {
    static let maximumSnapDistance: CGFloat = 80
    static let minimumLabelMatchScore = 0.5
    /// Spacing of the 5×5 grid of hit tests around the point, reaching
    /// `maximumSnapDistance` in each direction.
    static let sampleSpacing: CGFloat = 40

    /// Words that describe what kind of control it is rather than which one.
    private static let fillerWords: Set<String> = [
        "a", "an", "the", "my", "your", "this", "that", "to", "of", "on", "in", "for",
        "button", "buttons", "icon", "menu", "item", "items", "link", "tab", "field", "bar", "box", "area",
    ]

    /// Share of the pointing label's meaningful words found in the element's
    /// label, 0 ... 1.
    static func labelMatchScore(pointingLabel: String, elementLabel: String) -> Double {
        let meaningfulPointingWords = Set(words(in: pointingLabel)).subtracting(fillerWords)
        guard !meaningfulPointingWords.isEmpty else { return 0 }
        let elementWords = Set(words(in: elementLabel))
        let matchedWordCount = meaningfulPointingWords.filter { elementWords.contains($0) }.count
        return Double(matchedWordCount) / Double(meaningfulPointingWords.count)
    }

    /// The best-matching element within reach: highest label match, then
    /// nearest. Nil when nothing matches at least half the label.
    static func chooseElement(pointingLabel: String?, candidates: [LabeledElementCandidate]) -> LabeledElementCandidate? {
        guard let pointingLabel,
              pointingLabel.trimmingCharacters(in: .whitespaces).lowercased() != "none" else { return nil }

        let scoredCandidates = candidates
            .filter { $0.distanceFromPoint <= maximumSnapDistance }
            .map { (candidate: $0, score: labelMatchScore(pointingLabel: pointingLabel, elementLabel: $0.label)) }
            .filter { $0.score >= minimumLabelMatchScore }

        return scoredCandidates.min { first, second in
            if first.score != second.score { return first.score > second.score }
            return first.candidate.distanceFromPoint < second.candidate.distanceFromPoint
        }?.candidate
    }

    /// The point itself first, then a 5×5 grid around it.
    static func samplePoints(around point: CGPoint) -> [CGPoint] {
        let offsets: [CGFloat] = [0, -sampleSpacing, sampleSpacing, -2 * sampleSpacing, 2 * sampleSpacing]
        var samplePoints: [CGPoint] = []
        for yOffset in offsets {
            for xOffset in offsets {
                samplePoints.append(CGPoint(x: point.x + xOffset, y: point.y + yOffset))
            }
        }
        return samplePoints
    }

    static func distance(from point: CGPoint, to frame: CGRect) -> CGFloat {
        let horizontalGap = max(frame.minX - point.x, 0, point.x - frame.maxX)
        let verticalGap = max(frame.minY - point.y, 0, point.y - frame.maxY)
        return (horizontalGap * horizontalGap + verticalGap * verticalGap).squareRoot()
    }

    private static func words(in text: String) -> [String] {
        text.lowercased()
            .split(whereSeparator: { !$0.isLetter && !$0.isNumber })
            .map(String.init)
    }
}
