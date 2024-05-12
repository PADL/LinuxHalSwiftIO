import AsyncSwiftIO
@testable import LinuxHalSwiftIO
import SwiftIO
import XCTest

// assumes MISO connected to MOSI for loopback

private struct Id: IdName {
  var value: Int32

  init(_ value: Int32) {
    self.value = value
  }
}

final class LinuxHalSwiftIOTests: XCTestCase {
  let spi = SPI(Id(1), speed: 1000, bitOrder: .MSB)

  func testSpiLoopbackTransceive() throws {
    let writeBuffer: [UInt8] = [1, 2, 3, 4, 10, 11, 12, 13, 0xFF, 0]
    var readBuffer = [UInt8](repeating: 0xFF, count: writeBuffer.count)

    _ = spi.transceive(writeBuffer, into: &readBuffer)

    XCTAssertEqual(writeBuffer, readBuffer)
  }
}
