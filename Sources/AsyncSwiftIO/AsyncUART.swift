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
import ErrNo
import Foundation // workaround for apple/swift#66664
import IORing
import LinuxHalSwiftIO
import SwiftIO

public actor AsyncUART: CustomStringConvertible {
    private let ring: IORing
    private let uart: UART
    public let readBufferLength: Int

    public nonisolated var description: String {
        "\(type(of: self))(uart: \(uart))"
    }

    public init(with uart: UART) throws {
        guard let ring = IORing.shared else {
            throw Errno.invalidArgument
        }

        self.ring = ring
        self.uart = uart
        var cfg = swift_uart_cfg_t()
        swifthal_uart_config_get(uart.obj, &cfg)
        readBufferLength = Int(cfg.read_buf_len)
    }

    public func write(_ data: [UInt8]) async throws {
        try await ErrNo.rethrowingErrno { [self] in
            try await ring.write(data, to: uart.fd)
        }
    }

    public func read(_ count: Int) async throws -> [UInt8] {
        try await ErrNo.rethrowingErrno { [self] in
            try await ring.read(count: count, from: uart.fd)
        }
    }
}

extension UART {
    var fd: CInt {
        swifthal_uart_get_fd(obj)
    }
}
