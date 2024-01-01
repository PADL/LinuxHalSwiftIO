//
// Copyright (c) 2024 PADL Software Pty Ltd
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
import LinuxHalSwiftIO
import SwiftIO

private extension DigitalIn {
    func interruptCallbackInstall(_ callback: @escaping (UInt8) -> ()) throws {
        guard let obj = getObj(self) else { throw Errno.invalidArgument }
        let err = swifthal_gpio_interrupt_callback_install_block(obj, callback)
        guard err == 0 else { throw Errno(err) }
    }
}

public extension DigitalIn {
    var interrupts: AsyncThrowingStream<Bool, Error> {
        AsyncThrowingStream { continuation in
            do {
                try interruptCallbackInstall { risingEdge in
                    continuation.yield(risingEdge != 0)
                }
            } catch {
                continuation.finish(throwing: error)
            }
            continuation.onTermination = { @Sendable _ in
                self.disableInterrupt()
            }
            self.enableInterrupt()
        }
    }
}
