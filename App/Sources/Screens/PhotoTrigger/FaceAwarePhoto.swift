import MiraNoteKit
import SwiftUI

/// A story photo filling whatever frame it is given -- the whole screen in
/// the story, a grid cell on the ending card -- cropped so no face is cut
/// (`FacePreservingCrop`). Where the photo is shown whole, the paper shows
/// around it.
///
/// `whole`: full screen in the story, a landscape or square photo is shown
/// whole over a blurred, darkened fill of itself instead (decisions 10-24);
/// it fades back to a fill as the photo lands in its cell.
struct FaceAwarePhoto: View {
    let photo: StoryPhoto
    var whole = false

    /// The prototype's `blur(22px) brightness(.88)`, overhanging the frame
    /// so the blur has no pale edge.
    private static let blur: CGFloat = 22
    private static let overhang: CGFloat = 48

    var body: some View {
        GeometryReader { proxy in
            let faces = whole ? FacePreservingCrop.Faces.unknown : photo.faces
            let frame = FacePreservingCrop.frame(imageSize: photo.image.size, faces: faces, in: proxy.size)
            ZStack(alignment: .topLeading) {
                if whole {
                    Image(uiImage: photo.image)
                        .resizable()
                        .scaledToFill()
                        .frame(width: proxy.size.width + Self.overhang, height: proxy.size.height + Self.overhang)
                        .blur(radius: Self.blur)
                        .brightness(-0.12)
                        .position(x: proxy.size.width / 2, y: proxy.size.height / 2)
                        .transition(.opacity)
                }
                Image(uiImage: photo.image)
                    .resizable()
                    .frame(width: frame.width, height: frame.height)
                    .position(x: frame.midX, y: frame.midY)
            }
            .animation(.easeInOut(duration: 0.4), value: whole)
        }
        .clipped()
        .accessibilityHidden(true)
    }
}
