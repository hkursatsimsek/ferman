// swift-tools-version: 6.2
import PackageDescription

let strictSettings: [SwiftSetting] = [
    .enableUpcomingFeature("ExistentialAny"),
    .treatAllWarnings(as: .error),
]

let package = Package(
    name: "FermanAI",
    platforms: [.iOS("27.0"), .macOS("27.0")],
    products: [
        .library(name: "FermanAI", targets: ["FermanAI"])
    ],
    dependencies: [
        .package(path: "../FermanCore")
    ],
    targets: [
        .target(
            name: "FermanAI",
            dependencies: [
                .product(name: "FermanCore", package: "FermanCore")
            ],
            swiftSettings: strictSettings
        ),
        .testTarget(
            name: "FermanAITests",
            dependencies: [
                "FermanAI",
                .product(name: "FermanCore", package: "FermanCore"),
            ],
            swiftSettings: strictSettings
        ),
    ]
)
