//
// Copyright (c) 2023 PADL Software Pty Ltd
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

import AsyncAlgorithms
import AsyncExtensions
import CSwiftIO
import Glibc
#if canImport(IORing)
import IORing
#endif
import LinuxHalSwiftIO
@_spi(SwiftIOPrivate)
import SwiftIO

private extension I2C {
  func getFileDescriptor() -> CInt {
    swifthal_i2c_get_fd(obj)
  }

  func withObj(_ body: (_: UnsafeMutableRawPointer) -> CInt) throws(SwiftIO.Errno) {
    let err = body(obj)
    guard err == 0 else { throw SwiftIO.Errno(err) }
  }
}

public actor AsyncI2C: CustomStringConvertible {
  private let ring: IORing
  private let i2c: I2C
  private let fd: FileHandle

  public nonisolated var description: String {
    "\(type(of: self))(i2c: \(i2c))"
  }

  public init(with i2c: I2C, address: UInt8? = nil) throws {
    ring = IORing.shared
    self.i2c = i2c
    fd = try rethrowingSystemErrnoAsSwiftIOErrno {
      try FileHandle(fileDescriptor: i2c.getFileDescriptor())
    }
    if let address {
      try i2c.withObj { swifthal_i2c_set_addr($0, address) }
    }
  }

  public func write(_ data: [UInt8]) async throws -> Int {
    try await rethrowingSystemErrnoAsSwiftIOErrno { [self] in
      try await ring.write(data, to: fd)
    }
  }

  public func read(_ count: Int) async throws -> [UInt8] {
    try await rethrowingSystemErrnoAsSwiftIOErrno { [self] in
      try await ring.read(count: count, from: fd)
    }
  }
}
