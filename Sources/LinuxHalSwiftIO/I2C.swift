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

// Native-Swift port of the I2C HAL (previously swift_i2c.c), driving Linux
// i2c-dev. The I2C_SLAVE / I2C_RDWR ioctls go through the swifthal_i2c__*
// wrappers in swift_hal_native.h.

#if canImport(Glibc)
import Glibc
#elseif canImport(Darwin)
import Darwin
#endif
import CLinuxHalSwiftIO

private struct I2CHandle {
  var id: CInt
  var fd: CInt
}

@c
func swifthal_i2c_open(_ id: CInt) -> UnsafeMutableRawPointer? {
  let i2c = UnsafeMutablePointer<I2CHandle>.allocate(capacity: 1)
  i2c.initialize(to: I2CHandle(id: id, fd: -1))

  let device = "/dev/i2c-\(id)"
  let fd = device.withCString { open($0, O_RDWR) }
  if fd < 0 {
    _ = swifthal_i2c_close(UnsafeMutableRawPointer(i2c))
    return nil
  }
  i2c.pointee.fd = fd
  return UnsafeMutableRawPointer(i2c)
}

@c
func swifthal_i2c_close(_ arg: UnsafeMutableRawPointer?) -> CInt {
  guard let arg else { return -EINVAL }
  let i2c = arg.assumingMemoryBound(to: I2CHandle.self)
  if i2c.pointee.fd != -1 {
    close(i2c.pointee.fd)
  }
  i2c.deinitialize(count: 1)
  i2c.deallocate()
  return 0
}

@c
func swifthal_i2c_config(_ arg: UnsafeMutableRawPointer?, _ speed: UInt32) -> CInt {
  #if os(Linux)
  guard let arg else { return -EINVAL }
  let i2c = arg.assumingMemoryBound(to: I2CHandle.self)
  swifthal__syslog(
    LOG_INFO,
    "LinuxHalSwiftIO: I2C speed can only be configured by driver or device tree (device \(i2c.pointee.id))")
  return 0
  #else
  return -ENOSYS
  #endif
}

@c
func swifthal_i2c_write(_ arg: UnsafeMutableRawPointer?, _ address: UInt8, _ buf: UnsafePointer<UInt8>?, _ length: Int) -> CInt {
  #if os(Linux)
  guard let arg, length >= 0 else { return -EINVAL }
  let i2c = arg.assumingMemoryBound(to: I2CHandle.self)
  if swifthal_i2c__set_slave(i2c.pointee.fd, UInt(address)) < 0 || write(i2c.pointee.fd, buf, length) < 0 {
    return -errno
  }
  return 0
  #else
  return -ENOSYS
  #endif
}

@c
func swifthal_i2c_read(_ arg: UnsafeMutableRawPointer?, _ address: UInt8, _ buf: UnsafeMutablePointer<UInt8>?, _ length: Int) -> CInt {
  #if os(Linux)
  guard let arg, length >= 0 else { return -EINVAL }
  let i2c = arg.assumingMemoryBound(to: I2CHandle.self)
  if swifthal_i2c__set_slave(i2c.pointee.fd, UInt(address)) < 0 || read(i2c.pointee.fd, buf, length) < 0 {
    return -errno
  }
  return 0
  #else
  return -ENOSYS
  #endif
}

@c
func swifthal_i2c_write_read(
  _ arg: UnsafeMutableRawPointer?,
  _ addr: UInt8,
  _ writeBuf: UnsafeRawPointer?,
  _ numWrite: Int,
  _ readBuf: UnsafeMutableRawPointer?,
  _ numRead: Int
) -> CInt {
  #if os(Linux)
  guard let arg else { return -EINVAL }
  guard numWrite >= 0, numRead >= 0, numWrite <= Int(UInt16.max), numRead <= Int(UInt16.max) else {
    return -EINVAL
  }
  let i2c = arg.assumingMemoryBound(to: I2CHandle.self)

  var messages = [i2c_msg](repeating: i2c_msg(), count: 2)
  messages[0].addr = UInt16(addr)
  messages[0].flags = 0
  messages[0].len = UInt16(numWrite)
  messages[0].buf = UnsafeMutablePointer(mutating: writeBuf?.assumingMemoryBound(to: UInt8.self))

  // I2C_M_RD alone: the kernel emits a repeated START and addr+R before the read
  // segment. I2C_M_NOSTART would suppress that (and is rejected by most
  // adapters), breaking the combined write-then-read transaction.
  messages[1].addr = UInt16(addr)
  messages[1].flags = UInt16(I2C_M_RD)
  messages[1].len = UInt16(numRead)
  messages[1].buf = readBuf?.assumingMemoryBound(to: UInt8.self)

  let rc = messages.withUnsafeMutableBufferPointer { msgs -> CInt in
    var data = i2c_rdwr_ioctl_data(msgs: msgs.baseAddress, nmsgs: 2)
    return swifthal_i2c__rdwr(i2c.pointee.fd, &data)
  }
  if rc < 0 { return -errno }
  return 0
  #else
  return -ENOSYS
  #endif
}

// FIXME: implement this by /sys/class/i2c-dev
@c func swifthal_i2c_dev_number_get() -> CInt { 0 }

@c
func swifthal_i2c_get_fd(_ arg: UnsafeRawPointer?) -> CInt {
  guard let arg else { return -EINVAL }
  let i2c = arg.assumingMemoryBound(to: I2CHandle.self)
  return i2c.pointee.fd
}

@c
func swifthal_i2c_set_addr(_ arg: UnsafeRawPointer?, _ addr: UInt8) -> CInt {
  #if os(Linux)
  guard let arg else { return -EINVAL }
  let i2c = arg.assumingMemoryBound(to: I2CHandle.self)
  if swifthal_i2c__set_slave(i2c.pointee.fd, UInt(addr)) < 0 { return -errno }
  return 0
  #else
  return -ENOSYS
  #endif
}
