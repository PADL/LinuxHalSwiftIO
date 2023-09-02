import XCTest
@testable import LinuxHalSwiftIO

final class LinuxHalSwiftIOTests: XCTestCase {
    func testExample() throws {
        // This is an example of a functional test case.
        // Use XCTAssert and related functions to verify your tests produce the correct
        // results.
        XCTAssertEqual(LinuxHalSwiftIO().text, "Hello, World!")
    }
}
