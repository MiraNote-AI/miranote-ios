import CoreGraphics
import Foundation

extension Memory {
    /// The starter draft a new memory opens with: a serif title, a caption,
    /// an image placeholder, and a body line -- real elements the user can
    /// immediately move, edit, or delete.
    public static func starterDraft(title: String = "Lunch by the river") -> [CanvasItem] {
        [
            CanvasItem(
                content: .text(TextBlock(text: title, pointSize: 30)),
                position: CGPoint(x: 150, y: 62),
                size: CGSize(width: 270, height: 60),
                zIndex: 1
            ),
            CanvasItem(
                content: .text(TextBlock(text: "June 21 - calm afternoon", pointSize: 12, colorName: "textSecondary")),
                position: CGPoint(x: 120, y: 110),
                size: CGSize(width: 200, height: 24),
                zIndex: 2
            ),
            CanvasItem(
                content: .image(ImageRef(displayName: "placeholder")),
                position: CGPoint(x: 180, y: 240),
                size: CGSize(width: 328, height: 210),
                zIndex: 3
            ),
            CanvasItem(
                content: .text(TextBlock(text: "Sunny afternoon, tiny noodle shop by the bridge", pointSize: 15)),
                position: CGPoint(x: 160, y: 400),
                size: CGSize(width: 288, height: 66),
                zIndex: 4
            )
        ]
    }
}

extension Memory {
    /// The first-run welcome page (v2.1 onboarding layer 0): a page that is
    /// itself the teacher -- poke it, move it, delete it.
    public static func welcomeDraft() -> [CanvasItem] {
        [
            CanvasItem(
                content: .text(TextBlock(text: "A little welcome", pointSize: 30)),
                position: CGPoint(x: 150, y: 62),
                size: CGSize(width: 270, height: 60),
                zIndex: 1
            ),
            CanvasItem(
                content: .text(TextBlock(
                    text: "This page is yours to poke. Tap anything to pick it up, "
                        + "drag it around, two fingers to tilt it.",
                    pointSize: 15
                )),
                position: CGPoint(x: 170, y: 150),
                size: CGSize(width: 300, height: 70),
                zIndex: 2
            ),
            CanvasItem(
                content: .text(TextBlock(
                    text: "Long-press anything for more. And the bar below the page? "
                        + "Ask Mira -- she can change, tidy, and find things.",
                    pointSize: 15
                )),
                position: CGPoint(x: 170, y: 240),
                size: CGSize(width: 300, height: 80),
                zIndex: 3
            ),
            CanvasItem(
                content: .sticker(GeneratedSticker(prompt: "hello", symbolName: "hand.wave")),
                position: CGPoint(x: 290, y: 330),
                size: CGSize(width: 80, height: 80),
                rotation: 8,
                zIndex: 4
            )
        ]
    }
}

extension Memory {
    /// Legacy pages (and chat-filed ones) carry title/body only. Opening
    /// them in the editor materializes that metadata into real canvas
    /// elements -- the v2.1 rule is "the visual title IS a text element".
    /// composedMemory round-trips them back, so nothing is lost.
    public func materializedForEditing() -> Memory {
        guard items.isEmpty, !(title.isEmpty && body.isEmpty) else { return self }
        var copy = self
        var made: [CanvasItem] = []
        var nextTop: CGFloat = 28
        if !title.isEmpty {
            let height = Memory.estimatedTextHeight(title, pointSize: 30, width: 320)
            made.append(CanvasItem(
                content: .text(TextBlock(text: title, pointSize: 30)),
                position: CGPoint(x: 180, y: nextTop + height / 2),
                size: CGSize(width: 320, height: height),
                zIndex: 1
            ))
            nextTop += height + 12
        }
        if !body.isEmpty {
            let height = Memory.estimatedTextHeight(body, pointSize: 15, width: 320)
            made.append(CanvasItem(
                content: .text(TextBlock(text: body, pointSize: 15)),
                position: CGPoint(x: 180, y: nextTop + height / 2),
                size: CGSize(width: 320, height: height),
                zIndex: 2
            ))
        }
        copy.items = made
        return copy
    }

    /// Rough, UIKit-free height estimate so materialized blocks chain into
    /// one composition. The editor re-measures against real font metrics
    /// on open (block tops are preserved), so close is good enough.
    static func estimatedTextHeight(_ text: String, pointSize: CGFloat, width: CGFloat) -> CGFloat {
        let charsPerLine = max(8, Int(width / (pointSize * 0.55)))
        let lines = text
            .split(separator: "\n", omittingEmptySubsequences: false)
            .reduce(0) { total, line in
                total + max(1, (line.count + charsPerLine - 1) / charsPerLine)
            }
        return CGFloat(lines) * pointSize * 1.35 + 20
    }
}
