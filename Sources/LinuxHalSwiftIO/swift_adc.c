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

void *swifthal_adc_open(int id) { return NULL; }

int swifthal_adc_close(void *adc) { return -ENOSYS; }

int swifthal_adc_info_get(void *adc, swift_adc_info_t *info) { return -ENOSYS; }

int swifthal_adc_dev_number_get(void) { return 0; }
