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

// Native-Swift reimplementation of the platform HAL (previously swift_platform.c).
// swifthal_hwcycle_get / swifthal_hwcycle_to_ns remain in C
// (swift_platform_hwcycle.c) because they require inline assembly.

#if canImport(Glibc)
import Glibc
#elseif canImport(Darwin)
import Darwin
#endif
import CLinuxHalSwiftIO

@c
func swifthal_ms_sleep(_ ms: Int) {
  guard ms > 0 else { return }

  // nanosleep avoids usleep's useconds_t (32-bit) truncation for large delays
  // and correctly handles interruption by a signal.
  var ts = timespec(tv_sec: ms / 1000, tv_nsec: (ms % 1000) * 1_000_000)
  var rem = timespec()

  while nanosleep(&ts, &rem) < 0, errno == EINTR {
    ts = rem
  }
}

@c
func swifthal_us_wait(_ us: UInt32) {
  usleep(us)
}

@c
func swifthal_uptime_get() -> Int64 {
  #if os(Linux)
  var info = sysinfo()
  guard sysinfo(&info) == 0 else { return -Int64(errno) }
  return Int64(info.uptime) * 1000
  #else
  // No sysinfo() on Darwin; CLOCK_MONOTONIC (ms since boot, excluding sleep)
  // is the closest equivalent. The old C just returned 0 here.
  var ts = timespec()
  guard clock_gettime(CLOCK_MONOTONIC, &ts) == 0 else { return -Int64(errno) }
  return Int64(ts.tv_sec) * 1000 + Int64(ts.tv_nsec) / 1_000_000
  #endif
}

#if os(Linux)
private func urandomFill(_ buf: UnsafeMutablePointer<UInt8>, _ length: Int) -> Int {
  let fd = open("/dev/urandom", O_RDONLY | O_CLOEXEC)
  if fd < 0 { return -1 }
  defer { close(fd) }

  var total = 0
  while total < length {
    let n = read(fd, buf + total, length - total)
    if n < 0 {
      if errno == EINTR { continue }
      break
    }
    if n == 0 { break }
    total += n
  }

  return total == length ? 0 : -1
}
#endif

// NOTE: named to match the HAL header declaration `swifthal_random_get`. The
// original C defined `swiftHal_randomGet`, a symbol that did not match the
// prototype, so it could never be linked against — a pre-existing bug, fixed
// here by adopting the declared name.
@c
func swifthal_random_get(_ buf: UnsafeMutablePointer<UInt8>?, _ length: Int) {
  guard let buf, length > 0 else { return }

  #if os(Linux)
  var total = 0
  // getrandom() may return short or fail with EINTR before the entropy pool is
  // initialized; ignoring that leaves the buffer partially/fully uninitialized
  // while callers treat it as random (key/nonce) material. Fill completely.
  while total < length {
    let n = getrandom(buf + total, length - total, 0)
    if n < 0 {
      if errno == EINTR { continue }
      // getrandom() may be unavailable (pre-3.17 kernel, or blocked by a seccomp
      // policy, returning ENOSYS/EFAULT). Fall back to /dev/urandom rather than
      // crashing the process or handing back non-random bytes.
      if urandomFill(buf + total, length - total) == 0 { return }
      abort() // no entropy source available: fail closed
    }
    total += n
  }
  #elseif canImport(Darwin)
  arc4random_buf(buf, length)
  #endif
}
