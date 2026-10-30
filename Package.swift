// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "UTUVOMouse",
    defaultLocalization: "en",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "UTUVOMouseLocalization", targets: ["UTUVOMouseLocalization"]),
        .library(name: "UTUVOMouseCore", targets: ["UTUVOMouseCore"]),
        .library(name: "UTUVOMouseIO", targets: ["UTUVOMouseIO"]),
        .library(name: "UTUVOMouseSupport", targets: ["UTUVOMouseSupport"]),
        .executable(name: "UTUVO Mouse", targets: ["UTUVOMouse"]),
    ],
    dependencies: [
        // The only dependency of the app: the official Sparkle release, pinned to
        // one audited tag. It brings its own updater, downloader and installer;
        // nothing else is added.
        .package(url: "https://github.com/sparkle-project/Sparkle", exact: "2.10.1")
    ],
    targets: [
        .target(
            name: "UTUVOMouseLocalization",
            resources: [.process("Resources")]
        ),
        // Pure protocol + model layer. No IOKit, no hardware, fully testable.
        .target(name: "UTUVOMouseCore", dependencies: ["UTUVOMouseLocalization"]),
        // IOKit HID transport. Real device access lives here only.
        .target(name: "UTUVOMouseIO", dependencies: ["UTUVOMouseCore", "UTUVOMouseLocalization"]),
        // Login item, updater configuration and the shared exit gate.
        // No Sparkle and no ServiceManagement here, so every seam stays
        // injectable and the tests never touch the system.
        .target(name: "UTUVOMouseSupport", dependencies: ["UTUVOMouseLocalization", "UTUVOMouseCore"]),
        // SwiftUI application + `--probe` / `--demo` command line modes.
        .executableTarget(
            name: "UTUVOMouse",
            dependencies: [
                "UTUVOMouseCore",
                "UTUVOMouseIO",
                "UTUVOMouseSupport",
                "UTUVOMouseLocalization",
                .product(name: "Sparkle", package: "Sparkle"),
            ],
            swiftSettings: [.defaultIsolation(MainActor.self)]
        ),
        .testTarget(
            name: "UTUVOMouseCoreTests",
            dependencies: ["UTUVOMouseCore", "UTUVOMouseIO", "UTUVOMouseSupport", "UTUVOMouseLocalization"]
        ),
    ]
)
