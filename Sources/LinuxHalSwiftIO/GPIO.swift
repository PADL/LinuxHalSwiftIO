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

// Native-Swift port of the GPIO HAL (previously swift_gpio.c), driving libgpiod
// with a Swift Dispatch read source for edge interrupts. The original used an
// Objective-C block for the interrupt callback; because that entry point is
// consumed only by AsyncSwiftIO, it is now a native Swift closure API
// (swifthal_gpio_interrupt_callback_install_block, below) and no Blocks runtime
// is involved.

#if canImport(Glibc)
import Glibc
#elseif canImport(Darwin)
import Darwin
#endif
import Dispatch
import CLinuxHalSwiftIO

#if os(Linux)
private let gpioChip = "gpiochip0" // FIXME: make configurable

private final class GPIO {
  var chip: OpaquePointer? // gpiod_chip *
  var line: OpaquePointer? // gpiod_line *
  var direction = SWIFT_GPIO_DIRECTION_OUT
  var ioMode = SWIFT_GPIO_MODE_PULL_NONE
  var intMode = SWIFT_GPIO_INT_MODE_RISING_EDGE
  let queue = DispatchQueue.global()
  var source: (any DispatchSourceProtocol)?
  var sourceSuspended = false
  var callback: ((UInt8, timespec) -> Void)?
}

private func handle(_ arg: UnsafeMutableRawPointer) -> GPIO {
  Unmanaged<GPIO>.fromOpaque(arg).takeUnretainedValue()
}

// Cancel and release the interrupt dispatch source, bringing its suspend count
// to zero first. Safe to call with no source installed.
private func releaseSource(_ gpio: GPIO) {
  guard let source = gpio.source else { return }
  source.cancelForRelease(&gpio.sourceSuspended)
  gpio.source = nil
}

private func ioModeFlags(_ ioMode: swift_gpio_mode_t) -> CInt? {
  switch ioMode {
  case SWIFT_GPIO_MODE_PULL_UP: return CInt(GPIOD_LINE_REQUEST_FLAG_BIAS_PULL_UP)
  case SWIFT_GPIO_MODE_PULL_DOWN: return CInt(GPIOD_LINE_REQUEST_FLAG_BIAS_PULL_DOWN)
  case SWIFT_GPIO_MODE_PULL_NONE: return CInt(GPIOD_LINE_REQUEST_FLAG_BIAS_DISABLE)
  case SWIFT_GPIO_MODE_OPEN_DRAIN: return CInt(GPIOD_LINE_REQUEST_FLAG_OPEN_DRAIN)
  default: return nil
  }
}

// Takes ownership of `chip`, wires up the line, and returns the retained opaque
// handle (or nil, having closed the chip, on failure).
private func chip2gpio(
  _ id: CInt,
  _ chip: OpaquePointer,
  _ direction: swift_gpio_direction_t,
  _ ioMode: swift_gpio_mode_t
) -> UnsafeMutableRawPointer? {
  let gpio = GPIO()
  gpio.chip = chip

  gpio.line = gpiod_chip_get_line(chip, UInt32(bitPattern: id))
  if gpio.line == nil {
    gpiod_chip_close(chip)
    return nil
  }

  let opaque = Unmanaged.passRetained(gpio).toOpaque()
  if swifthal_gpio_config(opaque, direction, ioMode) < 0 {
    _ = swifthal_gpio_close(opaque)
    return nil
  }
  return opaque
}
#endif

@c
func swifthal_gpio_open(_ id: CInt, _ direction: swift_gpio_direction_t, _ ioMode: swift_gpio_mode_t) -> UnsafeMutableRawPointer? {
  #if os(Linux)
  // http://git.munts.com/muntsos/doc/AppNote11-link-gpiochip.pdf
  guard let iter = gpiod_chip_iter_new() else { return nil }

  var chip = gpiod_chip_iter_next(iter)
  while let c = chip {
    if let label = gpiod_chip_label(c) {
      let name = String(cString: label)
      if name == "pinctrl-rp1" || name == "pinctrl-bcm2835" || name == "pinctrl-bcm2711" {
        let gpio = chip2gpio(id, c, direction, ioMode)
        gpiod_chip_iter_free_noclose(iter)
        return gpio
      }
    }
    chip = gpiod_chip_iter_next(iter)
  }

  gpiod_chip_iter_free(iter)
  #endif
  return nil
}

