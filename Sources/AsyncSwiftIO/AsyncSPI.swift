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

public actor AsyncSPI {
    private let spi: SPI
    private let wordLength: Int
    private var readChannel = AsyncThrowingChannel<[UInt8], Error>()
    private var writeChannel = AsyncChannel<[UInt8]>()
    private var readChannelTask: Task<(), Error>?

    public init(with spi: SPI) async {
        self.spi = spi
        self.wordLength = spi.wordLength == .thirtyTwoBits ? 4 : 1
        self.readChannelTask = Task { await _readChannel() }
        Task { await _writeChannel() }
    }

    deinit {
        writeChannel.finish()
        readChannel.finish()
    }

    private func _writeChannel() async {
        for await data in writeChannel {
            _asyncWrite(data)
        }
    }

    private func _asyncWrite(_ data: [UInt8]) {
        data.withUnsafeBytes { bytes in
#if canImport(Darwin)
            // this should work, but is dependent on the struct layout of DispatchData starting
            // with __DispatchData (aka dispatch_data_t). Anyway, we don't actually need things
            // to _work_ on Darwin, only compile
            let dispatchData = unsafeBitCast(DispatchData(bytes: bytes), to: UnsafeRawPointer.self)
#else
            // allocate a buffer as the data may outlive the lifetime of the channel data
            let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: bytes.count)
            memcpy(&buffer[0], bytes.baseAddress!, bytes.count)
            let dispatchData = dispatch_data_create(
                buffer,
                bytes.count,
                swifthal_spi_async_get_queue(self.spi.obj)) { buffer.deallocate() }
#endif
            swifthal_spi_async_write_with_handler(self.spi.obj, dispatchData) { _, _ in }
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

    private func _readChannel() async {
        repeat {
            _asyncRead()
        } while !(self.readChannelTask?.isCancelled ?? true)
    }

    private func _asyncRead() {
        swifthal_spi_async_read_with_handler(self.spi.obj, wordLength) { data, error in
            Task {
                guard error == 0 else {
                    self.readChannel.fail(Errno(error))
                    self.readChannelTask?.cancel()
                    return
                }

#if canImport(Darwin)
                let dispatchData = unsafeBitCast(data, to: DispatchData.self)
                var bytes: [UInt8]!
                dispatchData.withUnsafeBytes {
                    bytes = Array($0)
                }
                await self.readChannel.send(bytes)
#else
                dispatch_data_apply(data) { region, offset, buffer, size in
                    let bytes = Array(UnsafeBufferPointer<UInt8>(
                        start: buffer.assumingMemoryBound(to: UInt8.self),
                        count: size
                    ))
                    Task { await self.readChannel.send(bytes) }
                    return true
                }
#endif
            }
        }
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
