@testable import LinuxHalSwiftIO
import SwiftIO
import AsyncSwiftIO
import XCTest

// these tests aren't going to work on all devices, of course

struct Id: IdName {
    var value: Int32

    init(_ value: Int32) {
        self.value = value;
    }
}

final class LinuxHalSwiftIOTests: XCTestCase {
    func testSpiLoopbackSync() throws {
        let spi = SPI(Id(0), loopback: true)

        let writeBuffer: [UInt8] = [0xca, 0xfe, 0xba, 0xbe]
        var readBuffer = [UInt8](repeating: 0, count: 4)

        let result = spi.transceive(writeBuffer, into: &readBuffer)
        XCTAssertEqual(writeBuffer, readBuffer)
    }
}
