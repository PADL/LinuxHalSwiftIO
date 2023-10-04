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
#include <limits.h>
#include <time.h>

#include "swift_hal_internal.h"

struct swifthal_counter {
    clockid_t clockid;
};

const void *swifthal_counter_open(int id) {
    struct swifthal_counter *counter;

    counter = calloc(1, sizeof(*counter));
    if (counter == NULL)
        return counter;

    counter->clockid = id;

    return counter;
}

int swifthal_counter_close(const void *arg) {
    struct swifthal_counter *counter = (struct swifthal_counter *)arg;

    if (counter) {
        free(counter);
        return 0;
    }

    return -EINVAL;
}

int swifthal_counter_read(const void *arg, uint32_t *ticks) {
    const struct swifthal_counter *counter = arg;
    struct timespec tp;
    unsigned long us;

    *ticks = 0;

    if (counter == NULL)
        return -EINVAL;

    if (clock_gettime(counter->clockid, &tp) < 0)
        return -errno;

    us = tp.tv_sec * USEC_PER_SEC;
    us += tp.tv_nsec / NSEC_PER_USEC;

    *ticks = swifthal_counter_us_to_ticks(counter, us);
    return 0;
}

int swifthal_counter_add_callback(const void *arg,
                                  const void *user_data,
                                  void (*callback)(uint32_t,
                                                   const void *)) {
    return -ENOSYS;
}

uint32_t swifthal_counter_freq(const void *arg) { return 0; }

uint64_t swifthal_counter_ticks_to_us(const void *arg, uint32_t ticks) {
    return 0;
}

uint32_t swifthal_counter_us_to_ticks(const void *arg, uint64_t us) {
    return 0;
}

uint32_t swifthal_counter_get_max_top_value(const void *arg) { return UINT_MAX; }

int swifthal_counter_set_channel_alarm(const void *arg, uint32_t ticks) {
    return -ENOSYS;
}

int swifthal_counter_cancel_channel_alarm(const void *arg) { return -ENOSYS; }

int swifthal_counter_start(const void *arg) { return -ENOSYS; }

int swifthal_counter_stop(const void *arg) { return -ENOSYS; }

int swifthal_counter_dev_number_get(void) { return 0; }
