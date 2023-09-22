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
import ErrNo
import Foundation // workaround for apple/swift#66664
import IORing
import LinuxHalSwiftIO
import SwiftIO

public actor AsyncSPI: CustomStringConvertible {
    private let ring: IORing
    private let spi: SPI
    private let blockSize: Int
    private let dataAvailableInput: DigitalIn?

    private typealias Continuation = CheckedContinuation<(), Error>
    private var waiters = Queue<Continuation>()

    public nonisolated var description: String {
        if let dataAvailableInput {
            return "\(type(of: self))(spi: \(spi), blockSize: \(blockSize), dataAvailableInput: \(dataAvailableInput))"
        } else {
            return "\(type(of: self))(spi: \(spi), blockSize: \(blockSize))"
        }
    }

    // TODO: move data available pin into SPI library
    public init(with spi: SPI, blockSize: Int = 1, dataAvailableInput: DigitalIn? = nil) throws {
        guard let ring = IORing.shared else {
            throw Errno.invalidArgument
        }

        self.ring = ring
        self.spi = spi
        self.blockSize = blockSize
        self.dataAvailableInput = dataAvailableInput

        if let dataAvailableInput {
            dataAvailableInput.setInterrupt(.rising) {
                if dataAvailableInput.read() {
                    Task { await self.resumeWaiters() }
                }
            }
        }
    }

    public func write(_ data: [UInt8]) async throws {
        if data.count % blockSize != 0 {
            throw Errno.invalidArgument
        }

        try await ErrNo.rethrowingErrno { [self] in
            try await ring.write(data, to: spi.fd)
        }
    }

    public func read(_ count: Int) async throws -> [UInt8] {
        if count % blockSize != 0 {
            throw Errno.invalidArgument
        }

        try await dataAvailable()

        return try await ErrNo.rethrowingErrno { [self] in
            try await ring.read(count: count, from: spi.fd)
        }
    }

    private func dataAvailable() async throws {
        guard let dataAvailableInput else {
            return
        }

        if dataAvailableInput.read() {
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
            waiter.resume(throwing: Errno.canceled)
        }
    }
}

extension SPI {
    var fd: CInt {
        swifthal_spi_get_fd(obj)
    }
}
