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

#include "swift_hal.h"

struct swifthal_uart {
    struct swift_uart_cfg cfg;
};

void *swifthal_uart_open(int id, const swift_uart_cfg_t *cfg) {
    struct swifthal_uart *uart;
    int err;

    uart = calloc(1, sizeof(*uart));
    if (uart == NULL)
        return NULL;

    uart->cfg.read_buf_len = cfg->read_buf_len;

    err = swifthal_uart_baudrate_set(uart, cfg->baudrate);
    if (err == 0)
        err = swifthal_uart_parity_set(uart, cfg->parity);
    if (err == 0)
        err = swifthal_uart_stop_bits_set(uart, cfg->stop_bits);
    if (err == 0)
        err = swifthal_uart_data_bits_set(uart, cfg->data_bits);

    if (err) {
        swifthal_uart_close(uart);
        return NULL;
    }

    return uart;
}

int swifthal_uart_close(void *arg) {
    struct swifthal_uart *uart = arg;

    if (uart == NULL)
        return -EINVAL;

    free(uart);
    return 0;
}

int swifthal_uart_baudrate_set(void *arg, int baudrate) {
    struct swifthal_uart *uart = arg;

    if (uart == NULL || baudrate == 0)
        return -EINVAL;
    
    uart->cfg.baudrate = baudrate;

    return -ENOSYS;
}

int swifthal_uart_parity_set(void *uart, swift_uart_parity_t parity) {
    return -ENOSYS;
}

int swifthal_uart_stop_bits_set(void *uart, swift_uart_stop_bits_t stop_bits) {
    return -ENOSYS;
}

int swifthal_uart_data_bits_set(void *uart,
                                swift_uart_data_bits_t data_bits) {
    return -ENOSYS;
}

int swifthal_uart_config_get(void *uart, swift_uart_cfg_t *cfg) {
    memset(cfg, 0, sizeof(*cfg));
    return -ENOSYS;
}

int swifthal_uart_char_put(void *uart, unsigned char c) { return -ENOSYS; }

int swifthal_uart_char_get(void *uart, unsigned char *c, int timeout) {
    return -ENOSYS;
}

int swifthal_uart_write(void *uart, const unsigned char *buf, int length) {
    return -ENOSYS;
}

int swifthal_uart_read(void *uart,
                       unsigned char *buf,
                       int length,
                       int timeout) {
    return -ENOSYS;
}

int swifthal_uart_remainder_get(void *uart) { return 0; }

int swifthal_uart_buffer_clear(void *uart) { return -ENOSYS; }

int swifthal_uart_dev_number_get(void) { return 0; }
