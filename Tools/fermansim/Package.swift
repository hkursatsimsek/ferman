// swift-tools-version: 6.2
import PackageDescription

let strictSettings: [SwiftSetting] = [
    .enableUpcomingFeature("ExistentialAny"),
    .treatAllWarnings(as: .error),
]

let package = Package(
    name: "fermansim",
    platforms: [.macOS("27.0")],
    products: [
        .executable(name: "fermansim", targets: ["fermansim"])
    ],
    dependencies: [
        .package(path: "../../Packages/FermanCore"),
        .package(path: "../../Packages/FermanContent"),
    ],
    targets: [
        .executableTarget(
            name: "fermansim",
            dependencies: ["FermanSimCLI"],
            swiftSettings: strictSettings
        ),
        .target(
            name: "FermanSimCLI",
            dependencies: [
                .product(name: "FermanCore", package: "FermanCore"),
                .product(name: "FermanContent", package: "FermanContent"),
            ],
            swiftSettings: strictSettings
        ),
        .testTarget(
            name: "FermanSimCLITests",
            dependencies: [
                "FermanSimCLI",
                .product(name: "FermanCore", package: "FermanCore"),
            ],
            swiftSettings: strictSettings
        ),
    ]
)
