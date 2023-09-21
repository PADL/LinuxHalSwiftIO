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

public actor AsyncUART: CustomStringConvertible {
    private let uart: UART
    public private(set) var readChannel = AsyncThrowingChannel<[UInt8], Error>()
    private var writeChannel = AsyncChannel<[UInt8]>()
    private let readBufferLength: Int

    public nonisolated var description: String {
        "\(type(of: self))(uart: \(uart))"
    }

    public init(with uart: UART) {
        self.uart = uart
        var cfg = swift_uart_cfg_t()
        swifthal_uart_config_get(uart.obj, &cfg)
        readBufferLength = Int(cfg.read_buf_len)

        Task {
            await readChannelRun()
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
    }

    public func write(_ data: [UInt8], count: Int? = nil) async throws {
        var writeLength = 0
        let result = validateLength(data, count: count, length: &writeLength)

        if case let .failure(error) = result {
            throw error
        }

        await writeChannel.send(Array(data[0..<writeLength]))
    }

    private func readChannelRun() {
    }

    public func read(into buffer: inout [UInt8], count: Int? = nil) async throws -> Int {
        var readLength = 0
        let result = validateLength(buffer, count: count, length: &readLength)

	return -1
    }
}
