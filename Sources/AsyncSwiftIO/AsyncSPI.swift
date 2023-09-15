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
import Foundation // workaround for apple/swift#66664
import LinuxHalSwiftIO
import SwiftIO

public actor AsyncSPI: CustomStringConvertible {
    private let spi: SPI
    private let blockSize: Int
    private let dataAvailableInput: DigitalIn?
    private var dataAvailable: Bool = true

    public nonisolated var description: String {
        if let dataAvailableInput {
            return "\(type(of: self))(spi: \(spi), blockSize: \(blockSize), dataAvailableInput: \(dataAvailableInput))"
        } else {
            return "\(type(of: self))(spi: \(spi), blockSize: \(blockSize))"
        }
    }

    private func dataAvailableInterrupt() {
        if let dataAvailableInput {
            dataAvailable = dataAvailableInput.read()
        }
    }

    // TODO: move data available pin into SPI library
    public init(with spi: SPI, blockSize: Int = 1, dataAvailableInput: DigitalIn? = nil) throws {
        self.spi = spi
        self.blockSize = blockSize
        self.dataAvailableInput = dataAvailableInput

        let result = nothingOrErrno(swifthal_spi_async_enable(spi.obj))
        if case let .failure(error) = result {
            throw error
        }

        if let dataAvailableInput {
            dataAvailableInput.setInterrupt(.rising) {
                Task {
                    await self.dataAvailableInterrupt()
                }
            }
        }
    }

    public func write(_ data: [UInt8]) async throws -> Int {
        if data.count % blockSize != 0 {
            throw Errno.invalidArgument
        }

        return try await withCheckedThrowingContinuation { continuation in
            data.withUnsafeBytes { bytes in
                let result = nothingOrErrno(
                    swifthal_spi_async_write_with_handler(
                        spi.obj,
                        bytes.baseAddress!,
                        bytes.count
                    ) { _, _, _, _ in
                        continuation.resume(returning: data.count)
                        return true
                    }
                )
                if case let .failure(error) = result {
                    continuation.resume(throwing: error)
                    return
                }
            }
        }
    }

    public func read(_ count: Int) async throws -> [UInt8] {
        if count % blockSize != 0 {
            throw Errno.invalidArgument
        }

        return try await withCheckedThrowingContinuation { continuation in
            swifthal_spi_async_read_with_handler(spi.obj, count) { _, data, count, error in
                guard error == 0 else {
                    continuation.resume(throwing: Errno(error))
                    return true
                }

                let bytes: [UInt8]

                if let data {
                    bytes = Array(UnsafeBufferPointer<UInt8>(start: data, count: count))
                } else {
                    bytes = []
                }
                continuation.resume(returning: bytes)
                return true
            }
        }
    }
}
