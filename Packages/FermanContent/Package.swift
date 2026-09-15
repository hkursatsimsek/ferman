// swift-tools-version: 6.2
import PackageDescription

let strictSettings: [SwiftSetting] = [
    .enableUpcomingFeature("ExistentialAny"),
    .treatAllWarnings(as: .error),
]

let package = Package(
    name: "FermanContent",
    platforms: [.iOS("27.0"), .macOS("27.0")],
    products: [
        .library(name: "FermanContent", targets: ["FermanContent"])
    ],
    dependencies: [
        .package(path: "../FermanCore")
    ],
    targets: [
        .target(
            name: "FermanContent",
            dependencies: [
                .product(name: "FermanCore", package: "FermanCore")
            ],
            resources: [
                .copy("Resources")
            ],
            swiftSettings: strictSettings
        ),
        .testTarget(
            name: "FermanContentTests",
            dependencies: [
                "FermanContent",
                .product(name: "FermanCore", package: "FermanCore"),
            ],
            swiftSettings: strictSettings
        ),
    ]
)
