// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "VaireKit",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .library(
            name: "VaireKit",
            targets: ["VaireKit"]
        ),
        .executable(
            name: "vaire",
            targets: ["VaireCLI"]
        )
    ],
    dependencies: [
        .package(url: "https://github.com/groue/GRDB.swift.git", from: "6.29.0")
    ],
    targets: [
        .target(
            name: "VaireKit",
            dependencies: [
                .product(name: "GRDB", package: "GRDB.swift")
            ]
        ),
        .testTarget(
            name: "VaireKitTests",
            dependencies: ["VaireKit"],
            resources: [
                .copy("Fixtures")
            ]
        ),
        .executableTarget(
            name: "VaireCLI",
            dependencies: ["VaireKit"]
        )
    ]
)
