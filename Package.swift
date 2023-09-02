// swift-tools-version: 5.7
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "LinuxHalSwiftIO",
    products: [
        // Products define the executables and libraries a package produces, and make them visible to other packages.
        .library(
            name: "LinuxHalSwiftIO",
            targets: ["LinuxHalSwiftIO"]),
    ],
    dependencies: [
        // Dependencies declare other packages that this package depends on.
        .package(url: "https://github.com/madmachineio/SwiftIO.git", branch: "main"),
    ],
    targets: [
        .target(
            name: "LinuxHalSwiftIO",
            dependencies: [
                .product(name: "CSwiftIO", package: "SwiftIO")
            ],
            cSettings: [
                .unsafeFlags(["-I", "/opt/swift/usr/lib/swift"]),
            ]
        )
    ]
)
