// swift-tools-version: 6.2
import PackageDescription

let strictSettings: [SwiftSetting] = [
    .enableUpcomingFeature("ExistentialAny"),
    .treatAllWarnings(as: .error),
]

let package = Package(
    name: "FermanReplay",
    platforms: [.iOS("27.0"), .macOS("27.0")],
    products: [
        .library(name: "FermanReplay", targets: ["FermanReplay"])
    ],
    dependencies: [
        .package(path: "../FermanCore")
    ],
    targets: [
        .target(
            name: "FermanReplay",
            dependencies: [
                .product(name: "FermanCore", package: "FermanCore")
            ],
            swiftSettings: strictSettings
        ),
        .testTarget(
            name: "FermanReplayTests",
            dependencies: [
                "FermanReplay",
                .product(name: "FermanCore", package: "FermanCore"),
            ],
            swiftSettings: strictSettings
        ),
    ]
)
