// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "osmBroker",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "osmBrokerCore", targets: ["osmBrokerCore"]),
        .executable(name: "osmBroker", targets: ["osmBroker"])
    ],
    dependencies: [
        // ADR-1: SwiftNIO for HTTP. NIOHTTP1 for parsing.
        .package(url: "https://github.com/apple/swift-nio.git", from: "2.65.0"),
        // Structured logging with redaction-friendly handlers.
        .package(url: "https://github.com/apple/swift-log.git", from: "1.5.4")
    ],
    targets: [
        // Pure broker logic — detection, HTTP server, adapters, spawning.
        // No SwiftUI imports. Fully unit-testable.
        .target(
            name: "osmBrokerCore",
            dependencies: [
                .product(name: "NIOCore", package: "swift-nio"),
                .product(name: "NIOHTTP1", package: "swift-nio"),
                .product(name: "NIOPosix", package: "swift-nio"),
                .product(name: "Logging", package: "swift-log")
            ],
            path: "Sources/osmBrokerCore"
        ),
        // SwiftUI app — depends on core.
        .executableTarget(
            name: "osmBroker",
            dependencies: ["osmBrokerCore"],
            path: "Sources/osmBroker",
            resources: [
                .process("Resources")
            ]
        ),
        // Unit + integration tests against the core library.
        .testTarget(
            name: "osmBrokerCoreTests",
            dependencies: ["osmBrokerCore"],
            path: "Tests/osmBrokerCoreTests",
            resources: [
                .copy("Fixtures")
            ]
        )
    ]
)
