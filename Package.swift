// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "SpoofTrap",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(name: "SpoofTrap", targets: ["SpoofTrap"])
    ],
    targets: [
        .executableTarget(
            name: "SpoofTrap",
            path: "Sources",
            resources: [
                .copy("Resources/spooftrap-icon.png"),
                .copy("Resources/bin")
            ]
        ),
        .testTarget(
            name: "SpoofTrapTests",
            dependencies: ["SpoofTrap"],
            path: "Tests"
        )
    ]
)
