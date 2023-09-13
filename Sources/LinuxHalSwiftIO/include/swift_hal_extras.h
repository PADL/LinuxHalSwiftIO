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

#include <dispatch/dispatch.h>

///
/// GPIO
///

int swifthal_gpio_set_handler(void *_Nonnull spi, void (^_Nonnull handler)(void));

///
/// SPI
///

#ifndef SWIFT_SPI_TRANSFER_8_BITS
#define SWIFT_SPI_TRANSFER_8_BITS (1 << 5) // undocumented
#endif

void *_Nullable swifthal_spi_open_ex(int id,
                                     int speed,
                                     unsigned short operation,
                                     dispatch_queue_t _Nonnull queue);

int swifthal_spi_async_enable(void *_Nonnull spi);

int swifthal_spi_async_read_with_handler(
    void *_Nonnull spi,
    size_t length,
    bool (^_Nonnull handler)(
        bool done, const uint8_t *_Nullable data, size_t count, int error));

int swifthal_spi_async_write_with_handler(
    void *_Nonnull spi,
    const uint8_t *_Nonnull buffer,
    size_t length,
    bool (^_Nonnull handler)(
        bool done, const uint8_t *_Nullable data, size_t count, int error));

///
/// UART
///

int swifthal_uart_async_enable(void *_Nonnull uart);

int swifthal_uart_async_read_with_handler(
    void *_Nonnull uart,
    size_t length,
    bool (^_Nonnull handler)(
        bool done, const uint8_t *_Nullable data, size_t count, int error));

int swifthal_uart_async_write_with_handler(
    void *_Nonnull uart,
    const uint8_t *_Nonnull buffer,
    size_t length,
    bool (^_Nonnull handler)(
        bool done, const uint8_t *_Nullable data, size_t count, int error));
