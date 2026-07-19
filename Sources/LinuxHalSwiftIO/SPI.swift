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

// Native-Swift reimplementation of the SPI HAL (previously swift_spi.c), driving
// Linux spidev. The ioctl request numbers are function-like C macros, so the
// actual ioctl() calls go through the `swifthal_spi__*` wrappers declared in
// swift_hal_native.h.

#if canImport(Glibc)
import Glibc
#elseif canImport(Darwin)
import Darwin
#endif
import CLinuxHalSwiftIO

private struct SPIHandle {
  var fd: CInt = -1
  var speedOld: UInt32 = 0
  var operationOld: UInt16 = 0
}

#if os(Linux)
private func spiReadConfig(_ spi: UnsafeMutablePointer<SPIHandle>) -> CInt {
  let fd = spi.pointee.fd
  var speed: UInt32 = 0
  var operation: Int32 = 0
  var tmp: UInt8 = 0

  if swifthal_spi__rd_max_speed(fd, &speed) < 0 { return -errno }

  if swifthal_spi__rd_mode(fd, &tmp) < 0 { return -errno }
  if tmp & swifthal_spi__cpol != 0 { operation |= SWIFT_SPI_MODE_CPOL }
  if tmp & swifthal_spi__cpha != 0 { operation |= SWIFT_SPI_MODE_CPHA }
  if tmp & swifthal_spi__loop != 0 { operation |= SWIFT_SPI_MODE_LOOP }

  if swifthal_spi__rd_lsb_first(fd, &tmp) < 0 { return -errno }
  operation |= (tmp != 0) ? SWIFT_SPI_TRANSFER_LSB : SWIFT_SPI_TRANSFER_MSB

  if swifthal_spi__rd_bits_per_word(fd, &tmp) < 0 { return -errno }
  switch tmp {
  case 8:
    operation |= SWIFT_SPI_TRANSFER_8_BITS
  default:
    return -EINVAL
  }

  spi.pointee.speedOld = speed
  spi.pointee.operationOld = UInt16(truncatingIfNeeded: operation)
  return 0
}
#endif

@c
func swifthal_spi_open(
  _ id: CInt,
  _ speed: Int,
  _ operation: UInt16,
  _ wNotify: (@convention(c) (UnsafeMutableRawPointer?) -> ())?,
  _ rNotify: (@convention(c) (UnsafeMutableRawPointer?) -> ())?
) -> UnsafeMutableRawPointer? {
  let spi = UnsafeMutablePointer<SPIHandle>.allocate(capacity: 1)
  spi.initialize(to: SPIHandle())

  // FIXME: how to integrate with CS from calling library
  let device = "/dev/spidev\(id).0"
  let fd = device.withCString { open($0, O_RDWR) }
  if fd < 0 {
    _ = swifthal_spi_close(UnsafeMutableRawPointer(spi))
    return nil
  }
  spi.pointee.fd = fd

  #if os(Linux)
  // save previous configuration so we can restore it
  if spiReadConfig(spi) < 0
    || swifthal_spi_config(UnsafeMutableRawPointer(spi), speed, operation) < 0
  {
    _ = swifthal_spi_close(UnsafeMutableRawPointer(spi))
    return nil
  }
  #endif

  return UnsafeMutableRawPointer(spi)
}

@c
func swifthal_spi_close(_ arg: UnsafeMutableRawPointer?) -> CInt {
  guard let arg else { return -EINVAL }
  let spi = arg.assumingMemoryBound(to: SPIHandle.self)

  if spi.pointee.speedOld != 0 {
    _ = swifthal_spi_config(arg, Int(spi.pointee.speedOld), spi.pointee.operationOld)
  }
  if spi.pointee.fd != -1 {
    close(spi.pointee.fd)
  }
  spi.deinitialize(count: 1)
  spi.deallocate()
  return 0
}

