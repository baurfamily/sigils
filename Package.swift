// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Sigils",
    products: [
        .executable(name: "sigils", targets: ["SigilsCLI"]),
        .library(name: "Sigils", targets: ["Sigils"]),
    ],
    dependencies: [
        .package(url: "https://github.com/jpsim/Yams.git", from: "6.0.0"),
    ],
    targets: [
        .target(name: "Sigils"),
        .target(
            name: "SigilsSpecRunner",
            dependencies: ["Sigils", .product(name: "Yams", package: "Yams")]
        ),
        .executableTarget(
            name: "SigilsCLI",
            dependencies: ["Sigils", "SigilsSpecRunner"]
        ),
        .testTarget(name: "SigilsTests", dependencies: ["Sigils", "SigilsSpecRunner"]),
    ]
)
