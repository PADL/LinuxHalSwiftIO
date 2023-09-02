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

#include "swift_hal.h"

void *swifthal_counter_open(int id) { return NULL; }

int swifthal_counter_close(void *counter) { return -ENOSYS; }

unsigned int swifthal_counter_read(void *counter) {
    return (unsigned int)(-ENOSYS);
}

int swifthal_counter_add_callback(void *counter,
                                  const void *user_data,
                                  void (*callback)(unsigned int,
                                                   const void *)) {
    return -ENOSYS;
}

unsigned int swifthal_counter_freq(void *counter) { return 0; }

unsigned long long int swifthal_counter_ticks_to_us(void *counter,
                                                    unsigned int ticks) {
    return 0;
}

unsigned int swifthal_counter_us_to_ticks(void *counter,
                                          unsigned long long int us) {
    return 0;
}

unsigned int swifthal_counter_get_max_top_value(void *counter) {
    return UINT_MAX;
}

int swifthal_counter_set_channel_alarm(void *counter, unsigned int ticks) {
    return -ENOSYS;
}

int swifthal_counter_cancel_channel_alarm(void *counter) { return -ENOSYS; }

int swifthal_counter_start(void *counter) { return -ENOSYS; }

int swifthal_counter_stop(void *counter) { return -ENOSYS; }

int swifthal_counter_dev_number_get(void) { return 0; }
