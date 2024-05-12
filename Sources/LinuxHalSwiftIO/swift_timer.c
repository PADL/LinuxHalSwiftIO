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

#include <stdlib.h>
#include <stdio.h>
#include <unistd.h>
#include <errno.h>
#include <string.h>
#include <stdatomic.h>
#include <dispatch/dispatch.h>

#include "swift_hal_internal.h"

struct swifthal_timer {
  swift_timer_type_t type;
  dispatch_source_t source;
  _Atomic(unsigned int) status;
};

void *swifthal_timer_open(void) {
  struct swifthal_timer *timer = calloc(1, sizeof(*timer));

  if (timer == NULL)
    return NULL;

  timer->source = dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER, 0, 0,
                                         dispatch_get_global_queue(0, 0));
  if (timer->source == NULL) {
    free(timer);
    return NULL;
  }

  timer->type = SWIFT_TIMER_TYPE_ONESHOT;

  return timer;
}

int swifthal_timer_close(void *arg) {
  struct swifthal_timer *timer = (struct swifthal_timer *)arg;

  if (timer) {
    dispatch_source_cancel(timer->source);
    dispatch_release(timer->source);
    free(timer);
    return 0;
  }

  return -EINVAL;
}

int swifthal_timer_start(void *arg, swift_timer_type_t type, ssize_t period) {
  const struct swifthal_timer *timer = arg;

  if (timer) {
    uint64_t interval = NSEC_PER_MSEC * period;

    dispatch_source_set_timer(
        timer->source, dispatch_time(DISPATCH_TIME_NOW, interval),
        (type == SWIFT_TIMER_TYPE_ONESHOT) ? DISPATCH_TIME_FOREVER : interval,
        0);
    return 0;
  }

  return -EINVAL;
}

int swifthal_timer_stop(void *arg) {
  const struct swifthal_timer *timer = arg;

  if (timer) {
    dispatch_source_cancel(timer->source);
    return 0;
  }
  return -EINVAL;
}

int swifthal_timer_add_callback(void *arg,
                                const void *param,
                                void (*callback)(const void *)) {
  struct swifthal_timer *timer = (struct swifthal_timer *)arg;

  if (timer) {
    dispatch_source_set_event_handler(timer->source, ^{
      if (timer->type == SWIFT_TIMER_TYPE_ONESHOT)
        dispatch_source_cancel(timer->source);
      atomic_fetch_add(&timer->status, 1);
      callback(param);
    });
    return 0;
  }

  return -EINVAL;
}

uint32_t swifthal_timer_status_get(void *arg) {
  struct swifthal_timer *timer = (struct swifthal_timer *)arg;

  if (timer) {
    unsigned int status = atomic_exchange(&timer->status, 0);
    return status;
  }

  return 0;
}
