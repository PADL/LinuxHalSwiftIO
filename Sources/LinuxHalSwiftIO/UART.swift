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

// Native-Swift port of the UART HAL (previously swift_uart.c): serial-port I/O
// with a buffered, timeout-aware read path (poll-based). The termios2 line
// configuration lives in swift_uart_native.c (see swift_uart_native.h) because
// <asm/termbits.h> cannot be exposed to Swift.

#if canImport(Glibc)
import Glibc
#elseif canImport(Darwin)
import Darwin
#endif
import CLinuxHalSwiftIO

private final class UART {
  var fd: CInt = -1
  let readBuf: UnsafeMutablePointer<UInt8>
  let readBufLen: Int
  var readBufOffset = 0
  var readBufConsumed = 0

  init(bufLen: Int) {
    readBufLen = bufLen
    let n = max(bufLen, 1)
    readBuf = UnsafeMutablePointer<UInt8>.allocate(capacity: n)
    readBuf.initialize(repeating: 0, count: n)
  }

  deinit {
    readBuf.deinitialize(count: max(readBufLen, 1))
    readBuf.deallocate()
  }
}

private func handle(_ arg: UnsafeMutableRawPointer) -> UART {
  Unmanaged<UART>.fromOpaque(arg).takeUnretainedValue()
}

#if os(Linux)
private func enableNbio(_ fd: CInt) -> CInt {
  let flags = fcntl(fd, F_GETFL, 0)
  if flags & O_NONBLOCK == 0 {
    if fcntl(fd, F_SETFL, flags | O_NONBLOCK) < 0 {
      swifthal__syslog(LOG_INFO, "LinuxHalSwiftIO: failed to enable non-blocking I/O on UART fd \(fd)")
      return -errno
    }
  }
  return 0
}

private func parityCode(_ parity: swift_uart_parity_t) -> CInt? {
  switch parity {
  case SWIFT_UART_PARITY_NONE: return 0
  case SWIFT_UART_PARITY_ODD: return 1
  case SWIFT_UART_PARITY_EVEN: return 2
  default: return nil
  }
}
#endif

@c
func swifthal_uart_open(_ id: CInt, _ cfg: UnsafePointer<swift_uart_cfg_t>?) -> UnsafeMutableRawPointer? {
  guard let cfg else { return nil }
  let uart = UART(bufLen: Int(cfg.pointee.read_buf_len))
  let opaque = Unmanaged.passRetained(uart).toOpaque()

  // FIXME: use this or /dev/serial?
  let device = "/dev/ttyAMA\(id)"
  let fd = device.withCString { open($0, O_RDWR) }
  if fd < 0 {
    _ = swifthal_uart_close(opaque)
    return nil
  }
  uart.fd = fd

  #if os(Linux)
  var err = enableNbio(fd)
  if err == 0 { err = swifthal_uart__set_raw(fd) }
  if err == 0 { err = swifthal_uart_baudrate_set(opaque, cfg.pointee.baudrate) }
  if err == 0 { err = swifthal_uart_parity_set(opaque, cfg.pointee.parity) }
  if err == 0 { err = swifthal_uart_stop_bits_set(opaque, cfg.pointee.stop_bits) }
  if err == 0 {
    // Call the helper directly rather than the public data_bits_set: the latter
    // is also declared _Nonnull in swift_hal_extras.h, so the name is ambiguous
    // at an internal call site.
    switch cfg.pointee.data_bits {
    case SWIFT_UART_DATA_BITS_8: err = swifthal_uart__set_data_bits_8(fd)
    default: err = -EINVAL
    }
  }
  if err != 0 {
    _ = swifthal_uart_close(opaque)
    return nil
  }
  #endif

  _ = swifthal_uart_buffer_clear(opaque)
  return opaque
}

@c
func swifthal_uart_close(_ arg: UnsafeMutableRawPointer?) -> CInt {
  guard let arg else { return -EINVAL }
  let uart = handle(arg)
  if uart.fd != -1 {
    close(uart.fd)
  }
  Unmanaged<UART>.fromOpaque(arg).release()
  return 0
}

@c
func swifthal_uart_baudrate_set(_ arg: UnsafeMutableRawPointer?, _ baudrate: Int) -> CInt {
  #if os(Linux)
  guard let arg else { return -EINVAL }
  guard baudrate != 0 else { return -EINVAL }
  return swifthal_uart__set_baud(handle(arg).fd, UInt32(truncatingIfNeeded: baudrate))
  #else
  return -ENOSYS
  #endif
}

