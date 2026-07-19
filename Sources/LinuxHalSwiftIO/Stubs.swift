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

// Native-Swift ports of the unimplemented HAL subsystems (ADC, Ethernet, I2S,
// LCD, PWM, WiFi). These have no Linux backing and return the same NULL /
// -ENOSYS / 0 sentinels as the original C stubs.

#if canImport(Glibc)
import Glibc
#elseif canImport(Darwin)
import Darwin
#endif
import CLinuxHalSwiftIO

// MARK: - ADC

@c func swifthal_adc_open(_ id: CInt) -> UnsafeMutableRawPointer? { nil }
@c func swifthal_adc_close(_ adc: UnsafeMutableRawPointer?) -> CInt { -ENOSYS }
@c func swifthal_adc_read(_ adc: UnsafeMutableRawPointer?, _ sampleBuffer: UnsafeMutablePointer<UInt16>?) -> CInt { -ENOSYS }
@c func swifthal_adc_info_get(_ adc: UnsafeMutableRawPointer?, _ info: UnsafeMutablePointer<swift_adc_info_t>?) -> CInt { -ENOSYS }
@c func swifthal_adc_dev_number_get() -> CInt { 0 }

// MARK: - Ethernet

@c func swift_eth_setup_mac(_ mac: UnsafePointer<UInt8>?) -> CInt { -ENOSYS }
@c func swift_eth_tx_register(_ send: (@convention(c) (UnsafePointer<UInt8>?, CInt) -> CInt)?) -> CInt { -ENOSYS }
@c func swift_eth_rx(_ buffer: UnsafeMutablePointer<UInt8>?, _ len: UInt16) -> CInt { -ENOSYS }
@c func swift_eth_event_send(_ eventID: Int32, _ eventData: UnsafeMutableRawPointer?, _ eventDataSize: Int, _ ticksToWait: Int) -> CInt { -ENOSYS }

// MARK: - I2S

@c func swifthal_i2s_open(_ id: CInt) -> UnsafeMutableRawPointer? { nil }
@c func swifthal_i2s_handle_get(_ id: CInt) -> UnsafeMutableRawPointer? { nil }
@c func swifthal_i2s_id_get(_ i2s: UnsafeMutableRawPointer?) -> CInt { -1 }
@c func swifthal_i2s_close(_ i2s: UnsafeMutableRawPointer?) -> CInt { -ENOSYS }
@c func swifthal_i2s_config_set(_ i2s: UnsafeMutableRawPointer?, _ dir: swift_i2s_dir_t, _ cfg: UnsafePointer<swift_i2s_cfg_t>?) -> CInt { -ENOSYS }
@c func swifthal_i2s_config_get(_ i2s: UnsafeMutableRawPointer?, _ dir: swift_i2s_dir_t, _ cfg: UnsafeMutablePointer<swift_i2s_cfg_t>?) -> CInt { -ENOSYS }
@c func swifthal_i2s_trigger(_ i2s: UnsafeMutableRawPointer?, _ dir: swift_i2s_dir_t, _ cmd: i2s_trigger_cmd_t) -> CInt { -ENOSYS }
@c func swifthal_i2s_status_get(_ i2s: UnsafeMutableRawPointer?, _ dir: swift_i2s_dir_t) -> CInt { -ENOSYS }
@c func swifthal_i2s_write(_ i2s: UnsafeMutableRawPointer?, _ buf: UnsafePointer<UInt8>?, _ length: Int) -> CInt { -ENOSYS }
@c func swifthal_i2s_read(_ i2s: UnsafeMutableRawPointer?, _ buf: UnsafeMutablePointer<UInt8>?, _ length: Int) -> CInt { -ENOSYS }
@c func swifthal_i2s_dev_number_get() -> CInt { 0 }

// MARK: - LCD

@c func swifthal_lcd_open(_ param: UnsafePointer<swift_lcd_panel_param_t>?) -> UnsafeMutableRawPointer? { nil }
@c func swifthal_lcd_close(_ lcd: UnsafeMutableRawPointer?) -> CInt { -ENOSYS }
@c func swifthal_lcd_start(_ lcd: UnsafeMutableRawPointer?, _ buf: UnsafeMutableRawPointer?, _ size: UInt32) -> CInt { -ENOSYS }
@c func swifthal_lcd_stop(_ lcd: UnsafeMutableRawPointer?) -> CInt { -ENOSYS }
@c func swifthal_lcd_fb_update(_ lcd: UnsafeMutableRawPointer?, _ buf: UnsafeMutableRawPointer?, _ size: UInt32) -> CInt { -ENOSYS }
@c func swifthal_lcd_screen_param_get(_ lcd: UnsafeMutableRawPointer?, _ width: UnsafeMutablePointer<CInt>?, _ height: UnsafeMutablePointer<CInt>?, _ format: UnsafeMutablePointer<swift_lcd_pixel_format_t>?, _ bpp: UnsafeMutablePointer<CInt>?) -> CInt {
  // The original C stub zeroed all out-params before returning; preserve that so
  // a caller reading them after -ENOSYS sees defined zeros, not stack garbage.
  width?.pointee = 0
  height?.pointee = 0
  format.map { _ = memset($0, 0, MemoryLayout<swift_lcd_pixel_format_t>.size) }
  bpp?.pointee = 0
  return -ENOSYS
}
@c func swifthal_lcd_refresh_rate_get(_ lcd: UnsafeMutableRawPointer?) -> CInt { -ENOSYS }

// MARK: - PWM

@c func swifthal_pwm_open(_ id: CInt) -> UnsafeMutableRawPointer? { nil }
@c func swifthal_pwm_close(_ pwm: UnsafeMutableRawPointer?) -> CInt { -ENOSYS }
@c func swifthal_pwm_set(_ pwm: UnsafeMutableRawPointer?, _ period: Int, _ pulse: Int) -> CInt { -ENOSYS }
@c func swifthal_pwm_suspend(_ pwm: UnsafeMutableRawPointer?) -> CInt { -ENOSYS }
@c func swifthal_pwm_resume(_ pwm: UnsafeMutableRawPointer?) -> CInt { -ENOSYS }
@c func swifthal_pwm_info_get(_ pwm: UnsafeMutableRawPointer?, _ info: UnsafeMutablePointer<swift_pwm_info_t>?) -> CInt { -ENOSYS }
@c func swifthal_pwm_dev_number_get() -> CInt { 0 }

// MARK: - WiFi

@c func swift_wifi_scan(_ results: UnsafeMutablePointer<swift_wifi_scan_result_t>?, _ num: CInt) -> CInt { -ENOSYS }
@c func swift_wifi_connect(_ ssid: UnsafeMutablePointer<CChar>?, _ ssidLength: CInt, _ psk: UnsafeMutablePointer<CChar>?, _ pskLength: CInt) -> CInt { -ENOSYS }
@c func swift_wifi_disconnect() -> CInt { -ENOSYS }
@c func swift_wifi_ap_mode_set(_ enable: CInt, _ ssid: UnsafeMutablePointer<CChar>?, _ ssidLength: CInt, _ psk: UnsafeMutablePointer<CChar>?, _ pskLength: CInt) -> CInt { -ENOSYS }
@c func swift_wifi_status_get(_ status: UnsafeMutablePointer<swift_wifi_status_t>?) -> CInt {
  // The original C stub memset the status struct before returning; preserve that
  // so a caller reading it after -ENOSYS sees a defined all-zero status.
  status?.pointee = swift_wifi_status_t()
  return -ENOSYS
}
