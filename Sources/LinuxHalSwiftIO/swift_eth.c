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

#include "swift_hal_internal.h"

int swift_eth_setup_mac(const uint8_t *mac) { return -ENOSYS; }

int swift_eth_tx_register(int (*send)(const uint8_t *, int)) {
    return -ENOSYS;
}

int swift_eth_rx(uint8_t *data, uint16_t len) { return -ENOSYS; }

int swift_eth_event_send(int32_t event_id,
                         void *event_data,
                         ssize_t event_data_size,
                         ssize_t ticks_to_wait) {
    return -ENOSYS;
}
