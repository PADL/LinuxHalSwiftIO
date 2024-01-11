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
import IORing
import LinuxHalSwiftIO
import SwiftIO

private extension UART {
    func getFileDescriptor() -> CInt {
        guard let obj = getObj(self) else { return -1 }
        return swifthal_uart_get_fd(obj)
    }
}

public actor AsyncUART: CustomStringConvertible {
    private let ring: IORing
    private let uart: UART
    private let fd: FileHandle
    public let blockSize: Int

    public nonisolated var description: String {
        "\(type(of: self))(uart: \(uart))"
    }

    public init(with uart: UART) async throws {
        self.uart = uart
        fd = try FileHandle(fileDescriptor: uart.getFileDescriptor())
        var cfg = swift_uart_cfg_t()
        swifthal_uart_config_get(getObj(uart), &cfg)
        blockSize = Int(cfg.read_buf_len)

        if blockSize > 1 {
            ring = try IORing()
            try await ring.registerFixedBuffers(count: 2, size: blockSize)
        } else {
            ring = IORing.shared
        }
    }

    public func write(_ data: [UInt8]) async throws -> Int {
        try await rethrowingIORingErrno { [self] in
            try await ring.write(data, to: fd)
        }
    }

    public func read(_ count: Int) async throws -> [UInt8] {
        try await rethrowingIORingErrno { [self] in
            try await ring.read(count: count, from: fd)
        }
    }

    public func writeBlock(_ block: [UInt8]) async throws -> Int {
        guard blockSize > 1, block.count <= blockSize else {
            throw SwiftIO.Errno.invalidArgument
        }

        return try await ring.writeFixed(block, bufferIndex: 0, to: fd)
    }

    public func readBlock(_ count: Int? = nil) async throws -> [UInt8] {
        guard blockSize > 1 else {
            throw SwiftIO.Errno.invalidArgument
        }

        return try await ring.readFixed(count: count ?? blockSize, bufferIndex: 1, from: fd) {
            Array($0)
        }
    }
}
