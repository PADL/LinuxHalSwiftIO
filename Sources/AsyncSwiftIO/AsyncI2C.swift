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
#if canImport(Glibc)
import Glibc
#endif
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
  private let blockSize: Int?

  public nonisolated var description: String {
    "\(type(of: self))(i2c: \(i2c))"
  }

  public init(with i2c: I2C, address: UInt8? = nil, blockSize: Int? = nil) async throws {
    self.i2c = i2c
    self.blockSize = blockSize
    fd = try rethrowingSystemErrnoAsSwiftIOErrno {
      try FileHandle(fileDescriptor: i2c.getFileDescriptor())
    }
    if let address {
      try i2c.withObj { swifthal_i2c_set_addr($0, address) }
    }

    if let blockSize {
      ring = try await rethrowingSystemErrnoAsSwiftIOErrno {
        let ring = try IORing()
        try await ring.registerFixedBuffers(count: 2, size: blockSize)
        return ring
      }
    } else {
      ring = IORing.shared
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

  public func writeRead(
    _ block: inout [UInt8],
    writeCount: Int? = nil,
    readCount: Int? = nil
  ) async throws {
    guard let blockSize else {
      throw SwiftIO.Errno.invalidArgument
    }

    try await rethrowingSystemErrnoAsSwiftIOErrno { [self] in
      try await ring.writeReadFixed(
        &block,
        writeCount: writeCount ?? blockSize,
        readCount: readCount ?? blockSize,
        bufferIndex: 0,
        fd: fd
      )
    }
  }
}
