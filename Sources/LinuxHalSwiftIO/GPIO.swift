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
import CLinuxHalSwiftIO
import Dispatch

#if os(Linux)
private let gpioChip = "/dev/gpiochip0" // FIXME: make configurable
private let gpioConsumer = "SwiftIO"
private let edgeEventBufferCapacity = 16

private final class GPIO {
  var chip: OpaquePointer? // gpiod_chip *
  var offset: UInt32 = 0
  var request: OpaquePointer? // gpiod_line_request *
  var eventBuffer: OpaquePointer? // gpiod_edge_event_buffer *
  var direction = SWIFT_GPIO_DIRECTION_OUT
  var ioMode = SWIFT_GPIO_MODE_PULL_NONE
  var intMode = SWIFT_GPIO_INT_MODE_RISING_EDGE
  let queue = DispatchQueue.global()
  var source: (any DispatchSourceProtocol)?
  var sourceSuspended = false
  var callback: ((Bool, timespec) -> ())?
}

private func handle(_ arg: UnsafeMutableRawPointer) -> GPIO {
  Unmanaged<GPIO>.fromOpaque(arg).takeUnretainedValue()
}

/// Cancel and release the interrupt dispatch source, bringing its suspend count
/// to zero first. Safe to call with no source installed.
private func releaseSource(_ gpio: GPIO) {
  guard let source = gpio.source else { return }
  source.cancelForRelease(&gpio.sourceSuspended)
  gpio.source = nil
}

/// Request the line with the given settings, or reconfigure the existing request
/// in place (keeping its file descriptor) if the line is already requested.
private func requestLine(
  _ gpio: GPIO,
  direction: gpiod_line_direction,
  ioMode: swift_gpio_mode_t,
  edge: gpiod_line_edge = GPIOD_LINE_EDGE_NONE
) -> CInt {
  guard let settings = gpiod_line_settings_new() else { return -errno }
  defer { gpiod_line_settings_free(settings) }

  gpiod_line_settings_set_direction(settings, direction)
  gpiod_line_settings_set_edge_detection(settings, edge)
  switch ioMode {
  case SWIFT_GPIO_MODE_PULL_UP: gpiod_line_settings_set_bias(settings, GPIOD_LINE_BIAS_PULL_UP)
  case SWIFT_GPIO_MODE_PULL_DOWN: gpiod_line_settings_set_bias(settings, GPIOD_LINE_BIAS_PULL_DOWN)
  case SWIFT_GPIO_MODE_PULL_NONE: gpiod_line_settings_set_bias(settings, GPIOD_LINE_BIAS_DISABLED)
  case SWIFT_GPIO_MODE_OPEN_DRAIN: gpiod_line_settings_set_drive(
      settings,
      GPIOD_LINE_DRIVE_OPEN_DRAIN
    )
  default: return -EINVAL
  }

  guard let lineConfig = gpiod_line_config_new() else { return -errno }
  defer { gpiod_line_config_free(lineConfig) }
  var offset = gpio.offset
  if gpiod_line_config_add_line_settings(lineConfig, &offset, 1, settings) < 0 { return -errno }

  if let request = gpio.request {
    if gpiod_line_request_reconfigure_lines(request, lineConfig) < 0 { return -errno }
    return 0
  }

  guard let requestConfig = gpiod_request_config_new() else { return -errno }
  defer { gpiod_request_config_free(requestConfig) }
  gpiod_request_config_set_consumer(requestConfig, gpioConsumer)

  guard let request = gpiod_chip_request_lines(gpio.chip, requestConfig, lineConfig)
  else { return -errno }
  gpio.request = request
  return 0
}

/// Takes ownership of `chip`, requests the line, and returns the retained opaque
/// handle (or nil, having closed the chip, on failure).
private func chip2gpio(
  _ id: CInt,
  _ chip: OpaquePointer,
  _ direction: swift_gpio_direction_t,
  _ ioMode: swift_gpio_mode_t
) -> UnsafeMutableRawPointer? {
  let gpio = GPIO()
  gpio.chip = chip
  gpio.offset = UInt32(bitPattern: id)

  let opaque = Unmanaged.passRetained(gpio).toOpaque()
  if swifthal_gpio_config(opaque, direction, ioMode) < 0 {
    _ = swifthal_gpio_close(opaque)
    return nil
  }
  return opaque
}

private func chipLabel(_ chip: OpaquePointer) -> String? {
  guard let info = gpiod_chip_get_info(chip) else { return nil }
  defer { gpiod_chip_info_free(info) }
  return String(cString: gpiod_chip_info_get_label(info))
}
#endif

@c
func swifthal_gpio_open(
  _ id: CInt,
  _ direction: swift_gpio_direction_t,
  _ ioMode: swift_gpio_mode_t
) -> UnsafeMutableRawPointer? {
  #if os(Linux)
  // libgpiod v2 has no chip iterator; scan /dev in sorted order, as v1 did.
  // http://git.munts.com/muntsos/doc/AppNote11-link-gpiochip.pdf
  var paths = glob_t()
  defer { globfree(&paths) }
  guard glob("/dev/gpiochip*", 0, nil, &paths) == 0 else { return nil }

  for i in 0..<Int(paths.gl_pathc) {
    guard let path = paths.gl_pathv[i], gpiod_is_gpiochip_device(path),
          let chip = gpiod_chip_open(path) else { continue }
    switch chipLabel(chip) {
    case "pinctrl-rp1", "pinctrl-bcm2835", "pinctrl-bcm2711":
      return chip2gpio(id, chip, direction, ioMode)
    default:
      gpiod_chip_close(chip)
    }
  }
  #endif
  return nil
}

