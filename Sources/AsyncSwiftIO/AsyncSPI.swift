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
import CSwiftIO
import Foundation // workaround for apple/swift#66664
import LinuxHalSwiftIO
import SwiftIO

#if os(Linux)
private extension dispatch_source_t {
    var data: UInt {
        dispatch_source_get_data(self)
    }
}
#endif

public actor AsyncSPI {
    private let spi: SPI
    private var readChannel = AsyncThrowingChannel<[UInt8], Error>()
    private var writeChannel = AsyncChannel<[UInt8]>()

#if os(Linux)
    typealias DispatchSource = dispatch_source_t
#endif

    public init(with spi: SPI) {
        self.spi = spi

        swifthal_spi_write_notification_handler_set(spi.obj) { source in
            Task { try await self.writeReady(source) }
        }

        swifthal_spi_read_notification_handler_set(spi.obj) { source in
            Task { await self.readReady(source) }
        }
    }

    private func writeReady(_ source: DispatchSource) async throws {
        for await data in writeChannel {
            let result = valueOrErrno(
                data.withUnsafeBytes { bytes in
                    swifthal_spi_write(self.spi.obj, bytes.baseAddress, CInt(bytes.count))
                }
            )
            if case let .failure(error) = result {
                throw error
            }
            if source.data == 0 {
                break
            }
        }
    }

    public func write(_ data: [UInt8], count: Int? = nil) async throws {
        var writeLength = 0
        let result = validateLength(data, count: count, length: &writeLength)

        if case let .failure(error) = result {
            throw error
        }

        if spi.wordLength == .thirtyTwoBits && (writeLength % 4) != 0 {
            throw Errno.invalidArgument
        }

        await writeChannel.send(Array(data[0..<writeLength]))
    }

    private func readReady(_ source: DispatchSource) async {
        repeat {
            let wordLength: Int32 = spi.wordLength == .thirtyTwoBits ? 4 : 1
            var buffer = [UInt8](repeating: 0, count: Int(wordLength))
            let result = valueOrErrno(
                buffer.withUnsafeMutableBytes { bytes in
                    swifthal_spi_read(self.spi.obj, bytes.baseAddress, wordLength)
                }
            )

            if case let .failure(error) = result {
                readChannel.fail(error)
            } else {
                await readChannel.send(buffer)
            }
        } while source.data != 0
    }

    public func read(into buffer: inout [UInt8], count: Int? = nil) async throws -> Int {
        var readLength = 0
        let result = validateLength(buffer, count: count, length: &readLength)

        if case let .failure(error) = result {
            throw error
        }

        if spi.wordLength == .thirtyTwoBits && (readLength % 4) != 0 {
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
