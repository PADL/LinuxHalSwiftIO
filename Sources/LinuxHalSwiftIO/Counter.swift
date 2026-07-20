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

// Native-Swift port of the counter HAL (previously swift_counter.c): a thin
// wrapper over a POSIX clock, counting microsecond ticks. Alarms and callbacks
// are unimplemented on Linux, matching the original.

#if canImport(Glibc)
import Glibc
#elseif canImport(Darwin)
import Darwin
#endif
import CLinuxHalSwiftIO

private struct CounterHandle {
  var clockid: clockid_t
}

@c
func swifthal_counter_open(_ id: CInt) -> UnsafeMutableRawPointer? {
  #if os(Linux)
  let clockid = clockid_t(id)
  #else
  // Darwin imports clockid_t as a RawRepresentable struct with a non-failable
  // init(rawValue:), so any bit pattern maps to a value.
  let clockid = clockid_t(rawValue: UInt32(bitPattern: id))
  #endif
  let c = UnsafeMutablePointer<CounterHandle>.allocate(capacity: 1)
  c.initialize(to: CounterHandle(clockid: clockid))
  return UnsafeMutableRawPointer(c)
}

@c
func swifthal_counter_close(_ arg: UnsafeMutableRawPointer?) -> CInt {
  guard let arg else { return -EINVAL }
  let c = arg.assumingMemoryBound(to: CounterHandle.self)
  c.deinitialize(count: 1)
  c.deallocate()
  return 0
}

@c
func swifthal_counter_read(
  _ arg: UnsafeMutableRawPointer?,
  _ ticks: UnsafeMutablePointer<UInt32>?
) -> CInt {
  ticks?.pointee = 0
  guard let arg else { return -EINVAL }
  let c = arg.assumingMemoryBound(to: CounterHandle.self)

  var tp = timespec()
  if clock_gettime(c.pointee.clockid, &tp) < 0 { return -errno }

  let us = UInt64(tp.tv_sec) * 1_000_000 + UInt64(tp.tv_nsec) / 1000
  ticks?.pointee = swifthal_counter_us_to_ticks(arg, us)
  return 0
}

@c
func swifthal_counter_add_callback(
  _ arg: UnsafeMutableRawPointer?,
  _ userData: UnsafeRawPointer?,
  _ callback: (@convention(c) (UInt32, UnsafeRawPointer?) -> ())?
) -> CInt {
  -ENOSYS
}

/// One tick == one microsecond (the old C stubbed these to 0, which made
/// counter_read discard its clock_gettime result and always report 0 ticks).
@c
func swifthal_counter_freq(_ arg: UnsafeMutableRawPointer?) -> UInt32 {
  1_000_000
}

@c
func swifthal_counter_ticks_to_us(
  _ arg: UnsafeMutableRawPointer?,
  _ ticks: UInt32
) -> UInt64 {
  UInt64(ticks)
}

@c
func swifthal_counter_us_to_ticks(
  _ arg: UnsafeMutableRawPointer?,
  _ us: UInt64
) -> UInt32 {
  UInt32(truncatingIfNeeded: us)
}

@c
func swifthal_counter_get_max_top_value(_ arg: UnsafeMutableRawPointer?) -> UInt32 {
  UInt32.max
}

@c
func swifthal_counter_set_channel_alarm(
  _ arg: UnsafeMutableRawPointer?,
  _ ticks: UInt32
) -> CInt {
  -ENOSYS
}

@c
func swifthal_counter_cancel_channel_alarm(_ arg: UnsafeMutableRawPointer?) -> CInt {
  -ENOSYS
}

@c
func swifthal_counter_start(_ arg: UnsafeMutableRawPointer?) -> CInt {
  -ENOSYS
}

@c
func swifthal_counter_stop(_ arg: UnsafeMutableRawPointer?) -> CInt {
  -ENOSYS
}

@c
func swifthal_counter_dev_number_get() -> CInt {
  0
}
