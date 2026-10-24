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
            url: "https://github.com/asanre/verivent/releases/download/v0.11.0/VeriventKit.xcframework.zip",
            checksum: "596711231bd64b62977c588065af5b33e7dabe550b6c286e3cf4655e8b1b55de"
        ),
        .target(name: "Verivent", dependencies: ["VeriventKit"]),
        // For UI test targets: only XCTest and URLSession, nothing of Verivent in the test runner.
        .target(name: "VeriventUITesting"),
    ]
)
