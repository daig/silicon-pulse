// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "SiliconPulse",
    platforms: [
        .macOS(.v15)
    ],
    products: [
        .executable(name: "SiliconPulse", targets: ["SiliconPulse"])
    ],
    targets: [
        .target(
            name: "CMetrics",
            path: "Sources/CMetrics",
            publicHeadersPath: "include",
            cSettings: [
                .unsafeFlags(["-fobjc-arc"])
            ],
            linkerSettings: [
                .linkedFramework("Foundation"),
                .linkedFramework("IOKit"),
                .linkedFramework("Metal"),
                .linkedLibrary("IOReport")
            ]
        ),
        .executableTarget(
            name: "SiliconPulse",
            dependencies: ["CMetrics"],
            path: "Sources/SiliconPulse",
            swiftSettings: [
                .swiftLanguageMode(.v5)
            ]
        )
    ]
)
