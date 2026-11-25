// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "DisplayCorners",
    platforms: [.macOS(.v13)],
    products: [
        .executable(name: "DisplayCorners", targets: ["DisplayCorners"]),
        .executable(name: "DisplayCornersHook", targets: ["DisplayCornersHook"]),
    ],
    targets: [
        .target(name: "CornerGeometry"),
        .target(name: "SessionList"),
        .target(name: "AgentRuntime", dependencies: ["SessionList"]),
        .executableTarget(name: "DisplayCorners", dependencies: ["CornerGeometry", "SessionList", "AgentRuntime"]),
        .executableTarget(name: "DisplayCornersHook", dependencies: ["AgentRuntime"]),
        .testTarget(name: "CornerGeometryTests", dependencies: ["CornerGeometry"]),
        .testTarget(name: "SessionListTests", dependencies: ["SessionList"]),
        .testTarget(name: "AgentRuntimeTests", dependencies: ["AgentRuntime"]),
    ]
)
