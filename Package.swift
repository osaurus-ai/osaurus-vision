// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "osaurus-vision",
    platforms: [.macOS(.v15)],
    products: [
        .library(name: "osaurus-vision", type: .dynamic, targets: ["osaurus_vision"])
    ],
    targets: [
        .target(
            name: "osaurus_vision",
            path: "Sources/osaurus_vision",
            linkerSettings: [
                .linkedFramework("Vision"),
                .linkedFramework("CoreImage"),
                .linkedFramework("AppKit")
            ]
        ),
        .testTarget(
            name: "osaurus_visionTests",
            dependencies: ["osaurus_vision"],
            path: "Tests/osaurus_visionTests"
        )
    ]
)