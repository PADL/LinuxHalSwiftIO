import AsyncSwiftIO
import Foundation
import SwiftIO

private struct Id: IdName {
    var value: Int32

    init(_ value: Int32) {
        self.value = value
    }
}

@main
public enum UARTDumper {
    public static func main() async throws {
        var device: Int32!

        if CommandLine.arguments.count > 1 {
            device = Int32(CommandLine.arguments[1])
        }

        if device == nil {
            device = 0
        }

        let uart = UART(Id(device))
        let asyncUart = try AsyncUART(with: uart)

        debugPrint("Initialized async UART handle \(asyncUart)...")

        repeat {
            let data = try await asyncUart.read(asyncUart.readBufferLength)
            debugPrint(Data(data).hexDescription)
        } while true
    }
}

// https://stackoverflow.com/questions/39075043/how-to-convert-data-to-hex-string-in-swift
extension Data {
    var hexDescription: String {
        reduce("") { $0 + String(format: "%02x", $1) }
    }
}