@c
func swifthal_uart_parity_set(_ arg: UnsafeMutableRawPointer?, _ parity: swift_uart_parity_t) -> CInt {
  #if os(Linux)
  guard let arg else { return -EINVAL }
  guard let code = parityCode(parity) else { return -EINVAL }
  return swifthal_uart__set_parity(handle(arg).fd, code)
  #else
  return -ENOSYS
  #endif
}

@c
func swifthal_uart_stop_bits_set(_ arg: UnsafeMutableRawPointer?, _ stopBits: swift_uart_stop_bits_t) -> CInt {
  #if os(Linux)
  guard let arg else { return -EINVAL }
  let two: CInt
  switch stopBits {
  case SWIFT_UART_STOP_BITS_2: two = 1
  case SWIFT_UART_STOP_BITS_1: two = 0
  default: return -EINVAL
  }
  return swifthal_uart__set_stop_bits(handle(arg).fd, two)
  #else
  return -ENOSYS
  #endif
}

@c
func swifthal_uart_data_bits_set(_ arg: UnsafeRawPointer?, _ dataBits: swift_uart_data_bits_t) -> CInt {
  #if os(Linux)
  guard let arg else { return -EINVAL }
  switch dataBits {
  case SWIFT_UART_DATA_BITS_8:
    return swifthal_uart__set_data_bits_8(handle(UnsafeMutableRawPointer(mutating: arg)).fd)
  default:
    return -EINVAL
  }
  #else
  return -ENOSYS
  #endif
}

@c
func swifthal_uart_config_get(_ arg: UnsafeMutableRawPointer?, _ cfg: UnsafeMutablePointer<swift_uart_cfg_t>?) -> CInt {
  #if os(Linux)
  guard let cfg else { return -EINVAL }
  cfg.pointee = swift_uart_cfg_t()
  guard let arg else { return -EINVAL }
  let uart = handle(arg)

  // Set read_buf_len before interrogating the line: AsyncUART reads it without
  // checking the return code (the old C also filled it before the CSIZE check).
  cfg.pointee.read_buf_len = uart.readBufLen

  var baud: UInt32 = 0
  var parity: CInt = 0
  var stop2: CInt = 0
  let rc = swifthal_uart__get_config(uart.fd, &baud, &parity, &stop2)
  if rc < 0 { return rc }

  cfg.pointee.baudrate = Int(baud)
  cfg.pointee.parity = parity == 1 ? SWIFT_UART_PARITY_ODD : (parity == 2 ? SWIFT_UART_PARITY_EVEN : SWIFT_UART_PARITY_NONE)
  cfg.pointee.stop_bits = stop2 == 1 ? SWIFT_UART_STOP_BITS_2 : SWIFT_UART_STOP_BITS_1
  cfg.pointee.data_bits = SWIFT_UART_DATA_BITS_8
  return 0
  #else
  return -ENOSYS
  #endif
}

@c
func swifthal_uart_char_put(_ arg: UnsafeMutableRawPointer?, _ c: UInt8) -> CInt {
  var ch = c
  return swifthal_uart_write(arg, &ch, 1)
}

@c
func swifthal_uart_char_get(_ arg: UnsafeMutableRawPointer?, _ c: UnsafeMutablePointer<UInt8>?, _ timeout: CInt) -> CInt {
  swifthal_uart_read(arg, c, 1, timeout)
}

@c
func swifthal_uart_write(_ arg: UnsafeMutableRawPointer?, _ buf: UnsafePointer<UInt8>?, _ length: Int) -> CInt {
  guard let arg else { return -EINVAL }
  let uart = handle(arg)

  var pfd = pollfd(fd: uart.fd, events: Int16(POLLOUT), revents: 0)
  var bufp = buf
  var nremain = length

  while nremain > 0 {
    let err = poll(&pfd, 1, -1)
    if err < 0 { return -errno }

    if pfd.revents & Int16(POLLERR | POLLHUP | POLLNVAL) != 0 { return -EIO }

    if pfd.revents == Int16(POLLOUT) {
      let nbytes = write(uart.fd, bufp, nremain)
      if nbytes < 0 { return -errno }
      nremain -= nbytes
      bufp = bufp?.advanced(by: nbytes)
    }
  }
  return 0
}

