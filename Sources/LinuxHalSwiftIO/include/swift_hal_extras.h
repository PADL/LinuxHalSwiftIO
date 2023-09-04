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

#ifdef __APPLE__
// because dispatch_data_t is unavailable in Swift
typedef const void *swifthal_spi_dispatch_data_t;
#else
typedef dispatch_data_t swifthal_spi_dispatch_data_t;
#endif

void swifthal_spi_async_read_with_handler(
    void *_Nonnull arg,
    size_t length,
    void (^_Nonnull handler)(swifthal_spi_dispatch_data_t _Nonnull data,
                             int error));

void swifthal_spi_async_write_with_handler(
    void *_Nonnull arg,
    swifthal_spi_dispatch_data_t _Nonnull data,
    void (^_Nonnull handler)(swifthal_spi_dispatch_data_t _Nullable data,
                             int error));
