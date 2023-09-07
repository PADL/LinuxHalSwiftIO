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

#include "swift_hal.h"

struct swifthal_counter {
    clockid_t clockid;
};

void *swifthal_counter_open(int id) {
    struct swifthal_counter *counter;

    counter = calloc(1, sizeof(*counter));
    if (counter == NULL)
        return counter;

    counter->clockid = id;

    return counter;
}

int swifthal_counter_close(void *arg) {
    struct swifthal_counter *counter = arg;

    if (counter) {
        free(counter);
        return 0;
    }

    return -EINVAL;
}

unsigned int swifthal_counter_read(void *arg) {
    struct swifthal_counter *counter = arg;
    struct timespec tp;
    unsigned long long us;

    if (counter == NULL)
        return 0;

    if (clock_gettime(counter->clockid, &tp) < 0)
        return 0;

    us = tp.tv_sec * USEC_PER_SEC;
    us += tp.tv_nsec / NSEC_PER_USEC;

    return swifthal_counter_us_to_ticks(counter, us);
}

int swifthal_counter_add_callback(void *arg,
                                  const void *user_data,
                                  void (*callback)(unsigned int,
                                                   const void *)) {
    return -ENOSYS;
}

unsigned int swifthal_counter_freq(void *arg) { return 0; }

unsigned long long int swifthal_counter_ticks_to_us(void *arg,
                                                    unsigned int ticks) {
    return 0;
}

unsigned int swifthal_counter_us_to_ticks(void *arg,
                                          unsigned long long int us) {
    return 0;
}

unsigned int swifthal_counter_get_max_top_value(void *arg) {
    return UINT_MAX;
}

int swifthal_counter_set_channel_alarm(void *arg, unsigned int ticks) {
    return -ENOSYS;
}

int swifthal_counter_cancel_channel_alarm(void *arg) { return -ENOSYS; }

int swifthal_counter_start(void *arg) { return -ENOSYS; }

int swifthal_counter_stop(void *arg) { return -ENOSYS; }

int swifthal_counter_dev_number_get(void) { return 0; }
