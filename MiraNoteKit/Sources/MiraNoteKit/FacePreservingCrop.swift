import CoreGraphics

/// Where to draw a photo so it fills a frame without cutting off a face.
/// Fill (aspect-fill) slides the overflow so the faces sit as near the
/// middle as the image allows; when the faces cannot all fit, or nobody knows
/// where they are, the whole photo is shown instead (aspect-fit) -- a margin
/// is better than a cut face.
public enum FacePreservingCrop {
    public enum Faces: Equatable, Sendable {
        /// Detection ran and found no one: a centered fill.
        case none
        /// The union of every face, in unit coordinates with a top-left origin.
        case found(CGRect)
        /// Detection failed: fit, since a face may be anywhere.
        case unknown
    }

    /// Full screen in the story, a landscape or square photo is shown whole
    /// over a blurred fill of itself and only a portrait one fills
    /// (decisions 10-24; the prototype's 0.8 width-to-height line).
    public static func showsWhole(imageSize: CGSize) -> Bool {
        imageSize.height > 0 && imageSize.width / imageSize.height >= 0.8
    }

    /// Breathing room kept around the faces, as a fraction of their size.
    static let margin: CGFloat = 0.15

    /// The image's frame in the container's coordinates. It may overhang the
    /// container (fill) or leave margins (fit); the caller clips.
    public static func frame(imageSize: CGSize, faces: Faces, in container: CGSize) -> CGRect {
        guard imageSize.width > 0, imageSize.height > 0, container.width > 0, container.height > 0 else {
            return CGRect(origin: .zero, size: container)
        }
        let fill = max(container.width / imageSize.width, container.height / imageSize.height)
        let drawn = CGSize(width: imageSize.width * fill, height: imageSize.height * fill)

        switch faces {
        case .unknown:
            return fit(imageSize, in: container)
        case .none:
            return CGRect(x: (container.width - drawn.width) / 2, y: (container.height - drawn.height) / 2,
                          width: drawn.width, height: drawn.height)
        case .found(let unit):
            let face = CGRect(x: unit.minX * drawn.width, y: unit.minY * drawn.height,
                              width: unit.width * drawn.width, height: unit.height * drawn.height)
                .insetBy(dx: -unit.width * drawn.width * margin, dy: -unit.height * drawn.height * margin)
            if face.width > container.width || face.height > container.height {
                return fit(imageSize, in: container)
            }
            // Centre the faces, then pull back so the image still covers the
            // frame. A face no wider than the frame stays whole either way.
            let left = clamp(container.width / 2 - face.midX, lower: container.width - drawn.width, upper: 0)
            let top = clamp(container.height / 2 - face.midY, lower: container.height - drawn.height, upper: 0)
            return CGRect(x: left, y: top, width: drawn.width, height: drawn.height)
        }
    }

    private static func fit(_ image: CGSize, in container: CGSize) -> CGRect {
        let scale = min(container.width / image.width, container.height / image.height)
        let size = CGSize(width: image.width * scale, height: image.height * scale)
        return CGRect(x: (container.width - size.width) / 2, y: (container.height - size.height) / 2,
                      width: size.width, height: size.height)
    }

    private static func clamp(_ value: CGFloat, lower: CGFloat, upper: CGFloat) -> CGFloat {
        min(max(value, lower), upper)
    }
}