private func tv2ms(_ tv: timeval) -> Int64 {
  Int64(tv.tv_sec) * 1000 + Int64(tv.tv_usec) / 1000
}

// Buffer whatever data arrives within `timeout` ms (nil = block indefinitely;
// expired = non-blocking poll), decrementing it in place by the elapsed wait.
// Returns the number of bytes still unfilled in the buffer, or a negative errno.
private func readBuffer(_ uart: UART, _ timeout: inout Int64?) -> Int {
  var pfd = pollfd(fd: uart.fd, events: 0, revents: 0)

  while uart.readBufOffset < uart.readBufLen {
    pfd.events = Int16(POLLIN)
    pfd.revents = 0

    var start = timeval()
    gettimeofday(&start, nil)

    let err = poll(&pfd, 1, timeout.map { CInt(truncatingIfNeeded: max($0, 0)) } ?? -1)

    if timeout != nil {
      var now = timeval()
      gettimeofday(&now, nil)
      timeout! -= tv2ms(now) - tv2ms(start)
    }

    if err < 0 { return -Int(errno) }
    if err == 0 { break } // timed out

    // Drain readable data first: a hangup (POLLHUP) can be reported together
    // with POLLIN while bytes are still buffered, and those must not be lost.
    if pfd.revents & Int16(POLLIN) != 0 {
      let nbytes = read(uart.fd, uart.readBuf + uart.readBufOffset, uart.readBufLen - uart.readBufOffset)
      if nbytes < 0 { return -Int(errno) }
      if nbytes == 0 { break } // EOF: return the bytes already buffered
      uart.readBufOffset += nbytes
      break // hand the data back rather than waiting for the buffer to fill
    }

    if pfd.revents & Int16(POLLERR | POLLHUP | POLLNVAL) != 0 { return -Int(EIO) }
    // spurious wakeup with nothing readable: poll again with the reduced timeout
  }

  return uart.readBufLen - uart.readBufOffset
}

@c
func swifthal_uart_read(_ arg: UnsafeMutableRawPointer?, _ buf: UnsafeMutablePointer<UInt8>?, _ length: Int, _ timeout: CInt) -> CInt {
  if length < 0 { return -EINVAL }
  if length == 0 { return 0 } // a zero-byte read is not an error
  guard let arg, let buf else { return -EINVAL }
  let uart = handle(arg)

  var timeout64: Int64? = timeout == -1 ? nil : Int64(timeout)
  var out = buf
  var nremain = length

  while nremain > 0 {
    // hand back any already-buffered, not-yet-consumed bytes
    if uart.readBufConsumed < uart.readBufOffset {
      let nconsume = min(uart.readBufOffset - uart.readBufConsumed, nremain)
      memcpy(out, uart.readBuf + uart.readBufConsumed, nconsume)
      uart.readBufConsumed += nconsume
      out = out.advanced(by: nconsume)
      nremain -= nconsume
      continue
    }

    // reset the buffer once fully consumed
    if uart.readBufOffset == uart.readBufLen {
      _ = swifthal_uart_buffer_clear(arg)
    }

    // A zero-length internal buffer can never deliver data.
    if uart.readBufLen == 0 { break }

    let filled = uart.readBufOffset
    let res = readBuffer(uart, &timeout64)
    if res < 0 { return CInt(truncatingIfNeeded: res) }

    // No new data: timeout expired, or EOF/hangup with nothing buffered — stop
    // rather than re-poll (a blocking re-poll at EOF would spin forever).
    if uart.readBufOffset == filled { break }
  }

  return CInt(truncatingIfNeeded: nremain)
}

@c
func swifthal_uart_remainder_get(_ arg: UnsafeMutableRawPointer?) -> CInt {
  guard let arg else { return -EINVAL }
  let uart = handle(arg)
  return CInt(uart.readBufOffset - uart.readBufConsumed)
}

@c
func swifthal_uart_buffer_clear(_ arg: UnsafeMutableRawPointer?) -> CInt {
  guard let arg else { return -EINVAL }
  let uart = handle(arg)
  uart.readBufOffset = 0
  uart.readBufConsumed = 0
  return 0
}

@c func swifthal_uart_dev_number_get() -> CInt { 0 }

@c
func swifthal_uart_get_fd(_ arg: UnsafeRawPointer?) -> CInt {
  guard let arg else { return -EINVAL }
  return handle(UnsafeMutableRawPointer(mutating: arg)).fd
}
