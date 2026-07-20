// swift-tools-version: 6.3
// The @c attribute used by the native-Swift HAL requires the Swift 6.3 compiler;
// gate older toolchains here rather than failing mid-build with cryptic errors.

import Foundation
import PackageDescription

let EnvSysRoot = ProcessInfo.processInfo.environment["SYSROOT"]

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

let SwiftLibRoot = EnvSysRoot != nil ? "\(EnvSysRoot!)/usr/lib/swift" : tryGuessSwiftLibRoot()

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
    .package(url: "https://github.com/PADL/IORingSwift", from: "1.0.0"),
    .package(url: "https://github.com/apple/swift-async-algorithms", from: "1.0.0"),
    .package(url: "https://github.com/lhoward/AsyncExtensions", from: "0.9.0"),
    .package(url: "https://github.com/apple/swift-system", from: "1.0.0"),
  ],
  targets: [
    // Residual C the Swift HAL calls (inline-assembly hwcycle, termios2 UART
    // helpers, fs mount point, ioctl/mq/syslog shims) plus the public HAL headers.
    .target(
      name: "CLinuxHalSwiftIO",
      dependencies: [
        .product(name: "CSwiftIO", package: "SwiftIO"),
      ],
      linkerSettings: [
        .linkedLibrary("gpiod", .when(platforms: [.linux])),
      ]
    ),
    // Native-Swift HAL implementation. Exports the same C ABI via @c and
    // re-exports the C module so `import LinuxHalSwiftIO` still surfaces the
    // HAL declarations to consumers (AsyncSwiftIO, SwiftIO).
    .target(
      name: "LinuxHalSwiftIO",
      dependencies: [
        "CLinuxHalSwiftIO",
        .product(name: "CSwiftIO", package: "SwiftIO"),
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
  ],
  // Keep the Swift 5 language mode the package built with under tools 5.7.
  swiftLanguageModes: [.v5]
)
