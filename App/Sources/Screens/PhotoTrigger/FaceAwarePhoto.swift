import MiraNoteKit
import SwiftUI

/// A story photo filling whatever frame it is given -- the whole screen in
/// the story, a grid cell on the ending card -- cropped so no face is cut
/// (`FacePreservingCrop`). Where the photo is shown whole, the paper shows
/// around it.
struct FaceAwarePhoto: View {
    let photo: StoryPhoto

    var body: some View {
        GeometryReader { proxy in
            let frame = FacePreservingCrop.frame(imageSize: photo.image.size, faces: photo.faces, in: proxy.size)
            Image(uiImage: photo.image)
                .resizable()
                .frame(width: frame.width, height: frame.height)
                .position(x: frame.midX, y: frame.midY)
        }
        .clipped()
        .accessibilityHidden(true)
    }
}
