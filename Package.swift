// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "ImageCache",
    platforms: [
        .iOS(.v15)
    ],
    products: [
        .library(name: "ImageCache", targets: ["ImageCache"]),
    ],
    targets: [
        .target(
            name: "Common",
            path: "Sources/Common"
        ),
        .target(
            name: "Caches",
            dependencies: ["Common"],
            path: "Sources/Caches"
        ),
        .target(
            name: "Networks",
            path: "Sources/Networks"
        ),
        .target(
            name: "ImageCache",
            dependencies: ["Caches", "Networks", "Common"],
            path: "Sources/ImageCache"
        ),
        .target(
            name: "TestUtilities",
            path: "Sources/TestUtilities"
        ),
        .testTarget(
            name: "ImageCacheTests",
            dependencies: ["ImageCache", "Common"],
            path: "Tests/ImageCacheTests"
        ),
        .testTarget(
            name: "CachesTests",
            dependencies: ["Caches", "Common"],
            path: "Tests/CachesTests"
        ),
        .testTarget(
            name: "NetworksTests",
            dependencies: ["Networks"],
            path: "Tests/NetworksTests"
        ),
        .testTarget(
            name: "CommonTests",
            dependencies: ["Common"],
            path: "Tests/CommonTests"
        )
    ]
)
