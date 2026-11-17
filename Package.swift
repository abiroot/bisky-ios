// swift-tools-version: 6.0
import PackageDescription

// The package's identity is its repository's name, `bisky-ios`:
//     .product(name: "Bisky", package: "bisky-ios")
// Its name is the product's, so Xcode's scheme is `Bisky`.
let package = Package(
    name: "Bisky",
    platforms: [.iOS(.v15)],
    products: [
        .library(name: "Bisky", targets: ["Bisky"]),
    ],
    targets: [
        .target(name: "Bisky"),
        .testTarget(
            name: "BiskyTests",
            dependencies: ["Bisky"],
            resources: [.copy("Fixtures")]
        ),
    ]
)
