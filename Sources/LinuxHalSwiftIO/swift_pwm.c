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

void *swifthal_pwm_open(int id) { return NULL; }

int swifthal_pwm_close(void *pwm) { return -ENOSYS; }

int swifthal_pwm_set(void *pwm, ssize_t period, ssize_t pulse) {
  return -ENOSYS;
}

int swifthal_pwm_suspend(void *pwm) { return -ENOSYS; }

int swifthal_pwm_resume(void *pwm) { return -ENOSYS; }

int swifthal_pwm_info_get(void *pwm, swift_pwm_info_t *info) {
  memset(info, 0, sizeof(*info));
  return -ENOSYS;
}

int swifthal_pwm_dev_number_get(void) { return 0; }
