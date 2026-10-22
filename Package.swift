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
            url: "https://github.com/asanre/verivent/releases/download/v0.10.0/VeriventKit.xcframework.zip",
            checksum: "f67ce7d69bd5e133a1f21d5aa6e2142f0436a3dd58c30741ebe530edb4b0a673"
        ),
        .target(name: "Verivent", dependencies: ["VeriventKit"]),
        // For UI test targets: only XCTest and URLSession, nothing of Verivent in the test runner.
        .target(name: "VeriventUITesting"),
    ]
)
