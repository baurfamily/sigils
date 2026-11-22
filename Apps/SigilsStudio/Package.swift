// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "SigilsStudio",
    platforms: [.macOS(.v13)],
    products: [
        .executable(name: "sigils-studio", targets: ["SigilsStudio"]),
    ],
    dependencies: [
        .package(path: "../.."),
        .package(url: "https://github.com/moreSwift/swift-cross-ui.git", exact: "0.9.0"),
        .package(url: "https://github.com/a2/MessagePack.swift.git", from: "4.0.0"),
    ],
    targets: [
        .target(
            name: "StudioCore",
            dependencies: [
                .product(name: "Sigils", package: "sigils"),
                .product(name: "MessagePack", package: "MessagePack.swift"),
            ]
        ),
        .executableTarget(
            name: "SigilsStudio",
            dependencies: [
                "StudioCore",
                .product(name: "SwiftCrossUI", package: "swift-cross-ui"),
                .product(name: "DefaultBackend", package: "swift-cross-ui"),
            ]
        ),
        .testTarget(
            name: "StudioCoreTests",
            dependencies: [
                "StudioCore",
                .product(name: "MessagePack", package: "MessagePack.swift"),
            ]
        ),
        .testTarget(name: "StudioViewTests", dependencies: ["SigilsStudio", "StudioCore"]),
    ]
)
