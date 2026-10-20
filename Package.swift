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
            url: "https://github.com/asanre/verivent/releases/download/v0.9.0/VeriventKit.xcframework.zip",
            checksum: "3a94a594c9c91bdd8268b35e4b173d4491704e2842adb373941781f22b1b99be"
        ),
        .target(name: "Verivent", dependencies: ["VeriventKit"]),
    ]
)
