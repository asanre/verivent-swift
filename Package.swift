// swift-tools-version: 5.9
//
// Rendered by the `publish` workflow into asanre/verivent-swift — the placeholders become the release
// asset's URL and checksum. Never edit the rendered copy: this file and Sources/ are the source of
// truth, and the generated repo is overwritten on every release.
import PackageDescription

let package = Package(
    name: "Verivent",
    platforms: [.iOS(.v14)],
    products: [
        .library(name: "Verivent", targets: ["Verivent"]),
        .library(name: "VeriventUITesting", targets: ["VeriventUITesting"]),
    ],
    targets: [
        .binaryTarget(
            name: "VeriventKit",
            url: "https://github.com/asanre/verivent/releases/download/v0.10.1/VeriventKit.xcframework.zip",
            checksum: "1d756fe3e6d69a706b5fe46cd8727e6fa552a0dd9873cad28b203f98027dd86d"
        ),
        .target(name: "Verivent", dependencies: ["VeriventKit"]),
        // For UI test targets: only XCTest and URLSession, nothing of Verivent in the test runner.
        .target(name: "VeriventUITesting"),
    ]
)
