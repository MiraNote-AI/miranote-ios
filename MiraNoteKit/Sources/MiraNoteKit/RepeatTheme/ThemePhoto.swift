import Foundation

/// One Vision label with its confidence, as kept on a theme photo.
public struct LabelScore: Codable, Equatable, Sendable {
    public let id: String
    public let confidence: Float

    public init(id: String, confidence: Float) {
        self.id = id
        self.confidence = confidence
    }
}

/// What the repeat-theme finder keeps about one library photo: enough to
/// cluster it with the same kind of photo from other days without opening
/// the image again. Local only; nothing here leaves the phone.
public struct ThemePhoto: Codable, Equatable, Sendable {
    public let id: String
    public let takenAt: Date
    public let location: GeoPoint?
    public let labels: [LabelScore]
    public let aesthetics: Double?
    public let faces: Int
    /// True when the photo passes the theme filter.
    public let isTheme: Bool
    /// The image feature print: Float32 little-endian, unit length. Its
    /// length depends on the OS revision, so it is never assumed.
    public let print: Data
    /// The revision of the feature print algorithm that made `print`.
    public let printRevision: Int

    public init(id: String, takenAt: Date, location: GeoPoint?, labels: [LabelScore], aesthetics: Double?,
                faces: Int, isTheme: Bool, print: Data, printRevision: Int) {
        self.id = id
        self.takenAt = takenAt
        self.location = location
        self.labels = labels
        self.aesthetics = aesthetics
        self.faces = faces
        self.isTheme = isTheme
        self.print = print
        self.printRevision = printRevision
    }

    /// `print` as floats (a trailing partial float is ignored).
    public var vector: [Float] {
        let count = print.count / MemoryLayout<Float>.size
        return (0..<count).map { index in
            let start = print.startIndex + index * MemoryLayout<Float>.size
            var bits: UInt32 = 0
            for byte in 0..<MemoryLayout<UInt32>.size {
                bits |= UInt32(print[start + byte]) << UInt32(8 * byte)
            }
            return Float(bitPattern: bits)
        }
    }

    /// `raw` scaled to unit length and packed as Float32 little-endian. An
    /// all-zero vector cannot be scaled and is packed as it is.
    public static func normalized(_ raw: [Float]) -> Data {
        let length = raw.reduce(Float(0)) { $0 + $1 * $1 }.squareRoot()
        let scaled = length > 0 ? raw.map { $0 / length } : raw
        var data = Data(capacity: scaled.count * MemoryLayout<Float>.size)
        for value in scaled {
            let bits = value.bitPattern
            for byte in 0..<MemoryLayout<UInt32>.size {
                data.append(UInt8(truncatingIfNeeded: bits >> UInt32(8 * byte)))
            }
        }
        return data
    }
}
