import MiraNoteKit
import SpriteKit
import SwiftUI
import UIKit

/// The jar's stars in the air after a tap on the jar (#179): SpriteKit's
/// physics throws them up like popcorn, lower ones higher, each turning
/// as it flies, and lets them fall back under gravity, bouncing off the
/// glass and each other. Only the toss is drawn here: at rest the stars
/// are the jar's own buttons again, at the spots `onSettle` hands back.
final class StarTossScene: SKScene, SKPhysicsContactDelegate {
    /// Every star's spot once all of them lie still, in the jar's
    /// (SwiftUI, y-down) coordinates.
    var onSettle: ([Memory.ID: StarPile.Spot]) -> Void = { _ in }

    private(set) var isTossing = false
    private var nodes: [Memory.ID: SKSpriteNode] = [:]
    /// The glass's inside: a star whose center slips past it (a fast one
    /// through the edge) goes back to where it last was inside.
    private var inside = CGPath(rect: .zero, transform: nil)
    private var lastInside: [Memory.ID: CGPoint] = [:]
    /// When the last tap threw the stars: set on the first frame after it,
    /// since a paused scene's clock stands still.
    private var lastThrow: TimeInterval?
    private var now: TimeInterval = 0
    private var stillFrames = 0
    private var ticks = 0
    private var lastTick: TimeInterval = 0
    private let tick = UIImpactFeedbackGenerator(style: .soft)

    /// Points per meter in SpriteKit's physics, for gravity in points.
    private static let pointsPerMeter: CGFloat = 150
    private static let gravity: CGFloat = 9.8 * pointsPerMeter
    private static let starCategory: UInt32 = 1
    private static let glassCategory: UInt32 = 2

    #if DEBUG
    /// The last toss's frame rate, for the debug probe.
    private(set) var frameStats = (fps: 0, worstMs: 0)
    private var frameTimes: [TimeInterval] = []
    #endif

