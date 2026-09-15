// swift-tools-version: 6.2
import PackageDescription

let strictSettings: [SwiftSetting] = [
    .enableUpcomingFeature("ExistentialAny"),
    .treatAllWarnings(as: .error),
]

let package = Package(
    name: "FermanCore",
    platforms: [.iOS("27.0"), .macOS("27.0")],
    products: [
        .library(name: "FermanCore", targets: ["FermanCore"])
    ],
    targets: [
        .target(
            name: "FermanCore",
            swiftSettings: strictSettings + [.strictMemorySafety()]
        ),
        .testTarget(
            name: "FermanCoreTests",
            dependencies: ["FermanCore"],
            swiftSettings: strictSettings
        ),
    ]
)
