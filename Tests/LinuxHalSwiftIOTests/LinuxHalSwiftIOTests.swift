import AsyncSwiftIO
@testable import LinuxHalSwiftIO
import SwiftIO
import XCTest

// these tests aren't going to work on all devices, of course

struct Id: IdName {
    var value: Int32

    init(_ value: Int32) {
        self.value = value
    }
}

final class LinuxHalSwiftIOTests: XCTestCase {
    func testSpiLoopbackSync() throws {
        let spi = SPI(Id(0), loopback: true)

        let writeBuffer: [UInt8] = [0xCA, 0xFE, 0xBA, 0xBE]
        var readBuffer = [UInt8](repeating: 0xFF, count: 4)

        _ = spi.transceive(writeBuffer, into: &readBuffer)
        XCTAssertEqual(writeBuffer, readBuffer)
    }

    func testSpiLoopbackAsync() async throws {
        let spi = await AsyncSPI(with: SPI(Id(0), loopback: true))
        let writeBuffer: [UInt8] = [0xCA, 0xFE, 0xBA, 0xBE]
        var readBuffer = [UInt8](repeating: 0xFF, count: 4)
        let bufferExpectation = XCTestExpectation(description: "Read/write buffer matching")

        try await spi.write(writeBuffer)
        _ = try await spi.read(into: &readBuffer)
        XCTAssertEqual(writeBuffer, readBuffer)
        bufferExpectation.fulfill()
        wait(for: [bufferExpectation], timeout: 1)
    }
}
