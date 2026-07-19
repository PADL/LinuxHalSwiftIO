//
// Copyright (c) 2026 PADL Software Pty Ltd
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

// Native-Swift port of the timer HAL (previously swift_timer.c). The original
// used libdispatch timer sources with an Objective-C block handler; this uses
// the Swift Dispatch overlay and a Swift closure, so no Blocks runtime is
// involved. The public callback is a plain C function pointer.

#if canImport(Glibc)
import Glibc
#elseif canImport(Darwin)
import Darwin
#endif
import Dispatch
import Synchronization
import CLinuxHalSwiftIO

private final class Timer {
  let source: DispatchSourceTimer
  var type: swift_timer_type_t = SWIFT_TIMER_TYPE_ONESHOT
  let status = Atomic<UInt32>(0)
  var suspended = true // dispatch sources start inactive
  var callback: (@convention(c) (UnsafeRawPointer?) -> Void)?
  var param: UnsafeRawPointer?

  init() {
    source = DispatchSource.makeTimerSource(queue: .global())
  }
}

@c
func swifthal_timer_open() -> UnsafeMutableRawPointer? {
  Unmanaged.passRetained(Timer()).toOpaque()
}

@c
func swifthal_timer_close(_ arg: UnsafeMutableRawPointer?) -> CInt {
  guard let arg else { return -EINVAL }
  let timer = Unmanaged<Timer>.fromOpaque(arg).takeUnretainedValue()

  timer.source.cancel()
  // A suspended source traps when its last reference is dropped; balance the
  // suspend count back to zero before releasing.
  if timer.suspended {
    timer.source.resume()
    timer.suspended = false
  }
  Unmanaged<Timer>.fromOpaque(arg).release()
  return 0
}

@c
func swifthal_timer_start(_ arg: UnsafeMutableRawPointer?, _ type: swift_timer_type_t, _ period: Int) -> CInt {
  guard let arg else { return -EINVAL }
  let timer = Unmanaged<Timer>.fromOpaque(arg).takeUnretainedValue()

  timer.type = type
  let interval = DispatchTimeInterval.milliseconds(Int(period))
  if type == SWIFT_TIMER_TYPE_ONESHOT {
    timer.source.schedule(deadline: .now() + interval)
  } else {
    timer.source.schedule(deadline: .now() + interval, repeating: interval)
  }
  // Resume only if suspended so re-arming a running timer does not over-resume.
  if timer.suspended {
    timer.source.resume()
    timer.suspended = false
  }
  return 0
}

@c
func swifthal_timer_stop(_ arg: UnsafeMutableRawPointer?) -> CInt {
  guard let arg else { return -EINVAL }
  let timer = Unmanaged<Timer>.fromOpaque(arg).takeUnretainedValue()

  // Suspend rather than cancel: cancellation is permanent, so a cancel here
  // would leave a subsequent timer_start unable to re-arm the timer.
  if !timer.suspended {
    timer.source.suspend()
    timer.suspended = true
  }
  return 0
}

@c
func swifthal_timer_add_callback(
  _ arg: UnsafeMutableRawPointer?,
  _ param: UnsafeRawPointer?,
  _ callback: (@convention(c) (UnsafeRawPointer?) -> Void)?
) -> CInt {
  guard let arg else { return -EINVAL }
  let timer = Unmanaged<Timer>.fromOpaque(arg).takeUnretainedValue()

  timer.callback = callback
  timer.param = param
  // weak capture avoids a source<->timer retain cycle; the timer is kept alive
  // by the retained opaque handle until timer_close releases it.
  timer.source.setEventHandler { [weak timer] in
    guard let timer else { return }
    timer.status.wrappingAdd(1, ordering: .relaxed)
    timer.callback?(timer.param)
  }
  return 0
}

@c
func swifthal_timer_status_get(_ arg: UnsafeMutableRawPointer?) -> UInt32 {
  guard let arg else { return 0 }
  let timer = Unmanaged<Timer>.fromOpaque(arg).takeUnretainedValue()
  return timer.status.exchange(0, ordering: .relaxed)
}
