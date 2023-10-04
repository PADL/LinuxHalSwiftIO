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
#include <fcntl.h>

#include "swift_hal_internal.h"

void *swifthal_i2s_open(int id) { return NULL; }

void *swifthal_i2s_handle_get(int id) { return NULL; }

int swifthal_i2s_id_get(void *i2s) { return -1; }

int swifthal_i2s_close(void *i2s) { return -ENOSYS; }

int swifthal_i2s_config_set(void *i2s,
                            const swift_i2s_dir_t dir,
                            const swift_i2s_cfg_t *cfg) {
    return -ENOSYS;
}

int swifthal_i2s_config_get(void *i2s,
                            const swift_i2s_dir_t dir,
                            swift_i2s_cfg_t *cfg) {
    return -ENOSYS;
}

int swifthal_i2s_trigger(void *i2s,
                         const swift_i2s_dir_t dir,
                         const i2s_trigger_cmd_t cmd) {
    return -ENOSYS;
}

int swifthal_i2s_status_get(void *i2s, const swift_i2s_dir_t dir) {
    return -ENOSYS;
}

int swifthal_i2s_write(void *i2s, const uint8_t *buf, ssize_t length) {
    return -ENOSYS;
}

int swifthal_i2s_read(void *i2s, uint8_t *buf, ssize_t length) {
    return -ENOSYS;
}

int swifthal_i2s_dev_number_get(void) { return 0; }
