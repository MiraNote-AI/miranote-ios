import SwiftUI
import UIKit

/// A small square of one of the user's photos, read from the library when
/// it shows. It lives in memory only: never written to a file, never
/// exported. A photo that is gone (or still in iCloud) stays a blank tile.
struct TriggerThumb: View {
    let photos: TriggerPhotoProviding
    let id: String
    var side: CGFloat = 52
    @State private var image: UIImage?

    var body: some View {
        RoundedRectangle(cornerRadius: 8)
            .fill(Palette.hairline)
            .frame(width: side, height: side)
            .overlay {
                if let image {
                    Image(uiImage: image).resizable().scaledToFill()
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .task(id: id) {
                image = await photos.image(for: id, maxPixel: 160, allowNetwork: false)
            }
            .accessibilityHidden(true)
    }
}

/// A wrapping strip of thumbnails; the rest is a count.
struct TriggerThumbStrip: View {
    let photos: TriggerPhotoProviding
    let ids: [String]
    var limit = 8

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(Array(ids.prefix(limit).enumerated()), id: \.offset) { _, id in
                    TriggerThumb(photos: photos, id: id)
                }
                if ids.count > limit {
                    Text(verbatim: "+\(ids.count - limit)")
                        .font(.miraCaption)
                        .foregroundStyle(Palette.textSecondary)
                        .padding(.leading, 4)
                }
            }
        }
    }
}
