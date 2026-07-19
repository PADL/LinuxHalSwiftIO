import AsyncSwiftIO
@testable import LinuxHalSwiftIO
import SwiftIO
import XCTest

// assumes MISO connected to MOSI for loopback

final class LinuxHalSwiftIOTests: XCTestCase {
  // Constructed lazily: SPI.init asserts when /dev/spidev1.0 is absent, so an
  // eager stored property would crash test discovery on any machine without SPI
  // hardware (and take the rest of the bundle's tests down with it).
  lazy var spi = SPI(Id(rawValue: 1), speed: 1000, bitOrder: .MSB)

  func testSpiLoopbackTransceive() throws {
    let writeBuffer: [UInt8] = [1, 2, 3, 4, 10, 11, 12, 13, 0xFF, 0]
    var readBuffer = [UInt8](repeating: 0xFF, count: writeBuffer.count)

    _ = spi.transceive(writeBuffer, into: &readBuffer)

    XCTAssertEqual(writeBuffer, readBuffer)
  }
}
