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

#include "swift_hal.h"
#include "swift_hal_extras.h"

#define SWIFTHAL_GPIO_CONSUMER "SwiftIO"
#define SWIFTHAL_GPIOCHIP "gpiochip0" // FIXME: make configurable

#ifndef SWIFT_SPI_TRANSFER_8_BITS
#define SWIFT_SPI_TRANSFER_8_BITS (1 << 5) // undocumented
#endif

#ifndef MSEC_PER_SEC
#define MSEC_PER_SEC (1000)
#endif

#ifndef USEC_PER_MSEC
#define USEC_PER_MSEC (1000)
#endif

#ifndef NSEC_PER_USEC
#define NSEC_PER_USEC (1000)
#endif

#ifndef NSEC_PER_MSEC
#define NSEC_PER_MSEC (NSEC_PER_USEC * USEC_PER_MSEC)
#endif

#ifndef USEC_PER_SEC
#define USEC_PER_SEC (USEC_PER_MSEC * MSEC_PER_SEC)
#endif

struct swifthal_counter;
struct swifthal_gpio;
struct swifthal_i2c;
struct swifthal_os_task;
struct swifthal_spi;
struct swifthal_timer;
struct swifthal_uart;

void *swifthal_gpio__open(int id,
                          const char *chip,
                          swift_gpio_direction_t direction,
                          swift_gpio_mode_t io_mode);