@c
func swifthal_gpio_close(_ arg: UnsafeMutableRawPointer?) -> CInt {
  #if os(Linux)
  guard let arg else { return -EINVAL }
  let gpio = handle(arg)

  // Release the dispatch source before closing the chip: gpiod_chip_close()
  // drops the line's event fd, and the cancel path traps on EBADF if it's gone.
  releaseSource(gpio)
  if let chip = gpio.chip {
    gpiod_chip_close(chip)
  }
  Unmanaged<GPIO>.fromOpaque(arg).release()
  return 0
  #else
  return -EINVAL
  #endif
}

@c
func swifthal_gpio_config(_ arg: UnsafeMutableRawPointer?, _ direction: swift_gpio_direction_t, _ ioMode: swift_gpio_mode_t) -> CInt {
  #if os(Linux)
  guard let arg else { return -EINVAL }
  let gpio = handle(arg)

  releaseSource(gpio)

  var lrc = gpiod_line_request_config()
  lrc.consumer = swifthal_gpio__consumer()
  lrc.flags = 0

  switch direction {
  case SWIFT_GPIO_DIRECTION_OUT: lrc.request_type = CInt(GPIOD_LINE_REQUEST_DIRECTION_OUTPUT)
  case SWIFT_GPIO_DIRECTION_IN: lrc.request_type = CInt(GPIOD_LINE_REQUEST_DIRECTION_INPUT)
  default: return -EINVAL
  }

  guard let flags = ioModeFlags(ioMode) else { return -EINVAL }
  lrc.flags = flags

  if gpiod_line_request(gpio.line, &lrc, 0) < 0 { return -errno }

  gpio.direction = direction
  gpio.ioMode = ioMode
  return 0
  #else
  return -ENOSYS
  #endif
}

@c
func swifthal_gpio_set(_ arg: UnsafeMutableRawPointer?, _ level: CInt) -> CInt {
  #if os(Linux)
  guard let arg else { return -EINVAL }
  let gpio = handle(arg)
  if gpiod_line_set_value(gpio.line, level) < 0 { return -errno }
  return 0
  #else
  return -ENOSYS
  #endif
}

@c
func swifthal_gpio_get(_ arg: UnsafeMutableRawPointer?) -> CInt {
  #if os(Linux)
  guard let arg else { return -EINVAL }
  let gpio = handle(arg)
  let value = gpiod_line_get_value(gpio.line)
  if value < 0 { return -errno }
  return value
  #else
  return -ENOSYS
  #endif
}

@c
func swifthal_gpio_interrupt_config(_ arg: UnsafeMutableRawPointer?, _ intMode: swift_gpio_int_mode_t) -> CInt {
  #if os(Linux)
  guard let arg else { return -EINVAL }
  let gpio = handle(arg)

  // Release any prior source so reconfiguring the edge mode does not leak it.
  releaseSource(gpio)

  var lrc = gpiod_line_request_config()
  lrc.consumer = swifthal_gpio__consumer()
  lrc.flags = 0

  switch intMode {
  case SWIFT_GPIO_INT_MODE_RISING_EDGE: lrc.request_type = CInt(GPIOD_LINE_REQUEST_EVENT_RISING_EDGE)
  case SWIFT_GPIO_INT_MODE_FALLING_EDGE: lrc.request_type = CInt(GPIOD_LINE_REQUEST_EVENT_FALLING_EDGE)
  case SWIFT_GPIO_INT_MODE_BOTH_EDGE: lrc.request_type = CInt(GPIOD_LINE_REQUEST_EVENT_BOTH_EDGES)
  default: return -EINVAL
  }

  guard let flags = ioModeFlags(gpio.ioMode) else { return -EINVAL }
  lrc.flags = flags

  if gpiod_line_is_requested(gpio.line) {
    gpiod_line_release(gpio.line)
  }

  if gpiod_line_request(gpio.line, &lrc, 0) < 0 { return -errno }

  let fd = gpiod_line_event_get_fd(gpio.line)
  if fd < 0 { return -errno }

  let source: any DispatchSourceProtocol = gpio.direction == SWIFT_GPIO_DIRECTION_OUT
    ? DispatchSource.makeWriteSource(fileDescriptor: fd, queue: gpio.queue)
    : DispatchSource.makeReadSource(fileDescriptor: fd, queue: gpio.queue)
  gpio.source = source
  // dispatch sources are created inactive; interrupt_enable resumes.
  gpio.sourceSuspended = true
  gpio.intMode = intMode
  return 0
  #else
  return -ENOSYS
  #endif
}

