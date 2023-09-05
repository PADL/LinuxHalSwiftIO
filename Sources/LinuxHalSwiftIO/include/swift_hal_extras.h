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

#ifndef SWIFT_SPI_TRANSFER_8_BITS
#define SWIFT_SPI_TRANSFER_8_BITS (1 << 5) // undocumented
#endif
#ifndef SWIFT_SPI_TRANSFER_32_BITS
#define SWIFT_SPI_TRANSFER_32_BITS (1 << 6) // undocumented
#endif

int swifthal_spi_async_read_with_handler(
    void *_Nonnull arg,
    size_t length,
    bool (^_Nonnull handler)(
        bool done, const uint8_t *_Nullable data, size_t count, int error));

int swifthal_spi_async_write_with_handler(
    void *_Nonnull arg,
    const uint8_t *_Nonnull buffer,
    size_t length,
    bool (^_Nonnull handler)(
        bool done, const uint8_t *_Nullable data, size_t count, int error));

int swifthal_spi_async_enable(void * _Nonnull arg);
