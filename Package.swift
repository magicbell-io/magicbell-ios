// swift-tools-version:5.5
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "MagicBell",
    platforms: [
        .iOS(.v12),
        .macOS(.v10_15)
    ],
    products: [
        .library(
            name: "MagicBell",
            targets: ["MagicBell"]
        ),
    ],
    dependencies: [
        .package(url: "https://github.com/mobilejazz/harmony-swift", from: "2.0.0"),
        .package(url: "https://github.com/ably/ably-cocoa", from: "1.2.27")
    ],
    targets: [
        .target(
            name: "MagicBell",
            dependencies: [
                .product(name: "Harmony", package: "harmony-swift"),
                .product(name: "Ably", package: "ably-cocoa")
            ],
            path: "Source"
        )
    ]
)
