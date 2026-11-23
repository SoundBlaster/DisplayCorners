// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "DisplayCorners",
    platforms: [.macOS(.v13)],
    products: [.executable(name: "DisplayCorners", targets: ["DisplayCorners"])],
    targets: [
        .target(name: "CornerGeometry"),
        .executableTarget(name: "DisplayCorners", dependencies: ["CornerGeometry"]),
        .testTarget(name: "CornerGeometryTests", dependencies: ["CornerGeometry"]),
    ]
)
