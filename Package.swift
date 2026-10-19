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
    ],
    targets: [
        .binaryTarget(
            name: "VeriventKit",
            url: "https://github.com/asanre/verivent/releases/download/v0.8.0/VeriventKit.xcframework.zip",
            checksum: "310f3a7bc12f8af037935da35fc37ac9cc5cdf06e1955ead1e3eadbf79452665"
        ),
        .target(name: "Verivent", dependencies: ["VeriventKit"]),
    ]
)
