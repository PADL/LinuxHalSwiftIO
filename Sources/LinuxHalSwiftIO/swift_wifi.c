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

#include "swift_hal_internal.h"

int swift_wifi_scan(swift_wifi_scan_result_t *results, int num) {
  return -ENOSYS;
}

int swift_wifi_connect(char *ssid, int ssid_length, char *psk, int psk_length) {
  return -ENOSYS;
}

int swift_wifi_disconnect(void) { return -ENOSYS; }

int swift_wifi_ap_mode_set(
    int enable, char *ssid, int ssid_length, char *psk, int psk_length) {
  return -ENOSYS;
}

int swift_wifi_status_get(swift_wifi_status_t *status) {
  memset(status, 0, sizeof(*status));
  return -ENOSYS;
}
