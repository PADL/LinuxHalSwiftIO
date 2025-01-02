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

#include <inttypes.h>
#include <string.h>
#include <fcntl.h>

#include <sys/param.h>

#if __has_include(<Block.h>)
#include <Block.h>
#elif __has_include(<Block/Block.h>)
#include <Block/Block.h>
#else
void *_Block_copy(const void *);
void _Block_release(const void *);
#endif

#if __has_include(<dispatch/dispatch.h>)
#include <dispatch/dispatch.h>
#else
// on Linux dispatch/dispatch.h is only available with unsafe Swift flags,
// which preclude the use of this package as a versioned dependency
struct dispatch_source_type_s {
} __attribute__((aligned(sizeof(uintptr_t))));

typedef struct dispatch_source_s *dispatch_source_t;
typedef struct dispatch_queue_s *dispatch_queue_t;
typedef const struct dispatch_source_type_s *dispatch_source_type_t;

typedef void (^dispatch_block_t)(void);

extern const struct dispatch_source_type_s _dispatch_source_type_read;
extern const struct dispatch_source_type_s _dispatch_source_type_write;
extern const struct dispatch_source_type_s _dispatch_source_type_timer;

void dispatch_release(void *object);
void dispatch_resume(void *object);
void dispatch_suspend(void *object);

void *dispatch_get_context(void *object);
void dispatch_set_context(void *object, void *context);

void dispatch_source_cancel(void *object);
void dispatch_source_set_event_handler(dispatch_source_t source,
                                       dispatch_block_t handler);
void dispatch_source_set_cancel_handler(dispatch_source_t source,
                                        dispatch_block_t handler);

typedef uint64_t dispatch_time_t;

uintptr_t dispatch_source_get_handle(dispatch_source_t source);

dispatch_queue_t dispatch_get_global_queue(intptr_t identifier,
                                           uintptr_t flags);
dispatch_source_t dispatch_source_create(dispatch_source_type_t type,
                                         uintptr_t handle,
                                         uintptr_t mask,
                                         dispatch_queue_t queue);
void dispatch_source_set_timer(dispatch_source_t source,
                               dispatch_time_t start,
                               uint64_t interval,
                               uint64_t leeway);
dispatch_time_t dispatch_time(dispatch_time_t when, int64_t delta);

#define dispatch_cancel dispatch_source_cancel
#define DISPATCH_QUEUE_PRIORITY_DEFAULT 0
#define DISPATCH_SOURCE_TYPE_READ (&_dispatch_source_type_read)
#define DISPATCH_SOURCE_TYPE_WRITE (&_dispatch_source_type_write)
#define DISPATCH_SOURCE_TYPE_TIMER (&_dispatch_source_type_timer)
#define DISPATCH_TIME_NOW (0ull)
#define DISPATCH_TIME_FOREVER (~0ull)
#endif

#include <syslog.h>

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