// Native-Swift replacement for the former Objective-C block entry point; wires
// the Swift closure to the dispatch source's event handler. Consumed only by
// AsyncSwiftIO.
public func swifthal_gpio_interrupt_callback_install_block(
  _ arg: UnsafeMutableRawPointer,
  _ callback: @escaping (UInt8, timespec) -> Void
) -> CInt {
  #if os(Linux)
  let gpio = handle(arg)
  guard let source = gpio.source else { return -EINVAL }

  gpio.callback = callback
  source.setEventHandler { [weak gpio] in
    guard let gpio, let source = gpio.source else { return }
    let fd = CInt(source.handle)
    var event = gpiod_line_event()
    if gpiod_line_event_read_fd(fd, &event) < 0 {
      // Tear down fully: a cancelled-but-installed source would strand later
      // disable/enable calls on a dead source (see callback_uninstall).
      releaseSource(gpio)
      return
    }
    gpio.callback?(event.event_type == CInt(GPIOD_LINE_EVENT_RISING_EDGE) ? 1 : 0, event.ts)
  }
  return 0
  #else
  return -ENOSYS
  #endif
}

@c
func swifthal_gpio_interrupt_callback_install(
  _ arg: UnsafeMutableRawPointer?,
  _ param: UnsafeRawPointer?,
  _ callback: (@convention(c) (UnsafeRawPointer?) -> Void)?
) -> CInt {
  guard let arg else { return -EINVAL }
  return swifthal_gpio_interrupt_callback_install_block(arg) { _, _ in
    callback?(param)
  }
}

@c
func swifthal_gpio_interrupt_callback_uninstall(_ arg: UnsafeMutableRawPointer?) -> CInt {
  #if os(Linux)
  guard let arg else { return -EINVAL }
  let gpio = handle(arg)
  // Fully tear down (cancel + rebalance + clear) rather than only cancel: cancel
  // is permanent, and resuming a dead source would silently drop all events.
  releaseSource(gpio)
  return 0
  #else
  return -ENOSYS
  #endif
}

@c
func swifthal_gpio_interrupt_enable(_ arg: UnsafeMutableRawPointer?) -> CInt {
  #if os(Linux)
  guard let arg else { return -EINVAL }
  let gpio = handle(arg)
  guard let source = gpio.source else { return -EINVAL }
  source.resumeIfSuspended(&gpio.sourceSuspended)
  return 0
  #else
  return -ENOSYS
  #endif
}

@c
func swifthal_gpio_interrupt_disable(_ arg: UnsafeMutableRawPointer?) -> CInt {
  #if os(Linux)
  guard let arg else { return -EINVAL }
  let gpio = handle(arg)
  // With no source (e.g. after callback_uninstall) the interrupt is already
  // effectively disabled; a no-op, as SwiftIO's teardown paths expect success.
  guard let source = gpio.source else { return 0 }
  source.suspendIfRunning(&gpio.sourceSuspended)
  return 0
  #else
  return -ENOSYS
  #endif
}

@c
func swifthal_gpio_dev_number_get() -> CInt {
  #if os(Linux)
  guard let chip = gpiod_chip_open_by_name(gpioChip) else { return 0 }
  defer { gpiod_chip_close(chip) }
  var bulk = gpiod_line_bulk()
  gpiod_chip_get_all_lines(chip, &bulk)
  return CInt(bulk.num_lines)
  #else
  return 0
  #endif
}

@c
func swifthal_gpio_get_fd(_ arg: UnsafeRawPointer?) -> CInt {
  #if os(Linux)
  guard let arg else { return -EINVAL }
  let gpio = handle(UnsafeMutableRawPointer(mutating: arg))
  return gpiod_line_event_get_fd(gpio.line)
  #else
  return -ENOSYS
  #endif
}
