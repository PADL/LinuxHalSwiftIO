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
import IORing
import LinuxHalSwiftIO
import SwiftIO

private extension SPI {
    func getFileDescriptor() -> CInt {
        guard let obj = getObj(self) else { return -1 }
        return swifthal_spi_get_fd(obj)
    }
}

public actor AsyncSPI: CustomStringConvertible {
    private let ring: IORing
    private let spi: SPI
    private let fd: FileHandle
    private let blockSize: Int?
    private let dataAvailableInput: DigitalIn?

    private typealias Continuation = CheckedContinuation<(), Error>
    private var waiters = Queue<Continuation>()

    public nonisolated var description: String {
        if let dataAvailableInput {
            return "\(type(of: self))(spi: \(spi), blockSize: \(blockSize ?? 0), dataAvailableInput: \(dataAvailableInput))"
        } else {
            return "\(type(of: self))(spi: \(spi), blockSize: \(blockSize ?? 0))"
        }
    }

    // TODO: move data available pin into SPI library
    public init(
        with spi: SPI,
        blockSize: Int? = nil,
        dataAvailableInput: DigitalIn? = nil
    ) async throws {
        self.spi = spi
        fd = try FileHandle(fileDescriptor: spi.getFileDescriptor())
        self.blockSize = blockSize
        self.dataAvailableInput = dataAvailableInput

        if let blockSize {
            ring = try IORing()
            try await ring.registerFixedBuffers(count: 2, size: blockSize)
        } else {
            ring = IORing.shared
        }

        if let dataAvailableInput {
            dataAvailableInput.setInterrupt(.rising) {
                Task { await self.resumeWaiters() }
            }
        }
    }

    public func write(_ data: [UInt8]) async throws {
        try await rethrowingIORingErrno { [self] in
            try await ring.write(data, to: fd)
        }
    }

    public func read(_ count: Int) async throws -> [UInt8] {
        try await dataAvailable()

        return try await rethrowingIORingErrno { [self] in
            try await ring.read(count: count, from: fd)
        }
    }

    public func writeBlock(_ block: [UInt8]) async throws {
        guard let blockSize else {
            throw SwiftIO.Errno.invalidArgument
        }

        if try await ring.writeFixed(block, count: blockSize, bufferIndex: 0, to: fd) != blockSize {
            throw SwiftIO.Errno.resourceTemporarilyUnavailable
        }
    }

    public func readBlock() async throws -> [UInt8] {
        guard let blockSize else {
            throw SwiftIO.Errno.invalidArgument
        }

        try await dataAvailable()
        return try await ring.readFixed(count: blockSize, bufferIndex: 1, from: fd) {
            Array($0)
        }
    }

    public func transceiveBlock(_ block: inout [UInt8]) async throws {
        guard let blockSize else {
            throw SwiftIO.Errno.invalidArgument
        }

        try await ring.writeReadFixed(&block, count: blockSize, bufferIndex: 0, fd: fd)
    }

    private func dataAvailable() async throws {
        guard let dataAvailableInput else {
            return
        }

        try await withCheckedThrowingContinuation { waiter in
            waiters.enqueue(waiter)
        }
    }

    private func resumeWaiters() async {
        while let waiter = waiters.dequeue() {
            waiter.resume()
        }
    }

    deinit {
        while let waiter = waiters.dequeue() {
            waiter.resume(throwing: SwiftIO.Errno.canceled)
        }
    }
}
