// swift-tools-version: 6.2
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "SVGPDFKit",
    platforms: [
        .macOS(.v12)
    ],
    products: [
        .library(
            name: "SVGPDFKit",
            targets: ["SVGPDFKit"]
        )
    ],
    dependencies: [
        .package(
            url: "https://github.com/swhitty/SwiftDraw.git",
            from: "0.18.0"
        )
    ],
    targets: [
        .target(
            name: "SVGPDFKit",
            dependencies: [
                .product(name: "SwiftDraw", package: "SwiftDraw")
            ]
        ),
        .testTarget(
            name: "SVGPDFKitTests",
            dependencies: ["SVGPDFKit"],
            resources: [
                .copy("Resources")
            ]
        )
    ]
)
