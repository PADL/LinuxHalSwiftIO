//
// Copyright (c) 2026 PADL Software Pty Ltd
//
// Licensed under the Apache License, Version 2.0 (the License);
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//     http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an 'AS IS' BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.
//

@testable import LinuxHalSwiftIO
import XCTest

// Exercises the native-Swift HAL primitives (OS + platform) that do not require
// peripheral hardware, complementing the SPI loopback test.
final class HALNativeTests: XCTestCase {
  func testSemaphoreLimitEnforced() throws {
    // init_cnt = 0, limit = 2: give() must cap the count at 2 even when called
    // more often, and exactly two takes should then succeed.
    guard let sem = swifthal_os_sem_create(0, 2) else {
      return XCTFail("sem_create failed")
    }
    defer { XCTAssertEqual(swifthal_os_sem_destroy(sem), 0) }

    XCTAssertEqual(swifthal_os_sem_give(sem), 0)
    XCTAssertEqual(swifthal_os_sem_give(sem), 0)
    XCTAssertEqual(swifthal_os_sem_give(sem), 0) // over the limit: no-op, no error

    XCTAssertEqual(swifthal_os_sem_take(sem, 10), 0)
    XCTAssertEqual(swifthal_os_sem_take(sem, 10), 0)
    // Third take must time out: the limit held the count at 2.
    XCTAssertLessThan(swifthal_os_sem_take(sem, 10), 0)
  }

  func testMutexLockUnlock() throws {
    guard let mutex = swifthal_os_mutex_create() else {
      return XCTFail("mutex_create failed")
    }
    defer { XCTAssertEqual(swifthal_os_mutex_destroy(mutex), 0) }

    XCTAssertEqual(swifthal_os_mutex_lock(mutex, -1), 0)
    XCTAssertEqual(swifthal_os_mutex_unlock(mutex), 0)
  }

  func testRandomGetFillsBuffer() throws {
    var buf = [UInt8](repeating: 0, count: 64)
    buf.withUnsafeMutableBufferPointer {
      swifthal_random_get($0.baseAddress, $0.count)
    }
    // A 64-byte all-zero result from a working RNG is astronomically unlikely.
    XCTAssertTrue(buf.contains { $0 != 0 })
  }

  func testUptimeIsPositive() throws {
    XCTAssertGreaterThan(swifthal_uptime_get(), 0)
  }
}
