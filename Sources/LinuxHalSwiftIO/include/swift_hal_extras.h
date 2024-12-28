//
// Copyright (c) 2023 PADL Software Pty Ltd
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

#pragma once

///
/// GPIO
///

int swifthal_gpio_get_fd(const void *_Nonnull gpio);

int swifthal_gpio_interrupt_callback_install_block(
    void *_Nonnull gpio, void (^_Nonnull)(uint8_t, struct timespec));

///
/// I2C
///

int swifthal_i2c_get_fd(const void *_Nonnull i2c);
int swifthal_i2c_set_addr(const void *_Nonnull i2c, uint8_t addr);

///
/// SPI
///

#ifndef SWIFT_SPI_TRANSFER_8_BITS
#define SWIFT_SPI_TRANSFER_8_BITS (1 << 5) // undocumented
#endif

int swifthal_spi_get_fd(const void *_Nonnull spi);

///
/// UART
///

int swifthal_uart_data_bits_set(const void *_Nonnull uart,
                                swift_uart_data_bits_t data_bits);
int swifthal_uart_get_fd(const void *_Nonnull uart);