    override init(size: CGSize) {
        super.init(size: size)
        backgroundColor = .clear
        scaleMode = .resizeFill
        physicsWorld.gravity = CGVector(dx: 0, dy: -9.8)
        physicsWorld.contactDelegate = self
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    /// Lays the stars where they rest now, inside `geometry`'s glass, ready
    /// to be thrown.
    func load(
        _ stars: [(star: JarStar, spot: StarPile.Spot)],
        starSize: CGFloat,
        geometry: JarGeometry,
        face: (Mood?) -> SKTexture
    ) {
        removeAllChildren()
        nodes = [:]
        lastInside = [:]
        size = geometry.size
        // Inside the hairline by what a turned star's tips reach past its
        // circle (its face sits a little low in its frame): no tip ever
        // crosses the glass.
        let flip = CGAffineTransform(translationX: 0, y: size.height).scaledBy(x: 1, y: -1)
        let edge = geometry.outline(inset: JarGeometry.stroke + 1 + starSize * 0.1).cgPath
        physicsBody = SKPhysicsBody(edgeLoopFrom: edge.copy(using: [flip]) ?? edge)
        physicsBody?.categoryBitMask = Self.glassCategory
        physicsBody?.friction = 0.3
        physicsBody?.restitution = 0.3
        inside = geometry.outline(inset: JarGeometry.stroke).cgPath.copy(using: [flip]) ?? edge
        for (star, spot) in stars {
            let node = SKSpriteNode(texture: face(star.memory.mood), size: CGSize(width: starSize, height: starSize))
            node.position = flipped(spot.center)
            node.zRotation = -spot.rotation * .pi / 180
            // A circle a little inside the star's tips: neighbors nest the
            // way the resting pile does.
            let body = SKPhysicsBody(circleOfRadius: starSize * 0.46)
            body.restitution = 0.3
            body.friction = 0.4
            body.linearDamping = 0.15
            body.angularDamping = 0.6
            body.categoryBitMask = Self.starCategory
            body.contactTestBitMask = Self.glassCategory
            body.usesPreciseCollisionDetection = true
            node.physicsBody = body
            addChild(node)
            nodes[star.id] = node
            lastInside[star.id] = node.position
        }
    }

    /// Throws every star up: staggered by a few frames, lower stars higher,
    /// each with half to one turn either way. A tap mid-toss throws them
    /// again from wherever they are.
    func toss() {
        guard !nodes.isEmpty else { return }
        isTossing = true
        // SpriteView's own `isPaused` reaches the view only when it is
        // first made: the scene wakes and rests its view itself.
        view?.isPaused = false
        isPaused = false
        stillFrames = 0
        ticks = 0
        lastThrow = nil
        #if DEBUG
        frameTimes = []
        #endif
        let lows = nodes.values.map(\.position.y)
        let bottom = lows.min() ?? 0
        let span = max(1, (lows.max() ?? 0) - bottom)
        for node in nodes.values {
            // 1 for the floor's stars, 0 for the top of the pile.
            let depth = 1 - (node.position.y - bottom) / span
            let height = size.height * (0.14 + 0.2 * depth) * .random(in: 0.8...1.15)
            let lift = (2 * Self.gravity * height).squareRoot()
            let air = 2 * lift / Self.gravity
            let turns = CGFloat.random(in: 0.5...1) * 2 * .pi * (Bool.random() ? 1 : -1)
            let drift = CGFloat.random(in: -70...70)
            node.run(.sequence([
                .wait(forDuration: .random(in: 0...0.12)),
                .run {
                    guard let body = node.physicsBody else { return }
                    // A star still rising gets a push, never more than one
                    // throw's speed: fast taps keep them up, not pinned to
                    // the lid.
                    let rise = min(max(body.velocity.dy, 0) + lift, lift * 1.1)
                    body.velocity = CGVector(dx: body.velocity.dx + drift, dy: rise)
                    body.angularVelocity = turns / air
                }
            ]))
        }
    }

    /// Where every star is this frame, for a tap on one in the air.
    func spots() -> [Memory.ID: StarPile.Spot] {
        nodes.mapValues { node in
            StarPile.Spot(center: flipped(node.position), rotation: -Double(node.zRotation) * 180 / .pi)
        }
    }

    override func update(_ currentTime: TimeInterval) {
        #if DEBUG
        if isTossing, lastThrow != nil { frameTimes.append(currentTime - now) }
        #endif
        now = currentTime
        guard isTossing else { return }
        let thrown = lastThrow ?? currentTime
        lastThrow = thrown
        for (id, node) in nodes {
            if inside.contains(node.position) {
                lastInside[id] = node.position
            } else if let back = lastInside[id] {
                node.position = back
                node.physicsBody?.velocity = .zero
            }
        }
        let still = nodes.values.allSatisfy { node in
            guard let body = node.physicsBody else { return true }
            return body.isResting
                || (hypot(body.velocity.dx, body.velocity.dy) < 8 && abs(body.angularVelocity) < 0.4)
        }
        stillFrames = still ? stillFrames + 1 : 0
        let elapsed = currentTime - thrown
        // Calm for a few frames after the throw has landed, or at most 3 s
        // after the last tap: a heap that keeps creeping still hands back.
        if (elapsed > 0.6 && stillFrames >= 6) || elapsed > 3 {
            settle()
        }
    }

    private func settle() {
        isTossing = false
        for node in nodes.values {
            node.removeAllActions()
            node.physicsBody?.velocity = .zero
            node.physicsBody?.angularVelocity = 0
        }
        #if DEBUG
        if !frameTimes.isEmpty {
            let average = frameTimes.reduce(0, +) / Double(frameTimes.count)
            frameStats = (Int((1 / average).rounded()), Int(((frameTimes.max() ?? 0) * 1000).rounded()))
        }
        #endif
        onSettle(spots())
        isPaused = true
        view?.isPaused = true
    }

    /// Soft ticks as the first stars land: at most three a toss.
    func didBegin(_ contact: SKPhysicsContact) {
        guard isTossing, let lastThrow, now - lastThrow > 0.25, ticks < 3, now - lastTick > 0.12,
              contact.collisionImpulse > 4 else { return }
        ticks += 1
        lastTick = now
        tick.impactOccurred(intensity: 0.45)
    }

    /// Between the jar's y-down points and the scene's y-up ones.
    private func flipped(_ point: CGPoint) -> CGPoint {
        CGPoint(x: point.x, y: size.height - point.y)
    }
}

/// The jar's sway and hop on a tap, in degrees and points (down is
/// positive).
struct JarPose {
    var angle = 0.0
    var lift: CGFloat = 0
}

extension StarTossScene {
    /// A mood's star face as a texture, drawn by the same `StarMark` the
    /// resting stars are, so the hand-over between the two never shows.
    @MainActor static func face(_ mood: Mood?, size: CGFloat, scale: CGFloat) -> SKTexture {
        let renderer = ImageRenderer(content: StarMark(color: Palette.mood(mood)).frame(width: size, height: size))
        renderer.scale = scale
        return SKTexture(image: renderer.uiImage ?? UIImage())
    }
}