@c
func swifthal_spi_config(
  _ arg: UnsafeMutableRawPointer?,
  _ speed: Int,
  _ operation: UInt16
) -> CInt {
  #if os(Linux)
  guard let arg else { return -EINVAL }
  let spi = arg.assumingMemoryBound(to: SPIHandle.self)
  let fd = spi.pointee.fd
  let op = Int32(operation)
  var mode: UInt8 = 0

  if op & SWIFT_SPI_MODE_CPOL != 0 { mode |= swifthal_spi__cpol }
  if op & SWIFT_SPI_MODE_CPHA != 0 { mode |= swifthal_spi__cpha }
  if op & SWIFT_SPI_MODE_LOOP != 0 { mode |= swifthal_spi__loop }
  if op & SWIFT_SPI_TRANSFER_LSB != 0 { mode |= swifthal_spi__lsb_first }

  if swifthal_spi__wr_mode(fd, &mode) < 0 { return -errno }

  if op & SWIFT_SPI_TRANSFER_8_BITS != 0 {
    var bpw: UInt8 = 8
    if swifthal_spi__wr_bits_per_word(fd, &bpw) < 0 { return -errno }
  }

  if speed != 0 {
    var freq = UInt32(truncatingIfNeeded: speed)
    if swifthal_spi__wr_max_speed(fd, &freq) < 0 { return -errno }
  }

  return 0
  #else
  return -ENOSYS
  #endif
}

@c
func swifthal_spi_write(
  _ arg: UnsafeMutableRawPointer?,
  _ buf: UnsafePointer<UInt8>?,
  _ length: Int
) -> CInt {
  guard let arg else { return -EINVAL }
  let spi = arg.assumingMemoryBound(to: SPIHandle.self)

  let nbytes = write(spi.pointee.fd, buf, length)
  if nbytes < 0 { return -errno }
  return CInt(truncatingIfNeeded: nbytes)
}

@c
func swifthal_spi_read(
  _ arg: UnsafeMutableRawPointer?,
  _ buf: UnsafeMutablePointer<UInt8>?,
  _ length: Int
) -> CInt {
  guard let arg else { return -EINVAL }
  let spi = arg.assumingMemoryBound(to: SPIHandle.self)

  let nbytes = read(spi.pointee.fd, buf, length)
  if nbytes < 0 { return -errno }
  return CInt(truncatingIfNeeded: nbytes)
}

@c
func swifthal_spi_transceive(
  _ arg: UnsafeMutableRawPointer?,
  _ wBuf: UnsafePointer<UInt8>?,
  _ wLength: Int,
  _ rBuf: UnsafeMutablePointer<UInt8>?,
  _ rLength: Int
) -> CInt {
  #if os(Linux)
  guard let arg, let wBuf, let rBuf else { return -EINVAL }

  // Guard against a negative length: it would convert to a huge size_t and
  // overflow the memset / spi_ioc_transfer len field.
  guard wLength >= 0, rLength >= 0 else { return -EINVAL }

  let spi = arg.assumingMemoryBound(to: SPIHandle.self)

  rBuf.update(repeating: 0, count: rLength)

  var xfer = [spi_ioc_transfer](repeating: spi_ioc_transfer(), count: 2)
  xfer[0].tx_buf = UInt64(UInt(bitPattern: UnsafeRawPointer(wBuf)))
  xfer[0].len = UInt32(truncatingIfNeeded: wLength)
  xfer[1].rx_buf = UInt64(UInt(bitPattern: UnsafeMutableRawPointer(rBuf)))
  xfer[1].len = UInt32(truncatingIfNeeded: rLength)

  let rc = xfer.withUnsafeMutableBufferPointer {
    swifthal_spi__message2(spi.pointee.fd, $0.baseAddress)
  }
  if rc < 0 { return -errno }
  return 0
  #else
  return -ENOSYS
  #endif
}

@c
func swifthal_spi_async_write(
  _ arg: UnsafeMutableRawPointer?,
  _ buf: UnsafePointer<UInt8>?,
  _ length: Int
) -> CInt {
  -ENOSYS
}

@c
func swifthal_spi_async_read(
  _ arg: UnsafeMutableRawPointer?,
  _ buf: UnsafeMutablePointer<UInt8>?,
  _ length: Int
) -> CInt {
  -ENOSYS
}

// FIXME: implement this by interrogating /sys/class/spi_master
@c
func swifthal_spi_dev_number_get() -> CInt {
  0
}

@c
func swifthal_spi_get_fd(_ arg: UnsafeRawPointer?) -> CInt {
  guard let arg else { return -EINVAL }
  let spi = arg.assumingMemoryBound(to: SPIHandle.self)
  return spi.pointee.fd
}
