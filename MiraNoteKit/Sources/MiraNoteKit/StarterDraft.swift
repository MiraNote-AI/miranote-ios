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