@c
func swifthal_gpio_close(_ arg: UnsafeMutableRawPointer?) -> CInt {
  #if os(Linux)
  guard let arg else { return -EINVAL }
  let gpio = handle(arg)

  // Release the dispatch source before releasing the request:
  // gpiod_line_request_release() closes the event fd, and the cancel path traps
  // on EBADF if it's gone.
  releaseSource(gpio)
  if let request = gpio.request {
    gpiod_line_request_release(request)
  }
  if let eventBuffer = gpio.eventBuffer {
    gpiod_edge_event_buffer_free(eventBuffer)
  }
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
func swifthal_gpio_config(
  _ arg: UnsafeMutableRawPointer?,
  _ direction: swift_gpio_direction_t,
  _ ioMode: swift_gpio_mode_t
) -> CInt {
  #if os(Linux)
  guard let arg else { return -EINVAL }
  let gpio = handle(arg)

  releaseSource(gpio)

  let lineDirection: gpiod_line_direction
  switch direction {
  case SWIFT_GPIO_DIRECTION_OUT: lineDirection = GPIOD_LINE_DIRECTION_OUTPUT
  case SWIFT_GPIO_DIRECTION_IN: lineDirection = GPIOD_LINE_DIRECTION_INPUT
  default: return -EINVAL
  }

  let err = requestLine(gpio, direction: lineDirection, ioMode: ioMode)
  if err < 0 { return err }

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
  guard let request = gpio.request else { return -EINVAL }
  let value = level != 0 ? GPIOD_LINE_VALUE_ACTIVE : GPIOD_LINE_VALUE_INACTIVE
  if gpiod_line_request_set_value(request, gpio.offset, value) < 0 { return -errno }
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
  guard let request = gpio.request else { return -EINVAL }
  let value = gpiod_line_request_get_value(request, gpio.offset)
  if value == GPIOD_LINE_VALUE_ERROR { return -errno }
  return value.rawValue
  #else
  return -ENOSYS
  #endif
}

@c
func swifthal_gpio_interrupt_config(
  _ arg: UnsafeMutableRawPointer?,
  _ intMode: swift_gpio_int_mode_t
) -> CInt {
  #if os(Linux)
  guard let arg else { return -EINVAL }
  let gpio = handle(arg)

  // Release any prior source so reconfiguring the edge mode does not leak it.
  releaseSource(gpio)

  let edge: gpiod_line_edge
  switch intMode {
  case SWIFT_GPIO_INT_MODE_RISING_EDGE: edge = GPIOD_LINE_EDGE_RISING
  case SWIFT_GPIO_INT_MODE_FALLING_EDGE: edge = GPIOD_LINE_EDGE_FALLING
  case SWIFT_GPIO_INT_MODE_BOTH_EDGE: edge = GPIOD_LINE_EDGE_BOTH
  default: return -EINVAL
  }

  if gpio.eventBuffer == nil {
    gpio.eventBuffer = gpiod_edge_event_buffer_new(edgeEventBufferCapacity)
    if gpio.eventBuffer == nil { return -errno }
  }

  // Edge detection requires an input line (v1 event requests were implicitly
  // input too).
  let err = requestLine(
    gpio,
    direction: GPIOD_LINE_DIRECTION_INPUT,
    ioMode: gpio.ioMode,
    edge: edge
  )
  if err < 0 { return err }

  let fd = gpiod_line_request_get_fd(gpio.request)
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

/// Native-Swift replacement for the former Objective-C block entry point; wires
/// the Swift closure to the dispatch source's event handler. Consumed only by
/// AsyncSwiftIO.
package func swifthal_gpio_interrupt_callback_install_block(
  _ arg: UnsafeMutableRawPointer,
  _ callback: @escaping (Bool, timespec) -> ()
) -> CInt {
  #if os(Linux)
  let gpio = handle(arg)
  guard let source = gpio.source else { return -EINVAL }

  gpio.callback = callback
  source.setEventHandler { [weak gpio] in
    guard let gpio, gpio.source != nil, let request = gpio.request,
          let buffer = gpio.eventBuffer else { return }
    let count = gpiod_line_request_read_edge_events(
      request,
      buffer,
      gpiod_edge_event_buffer_get_capacity(buffer)
    )
    if count < 0 {
      // Tear down fully: a cancelled-but-installed source would strand later
      // disable/enable calls on a dead source (see callback_uninstall).
      releaseSource(gpio)
      return
    }
    for i in 0..<UInt(count) {
      guard let event = gpiod_edge_event_buffer_get_event(buffer, i) else { continue }
      let ns = gpiod_edge_event_get_timestamp_ns(event)
      let ts = timespec(
        tv_sec: time_t(ns / 1_000_000_000),
        tv_nsec: Int(ns % 1_000_000_000)
      )
      gpio.callback?(gpiod_edge_event_get_event_type(event) == GPIOD_EDGE_EVENT_RISING_EDGE, ts)
    }
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
  _ callback: (@convention(c) (UnsafeRawPointer?) -> ())?
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
  guard let chip = gpiod_chip_open(gpioChip) else { return 0 }
  defer { gpiod_chip_close(chip) }
  guard let info = gpiod_chip_get_info(chip) else { return 0 }
  defer { gpiod_chip_info_free(info) }
  return CInt(gpiod_chip_info_get_num_lines(info))
  #else
  return 0
  #endif
}

@c
func swifthal_gpio_get_fd(_ arg: UnsafeRawPointer?) -> CInt {
  #if os(Linux)
  guard let arg else { return -EINVAL }
  let gpio = handle(UnsafeMutableRawPointer(mutating: arg))
  guard let request = gpio.request else { return -EINVAL }
  return gpiod_line_request_get_fd(request)
  #else
  return -ENOSYS
  #endif
}
