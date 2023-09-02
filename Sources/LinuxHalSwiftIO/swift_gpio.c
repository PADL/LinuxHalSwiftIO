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

#include "swift_hal.h"

void *swifthal_gpio_open(int id,
                         swift_gpio_direction_t direction,
                         swift_gpio_mode_t io_mode) {
    return NULL;
}

int swifthal_gpio_close(void *gpio) { return -ENOSYS; }

int swifthal_gpio_config(void *gpio,
                         swift_gpio_direction_t direction,
                         swift_gpio_mode_t io_mode) {
    return -ENOSYS;
}

int swifthal_gpio_set(void *gpio, int level) { return -ENOSYS; }

int swifthal_gpio_get(void *gpio) { return -ENOSYS; }

int swifthal_gpio_interrupt_config(void *gpio, swift_gpio_int_mode_t int_mode) {
    return -ENOSYS;
}

int swifthal_gpio_interrupt_callback_install(void *gpio,
                                             const void *param,
                                             void (*callback)(const void *)) {
    return -ENOSYS;
}

int swifthal_gpio_interrupt_callback_uninstall(void *gpio) { return -ENOSYS; }

int swifthal_gpio_interrupt_enable(void *gpio) { return -ENOSYS; }

int swifthal_gpio_interrupt_disable(void *gpio) { return -ENOSYS; }

int swifthal_gpio_dev_number_get(void) { return 0; }
