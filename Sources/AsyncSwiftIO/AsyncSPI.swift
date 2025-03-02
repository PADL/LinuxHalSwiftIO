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

import CSwiftIO
#if canImport(IORing)
import IORing
#endif
import LinuxHalSwiftIO
@_spi(SwiftIOPrivate)
import SwiftIO

private extension SPI {
  func getFileDescriptor() -> CInt {
    swifthal_spi_get_fd(obj)
  }
}

public actor AsyncSPI: CustomStringConvertible {
  private let ring: IORing
  private let spi: SPI
  private let fd: FileHandle
  private let blockSize: Int?

  private typealias Continuation = CheckedContinuation<(), Error>

  public nonisolated var description: String {
    "\(type(of: self))(spi: \(spi), blockSize: \(blockSize ?? 0))"
  }

  // TODO: move data available pin into SPI library
  public init(
    with spi: SPI,
    blockSize: Int? = nil
  ) async throws {
    self.spi = spi
    fd = try rethrowingSystemErrnoAsSwiftIOErrno {
      try FileHandle(fileDescriptor: spi.getFileDescriptor())
    }
    self.blockSize = blockSize

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

  public func writeBlock(_ block: [UInt8]) async throws -> Int {
    guard let blockSize, block.count <= blockSize else {
      throw SwiftIO.Errno.invalidArgument
    }

    return try await rethrowingSystemErrnoAsSwiftIOErrno { [self] in
      try await ring.writeFixed(block, bufferIndex: 0, to: fd)
    }
  }

  public func readBlock(_ count: Int? = nil) async throws -> [UInt8] {
    guard let blockSize else {
      throw SwiftIO.Errno.invalidArgument
    }

    return try await rethrowingSystemErrnoAsSwiftIOErrno { [self] in
      try await ring.readFixed(count: count ?? blockSize, bufferIndex: 1, from: fd) {
        Array($0)
      }
    }
  }

  public func transceiveBlock(_ block: inout [UInt8], count: Int? = nil) async throws {
    guard let blockSize else {
      throw SwiftIO.Errno.invalidArgument
    }

    try await rethrowingSystemErrnoAsSwiftIOErrno { [self] in
      try await ring.writeReadFixed(
        &block,
        writeCount: count ?? blockSize,
        readCount: count ?? blockSize,
        bufferIndex: 0,
        fd: fd
      )
    }
  }
}
