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
public enum SPIDumper {
    public static func main() {
        var device: Int32!

        if CommandLine.arguments.count > 1 {
            device = Int32(CommandLine.arguments[1])
        }

        if device == nil {
            device = 0
        }

        let spi = SPI(Id(device))

        Task {
            let asyncSpi = await AsyncSPI(with: spi)

            debugPrint("Initialized async SPI handle \(asyncSpi)...")

            for try await data in await asyncSpi.readChannel {
                debugPrint(Data(data).hexDescription)
            }
        }
        RunLoop.main.run()
    }
}

// https://stackoverflow.com/questions/39075043/how-to-convert-data-to-hex-string-in-swift
extension Data {
    var hexDescription: String {
        reduce("") { $0 + String(format: "%02x", $1) }
    }
}
