// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "osaurus-vision",
    platforms: [.macOS(.v15)],
    products: [
        .library(name: "osaurus-vision", type: .dynamic, targets: ["osaurus_vision"])
    ],
    dependencies: [
        .package(url: "https://github.com/osaurus-ai/osaurus-plugin-sdk.git", exact: "1.0.0")
    ],
    targets: [
        .target(
            name: "osaurus_vision",
            dependencies: [
                .product(name: "OsaurusPluginABI", package: "osaurus-plugin-sdk"),
                .product(name: "OsaurusPluginKit", package: "osaurus-plugin-sdk"),
            ],
            path: "Sources/osaurus_vision",
            linkerSettings: [
                .linkedFramework("Vision"),
                .linkedFramework("CoreImage"),
                .linkedFramework("AppKit")
            ]
        ),
        .testTarget(
            name: "osaurus_visionTests",
            dependencies: [
                "osaurus_vision",
                .product(name: "OsaurusPluginKit", package: "osaurus-plugin-sdk"),
                .product(name: "OsaurusPluginTestSupport", package: "osaurus-plugin-sdk"),
            ],
            path: "Tests/osaurus_visionTests"
        )
    ]
)
