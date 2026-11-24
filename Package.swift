// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "DisplayCorners",
    platforms: [.macOS(.v13)],
    products: [.executable(name: "DisplayCorners", targets: ["DisplayCorners"])],
    targets: [
        .target(name: "CornerGeometry"),
        .target(name: "SessionList"),
        .executableTarget(name: "DisplayCorners", dependencies: ["CornerGeometry", "SessionList"]),
        .testTarget(name: "CornerGeometryTests", dependencies: ["CornerGeometry"]),
        .testTarget(name: "SessionListTests", dependencies: ["SessionList"]),
    ]
)
