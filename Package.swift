// swift-tools-version: 5.7
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "LinuxHalSwiftIO",
    platforms: [
        // specify each minimum deployment requirement,
        // otherwise the platform default minimum is used.
        .macOS(.v10_15),
    ],
    products: [
        // Products define the executables and libraries a package produces, and make them visible
        // to other packages.
        .library(
            name: "LinuxHalSwiftIO",
            targets: ["LinuxHalSwiftIO"]
        ),
        .library(
            name: "AsyncSwiftIO",
            targets: ["AsyncSwiftIO"]
        ),
    ],
    dependencies: [
        // Dependencies declare other packages that this package depends on.
        .package(url: "https://github.com/PADL/SwiftIO.git", branch: "linux-hal"),
        .package(url: "https://github.com/apple/swift-async-algorithms", from: "0.1.0"),
        .package(url: "https://github.com/lhoward/AsyncExtensions", branch: "linux"),
    ],
    targets: [
        .target(
            name: "LinuxHalSwiftIO",
            dependencies: [
                .product(name: "CSwiftIO", package: "SwiftIO"),
            ],
            cSettings: [
                .unsafeFlags(["-I", "/opt/swift/usr/lib/swift"]),
            ],
            linkerSettings: [
                .linkedLibrary("gpiod", .when(platforms: [.linux])),
            ]
        ),
        .target(
            name: "AsyncSwiftIO",
            dependencies: [
                .product(name: "AsyncAlgorithms", package: "swift-async-algorithms"),
                "AsyncExtensions",
                .product(name: "SwiftIO", package: "SwiftIO"),
                "LinuxHalSwiftIO",
            ],
            cSettings: [
                .unsafeFlags(["-I", "/opt/swift/usr/lib/swift"]),
            ]
        ),
        .executableTarget(
            name: "SPIMonitor",
            dependencies: [
                "AsyncSwiftIO",
                "SwiftIO",
            ],
            path: "Examples/SPIMonitor"
        ),
        .executableTarget(
            name: "UARTMonitor",
            dependencies: [
                "AsyncSwiftIO",
                "SwiftIO",
            ],
            path: "Examples/UARTMonitor"
        ),
        .testTarget(
            name: "LinuxHalSwiftIOTests",
            dependencies: [
                .target(name: "LinuxHalSwiftIO"),
                .target(name: "AsyncSwiftIO"),
            ]
        ),
    ]
)
