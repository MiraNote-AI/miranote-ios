import CoreGraphics
import Foundation

/// One element's worth of change, as Mira asked for it. Every field is
/// optional: only what changes is sent. Keys match the backend's
/// edit_page tool arguments.
public struct ElementChange: Codable, Equatable, Sendable {
    public enum Layer: String, Codable, Sendable {
        case front, back
    }

    public let handle: String
    public var x: Double?
    public var y: Double?
    public var w: Double?
    public var h: Double?
    public var pointSize: Double?
    public var color: String?
    public var layer: Layer?

    enum CodingKeys: String, CodingKey {
        case handle = "id"
        case x, y, w, h, color, layer
        case pointSize = "size"
    }

    public init(
        handle: String, x: Double? = nil, y: Double? = nil,
        w: Double? = nil, h: Double? = nil, pointSize: Double? = nil,
        color: String? = nil, layer: Layer? = nil
    ) {
        self.handle = handle
        self.x = x
        self.y = y
        self.w = w
        self.h = h
        self.pointSize = pointSize
        self.color = color
        self.layer = layer
    }
}

/// A change that survived the guards, addressed at a real item.
public struct ResolvedChange: Equatable, Sendable {
    public let id: CanvasItem.ID
    public var x: Double?
    public var y: Double?
    public var w: Double?
    public var h: Double?
    public var pointSize: CGFloat?
    public var colorName: String?
    public var layer: ElementChange.Layer?

    public init(
        id: CanvasItem.ID, x: Double? = nil, y: Double? = nil,
        w: Double? = nil, h: Double? = nil, pointSize: CGFloat? = nil,
        colorName: String? = nil, layer: ElementChange.Layer? = nil
    ) {
        self.id = id
        self.x = x
        self.y = y
        self.w = w
        self.h = h
        self.pointSize = pointSize
        self.colorName = colorName
        self.layer = layer
    }
}

/// What stands between a language model's arithmetic and the user's
/// page. Pure functions, no editor state.
public enum PageEditGuard {
    public static let pointSizeRange: ClosedRange<CGFloat> = 11...48

    /// Later calls win field by field, so a model that corrects itself
    /// mid-turn lands the correction instead of leaving two receipts and
    /// two undo steps behind.
    public static func merge(_ sets: [[ElementChange]]) -> [ElementChange] {
        var order: [String] = []
        var merged: [String: ElementChange] = [:]
        for set in sets {
            for change in set {
                guard var existing = merged[change.handle] else {
                    order.append(change.handle)
                    merged[change.handle] = change
                    continue
                }
                if let value = change.x { existing.x = value }
                if let value = change.y { existing.y = value }
                if let value = change.w { existing.w = value }
                if let value = change.h { existing.h = value }
                if let value = change.pointSize { existing.pointSize = value }
                if let value = change.color { existing.color = value }
                if let value = change.layer { existing.layer = value }
                merged[change.handle] = existing
            }
        }
        return order.compactMap { merged[$0] }
    }

    /// Drop what cannot be honoured, clamp what can. An entry whose
    /// handle names nothing is dropped whole; a bad colour costs only its
    /// own field.
    ///
    /// `canvasWidth` is the real board width, never a constant: clamping
    /// against 360 on a 393pt screen would itself be the bug it is
    /// supposed to prevent.
    public static func resolve(
        _ changes: [ElementChange],
        handles: [String: CanvasItem.ID],
        canvasWidth: CGFloat
    ) -> [ResolvedChange] {
        let width = Double(max(1, canvasWidth))
        return changes.compactMap { change in
            guard let id = handles[change.handle] else { return nil }
            return ResolvedChange(
                id: id,
                x: change.x.map { min(max(0, $0), width) },
                // The canvas scrolls downward without limit, so only the
                // top edge is a wall.
                y: change.y.map { max(0, $0) },
                w: change.w.map { min(max(1, $0), width) },
                h: change.h.map { max(1, $0) },
                pointSize: change.pointSize.map {
                    min(max(Self.pointSizeRange.lowerBound, CGFloat($0)),
                        Self.pointSizeRange.upperBound)
                },
                colorName: change.color.flatMap {
                    CanvasPalette.names.contains($0) ? $0 : nil
                },
                layer: change.layer
            )
        }
    }
}
