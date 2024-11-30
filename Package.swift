// swift-tools-version: 5.7
// The swift-tools-version declares the minimum version of Swift required to build this package.

import Foundation
import PackageDescription

func tryGuessSwiftLibRoot() -> String {
  let task = Process()
  task.executableURL = URL(fileURLWithPath: "/bin/sh")
  task.arguments = ["-c", "which swift"]
  task.standardOutput = Pipe()
  do {
    try task.run()
    let outputData = (task.standardOutput as! Pipe).fileHandleForReading.readDataToEndOfFile()
    let path = URL(fileURLWithPath: String(decoding: outputData, as: UTF8.self))
    return path.deletingLastPathComponent().path + "/../lib/swift"
  } catch {
    return "/usr/lib/swift"
  }
}

let SwiftLibRoot = tryGuessSwiftLibRoot()

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
    .package(url: "https://github.com/madmachineio/SwiftIO", from: "0.1.0"),
    .package(url: "https://github.com/PADL/IORingSwift.git", from: "0.1.2"),
    .package(url: "https://github.com/PADL/CLinuxGCD.git", from: "6.0.2"),
    .package(url: "https://github.com/apple/swift-async-algorithms", from: "1.0.0"),
    .package(url: "https://github.com/lhoward/AsyncExtensions", from: "0.9.0"),
    .package(url: "https://github.com/apple/swift-system", from: "1.0.0"),
  ],
  targets: [
    .target(
      name: "LinuxHalSwiftIO",
      dependencies: [
        .product(name: "CSwiftIO", package: "SwiftIO"),
                     .product(name: "CBlockHeaders", package: "CLinuxGCD"),
                     .product(name: "CDispatchHeaders", package: "CLinuxGCD")
      ],
      linkerSettings: [
        .linkedLibrary("gpiod", .when(platforms: [.linux])),
      ]
    ),
    .target(
      name: "AsyncSwiftIO",
      dependencies: [
        .product(name: "AsyncAlgorithms", package: "swift-async-algorithms"),
        .product(name: "SystemPackage", package: "swift-system"),
        "AsyncExtensions",
        .product(name: "SwiftIO", package: "SwiftIO"),
        "LinuxHalSwiftIO",
        .product(
          name: "IORing",
          package: "IORingSwift",
          condition: .when(platforms: [.linux])
        ),
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
