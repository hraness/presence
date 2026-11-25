// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "presence",
    platforms: [.macOS(.v13)],
    products: [
        .executable(name: "presence", targets: ["presence"]),
        .library(name: "PresenceCore", targets: ["PresenceCore"]),
    ],
    targets: [
        // Pure model, classification, filters, CLI parsing and loops. Foundation only.
        .target(name: "PresenceCore"),
        // Reads the live machine through CoreGraphics, CoreAudio, CoreMediaIO, IOKit and libproc.
        .target(
            name: "PresenceSystem",
            dependencies: ["PresenceCore"],
            linkerSettings: [
                .linkedFramework("CoreGraphics"),
                .linkedFramework("CoreAudio"),
                .linkedFramework("CoreMediaIO"),
                .linkedFramework("IOKit"),
            ]
        ),
        .executableTarget(name: "presence", dependencies: ["PresenceCore", "PresenceSystem"]),
        .testTarget(
            name: "PresenceCoreTests",
            dependencies: ["PresenceCore"],
            resources: [.copy("Fixtures")]
        ),
    ],
    swiftLanguageModes: [.v5]
)
