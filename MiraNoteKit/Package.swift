// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "MiraNoteKit",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "MiraNoteKit", targets: ["MiraNoteKit"])
    ],
    targets: [
        .target(name: "MiraNoteKit", dependencies: ["StickerEdgeCore"]),
        // Per-pixel image code, optimised in every configuration: a Debug build
        // ran it 57x slower (23 s a sticker instead of 0.4 s), and a team build
        // run from Xcode is Debug unless someone remembers to change the scheme.
        // Its own target so the rest of the package still debugs normally.
        // unsafeFlags only resolves while the app references MiraNoteKit by
        // local path; as a versioned/remote dependency SwiftPM rejects it.
        .target(
            name: "StickerEdgeCore",
            swiftSettings: [.unsafeFlags(["-O"])]
        ),
        .testTarget(name: "MiraNoteKitTests", dependencies: ["MiraNoteKit", "StickerEdgeCore"])
    ]
)
