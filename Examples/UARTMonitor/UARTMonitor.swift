import AsyncSwiftIO
import Foundation
import SwiftIO

@main
public enum UARTMonitor {
  public static func main() async throws {
    var device: Int32!
    let blockSize: Int

    if CommandLine.arguments.count > 1 {
      device = Int32(CommandLine.arguments[1])
    }
    if CommandLine.arguments.count > 2 {
      blockSize = Int(CommandLine.arguments[2])!
    } else {
      blockSize = 16
    }

    let uart = UART(Id(rawValue: device ?? 1), readBufferLength: blockSize)
    let asyncUart = try await AsyncUART(with: uart)

    debugPrint("Initialized async UART handle \(asyncUart) from UART \(uart)...")

    repeat {
      let data = try await asyncUart.readBlock()
      print([UInt8](data))
    } while true
  }
}

private func print(_ data: [UInt8]) {
  Swift.print(data.map { String(format: "%02x", $0) }.joined())
}
