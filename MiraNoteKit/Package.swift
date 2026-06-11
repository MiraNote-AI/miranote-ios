// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "MiraNoteKit",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "MiraNoteKit", targets: ["MiraNoteKit"])
    ],
    targets: [
        .target(name: "MiraNoteKit"),
        .testTarget(name: "MiraNoteKitTests", dependencies: ["MiraNoteKit"])
    ]
)
