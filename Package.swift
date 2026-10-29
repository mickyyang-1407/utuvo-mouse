// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "UTUVOMouse",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "UTUVOMouseCore", targets: ["UTUVOMouseCore"]),
        .library(name: "UTUVOMouseIO", targets: ["UTUVOMouseIO"]),
        .executable(name: "UTUVO Mouse", targets: ["UTUVOMouse"]),
    ],
    targets: [
        // Pure protocol + model layer. No IOKit, no hardware, fully testable.
        .target(name: "UTUVOMouseCore"),
        // IOKit HID transport. Real device access lives here only.
        .target(name: "UTUVOMouseIO", dependencies: ["UTUVOMouseCore"]),
        // SwiftUI application + `--probe` / `--demo` command line modes.
        .executableTarget(
            name: "UTUVOMouse",
            dependencies: ["UTUVOMouseCore", "UTUVOMouseIO"],
            swiftSettings: [.defaultIsolation(MainActor.self)]
        ),
        .testTarget(name: "UTUVOMouseCoreTests", dependencies: ["UTUVOMouseCore", "UTUVOMouseIO"]),
    ]
)
