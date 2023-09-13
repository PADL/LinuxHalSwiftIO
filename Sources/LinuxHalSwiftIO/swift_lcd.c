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

void *swifthal_lcd_open(const swift_lcd_panel_param_t *param) { return NULL; }

int swifthal_lcd_close(void *lcd) { return -ENOSYS; }

int swifthal_lcd_start(void *lcd, void *buf, unsigned int size) {
    return -ENOSYS;
}

int swifthal_lcd_stop(void *lcd) { return -ENOSYS; }

int swifthal_lcd_fb_update(void *lcd, void *buf, unsigned int size) {
    return -ENOSYS;
}

int swifthal_lcd_screen_param_get(void *lcd,
                                  int *width,
                                  int *height,
                                  swift_lcd_pixel_format_t *format,
                                  int *bpp) {
    *width = 0;
    *height = 0;
    memset(format, 0, sizeof(*format));
    *bpp = 0;
    return -ENOSYS;
}

int swifthal_lcd_refresh_rate_get(void *lcd) { return -ENOSYS; }
