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
    public private(set) var readChannel = AsyncThrowingChannel<[UInt8], Error>()
    private var writeChannel = AsyncChannel<[UInt8]>()
    private var readChannelTask: Task<(), Error>?

    public nonisolated var description: String {
        "\(type(of: self))(spi: \(spi), blockSize: \(blockSize))"
    }

    public init(with spi: SPI, blockSize: Int? = nil) {
        self.spi = spi
        swifthal_spi_async_enable(spi.obj)
        if let blockSize {
            self.blockSize = blockSize
        } else {
            self.blockSize = 1
        }

        Task {
            await readChannelInitTask()
            try await writeChannelRun()
        }
    }

    deinit {
        writeChannel.finish()
        readChannel.finish()
    }

    private func writeChannelRun() async throws {
        for await data in writeChannel {
            try asyncWrite(data)
        }
    }

    private func asyncWrite(_ data: [UInt8]) throws {
        let result = data.withUnsafeBytes { bytes in
            nothingOrErrno(
                swifthal_spi_async_write_with_handler(
                    self.spi.obj,
                    bytes.baseAddress!,
                    bytes.count
                ) { _, _, _, _ in true }
            )
        }

        if case let .failure(error) = result {
            throw error
        }
    }

    public func write(_ data: [UInt8], count: Int? = nil) async throws {
        var writeLength = 0
        let result = validateLength(data, count: count, length: &writeLength)

        if case let .failure(error) = result {
            throw error
        }

        if writeLength % blockSize != 0 {
            throw Errno.invalidArgument
        }

        await writeChannel.send(Array(data[0..<writeLength]))
    }

    private func readChannelInitTask() {
        readChannelTask = Task {
            await readChannelRun()
        }
    }

    private func readChannelRun() async {
        repeat {
            asyncRead()
        } while !(readChannelTask?.isCancelled ?? true)
    }

    private func asyncRead() {
        swifthal_spi_async_read_with_handler(spi.obj, blockSize) { _, data, count, error in
            Task {
                guard error == 0 else {
                    self.readChannel.fail(Errno(error))
                    self.readChannelTask?.cancel()
                    return
                }

                let bytes = Array(UnsafeBufferPointer<UInt8>(start: data, count: count))
                await self.readChannel.send(bytes)
            }
            return true // FIXME: check this
        }
    }

    public func read(into buffer: inout [UInt8], count: Int? = nil) async throws -> Int {
        var readLength = 0
        let result = validateLength(buffer, count: count, length: &readLength)

        if case let .failure(error) = result {
            throw error
        }

        if readLength % blockSize != 0 {
            throw Errno.invalidArgument
        }

        var bytesRead = 0

        for try await data in readChannel {
            memcpy(&buffer[bytesRead], data, data.count)
            bytesRead += data.count

            if bytesRead == readLength {
                break
            }
        }

        return bytesRead
    }
}
