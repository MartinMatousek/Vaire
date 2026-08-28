// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "TimeKeeperKit",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .library(
            name: "TimeKeeperKit",
            targets: ["TimeKeeperKit"]
        )
    ],
    dependencies: [
        .package(url: "https://github.com/groue/GRDB.swift.git", from: "6.29.0")
    ],
    targets: [
        .target(
            name: "TimeKeeperKit",
            dependencies: [
                .product(name: "GRDB", package: "GRDB.swift")
            ]
        ),
        .testTarget(
            name: "TimeKeeperKitTests",
            dependencies: ["TimeKeeperKit"],
            resources: [
                .copy("Fixtures")
            ]
        )
    ]
)
