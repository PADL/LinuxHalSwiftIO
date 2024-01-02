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

import AsyncAlgorithms
import CSwiftIO
import Foundation
import LinuxHalSwiftIO
import SwiftIO

//
// maps GPIO interrupts (events in Linux parlance) to an async stream of
// (Bool, Date) tuples indicating whether a rising edge was received and
// an approximate timestamp, respectively.
//
// This is not safe to use with the SwiftIO DigitalIn callback API as only
// a single callback can be registered at a time. Choose one.
//

private func getInterruptModeRawValue(
    _ mode: DigitalIn.InterruptMode
) -> swift_gpio_int_mode_t {
    switch mode {
    case .rising:
        return SWIFT_GPIO_INT_MODE_RISING_EDGE
    case .falling:
        return SWIFT_GPIO_INT_MODE_FALLING_EDGE
    case .bothEdge:
        return SWIFT_GPIO_INT_MODE_BOTH_EDGE
    }
}

private extension DigitalIn {
    func withObj(_ body: (_: UnsafeMutableRawPointer) -> CInt) throws {
        guard let obj = getObj(self) else { throw SwiftIO.Errno.invalidArgument }
        let err = body(obj)
        guard err == 0 else { throw SwiftIO.Errno(err) }
    }

    func _setInterruptBlock(
        _ mode: DigitalIn.InterruptMode,
        callback: @escaping (UInt8, timespec) -> ()
    ) throws {
        try withObj { obj in
            swifthal_gpio_interrupt_config(obj, getInterruptModeRawValue(mode))
        }
        try withObj { obj in
            swifthal_gpio_interrupt_callback_install_block(obj, callback)
        }
    }

    func _enableInterrupt() throws {
        try withObj { obj in
            swifthal_gpio_interrupt_enable(obj)
        }
    }

    func _disableInterrupt() throws {
        try withObj { obj in
            swifthal_gpio_interrupt_disable(obj)
        }
    }
}

public extension DigitalIn {
    typealias Interrupt = (Bool, Date) // is rising and timestamp
    typealias InterruptStream = AsyncThrowingRemoveDuplicatesSequence<AsyncThrowingStream<Interrupt, Error>>

    var interrupts: InterruptStream {
        AsyncThrowingStream { continuation in
            do {
                try _setInterruptBlock(.bothEdge) { risingEdge, ts in
                    let timeInterval = TimeInterval(ts.tv_sec + ts.tv_nsec / 1_000_000_000)
                    continuation.yield((risingEdge != 0, Date(timeIntervalSince1970: timeInterval)))
                }
            } catch {
                continuation.finish(throwing: error)
            }
            continuation.onTermination = { @Sendable _ in
                try? self._disableInterrupt()
            }
            try! self._enableInterrupt()
        }.removeDuplicates { $0.0 == $1.0 }
    }

    typealias EdgeInterruptStream = AsyncMapSequence<AsyncFilterSequence<InterruptStream>, Date>

    var risingEdgeInterrupts: EdgeInterruptStream {
        interrupts.filter { $0.0 }.map { $0.1 }
    }

    var fallingEdgeInterrupts: EdgeInterruptStream {
        interrupts.filter { $0.0 }.map { $0.1 }
    }
}
