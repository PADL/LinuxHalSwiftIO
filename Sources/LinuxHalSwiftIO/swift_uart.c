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
#include <poll.h>
#include <asm/termbits.h>
#include <sys/ioctl.h>
#include <dispatch/dispatch.h>

#include "swift_hal.h"

struct swifthal_uart {
    int fd;
    dispatch_queue_t queue;
    dispatch_io_t channel;
    size_t read_buf_len;
    off_t read_buf_offset;
    unsigned char read_buf[0];
};

static int swifthal_uart__enable_nbio(struct swifthal_uart *uart) {
    int flags = fcntl(uart->fd, F_GETFL, 0);
    if ((flags & O_NONBLOCK) == 0) {
        if (fcntl(uart->fd, F_SETFL, flags | O_NONBLOCK) < 0) {
            fprintf(
                stderr,
                "LinuxHalSwiftIO: failed to enable non-blocking I/O on UART fd "
                "%d: %m\n",
                uart->fd);
            return -errno;
        }
    }
    return 0;
}

static int swifthal_uart__io_create(struct swifthal_uart *uart) {
    int err;

    uart->channel =
        dispatch_io_create(DISPATCH_IO_STREAM, uart->fd, uart->queue,
                           ^(int error){
                           });
    if (uart->channel == NULL)
        return -ENOMEM;

    return 0;
}

void *swifthal_uart_open(int id, const swift_uart_cfg_t *cfg) {
    struct swifthal_uart *uart;
    char device[PATH_MAX + 1];
    int err;

    uart = calloc(1, sizeof(*uart) + cfg->read_buf_len);
    if (uart == NULL)
        return NULL;

    // FIXME: use this or /dev/serial?
    snprintf(device, sizeof(device), "/dev/ttyAMA%d", id);

    uart->fd = open(device, O_RDWR);
    if (uart->fd < 0) {
        swifthal_uart_close(uart);
        return NULL;
    }

    uart->queue = dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0);

    uart->read_buf_len = (int)cfg->read_buf_len;

    err = swifthal_uart__enable_nbio(uart);
    if (err == 0)
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

    if (uart) {
        if (uart->fd != -1)
            close(uart->fd);
        if (uart->channel) {
            dispatch_io_close(uart->channel, DISPATCH_IO_STOP);
            dispatch_release(uart->channel);
        }

        free(uart);
        return 0;
    }

    return -EINVAL;
}

int swifthal_uart_baudrate_set(void *arg, int baudrate) {
#ifdef __linux__
    struct swifthal_uart *uart = arg;
    struct termios2 tty;

    if (uart == NULL || baudrate == 0)
        return -EINVAL;

    if (ioctl(uart->fd, TCGETS2, &tty) < 0)
        return -errno;

    tty.c_ispeed = tty.c_ospeed = baudrate;

    if (ioctl(uart->fd, TCSETS2, &tty) < 0)
        return -errno;

    return 0;
#else
    return -ENOSYS;
#endif
}

int swifthal_uart_parity_set(void *arg, swift_uart_parity_t parity) {
#ifdef __linux__
    struct swifthal_uart *uart = arg;
    struct termios2 tty;

    if (uart == NULL)
        return -EINVAL;

    if (ioctl(uart->fd, TCGETS2, &tty) < 0)
        return -errno;

    switch (parity) {
    case SWIFT_UART_PARITY_NONE:
        tty.c_cflag &= ~(PARENB | PARODD);
        break;
    case SWIFT_UART_PARITY_ODD:
        tty.c_cflag |= PARENB | PARODD;
        break;
    case SWIFT_UART_PARITY_EVEN:
        tty.c_cflag |= PARENB;
        tty.c_cflag &= ~(PARODD);
        break;
    default:
        return -EINVAL;
    }

    if (ioctl(uart->fd, TCSETS2, &tty) < 0)
        return -errno;

    return 0;
#else
    return -ENOSYS;
#endif
}

int swifthal_uart_stop_bits_set(void *arg, swift_uart_stop_bits_t stop_bits) {
#ifdef __linux__
    struct swifthal_uart *uart = arg;
    struct termios2 tty;

    if (uart == NULL)
        return -EINVAL;

    if (ioctl(uart->fd, TCGETS2, &tty) < 0)
        return -errno;

    switch (stop_bits) {
    case SWIFT_UART_STOP_BITS_2:
        tty.c_cflag |= CSTOPB;
    case SWIFT_UART_STOP_BITS_1:
        tty.c_cflag &= ~(CSTOPB);
        break;
    default:
        return -EINVAL;
    }

    if (ioctl(uart->fd, TCSETS2, &tty) < 0)
        return -errno;

    return 0;
#else
    return -ENOSYS;
#endif
}

int swifthal_uart_data_bits_set(void *arg, swift_uart_data_bits_t data_bits) {
#ifdef __linux__
    struct swifthal_uart *uart = arg;
    struct termios2 tty;

    if (uart == NULL)
        return -EINVAL;

    if (ioctl(uart->fd, TCGETS2, &tty) < 0)
        return -errno;

    switch (data_bits) {
    case SWIFT_UART_DATA_BITS_8:
        tty.c_cflag |= CS8;
        break;
    default:
        return -EINVAL;
    }

    if (ioctl(uart->fd, TCSETS2, &tty) < 0)
        return -errno;

    return 0;
#else
    return -ENOSYS;
#endif
}

int swifthal_uart_config_get(void *arg, swift_uart_cfg_t *cfg) {
#ifdef __linux__
    struct swifthal_uart *uart = arg;
    struct termios2 tty;

    memset(cfg, 0, sizeof(*cfg));

    if (uart == NULL)
        return -EINVAL;

    if (ioctl(uart->fd, TCGETS2, &tty) < 0)
        return -errno;

    cfg->baudrate = MIN(tty.c_ispeed, tty.c_ospeed);

    if (tty.c_cflag & PARENB) {
        if (tty.c_cflag & PARODD)
            cfg->parity = SWIFT_UART_PARITY_ODD;
        else
            cfg->parity = SWIFT_UART_PARITY_EVEN;
    } else {
        cfg->parity = SWIFT_UART_PARITY_NONE;
    }

    if (tty.c_cflag & CSTOPB) {
        cfg->stop_bits = SWIFT_UART_STOP_BITS_2;
    } else {
        cfg->stop_bits = SWIFT_UART_STOP_BITS_1;
    }

    cfg->read_buf_len = uart->read_buf_len;

    switch (tty.c_cflag & CSIZE) {
    case CS8:
        cfg->data_bits = SWIFT_UART_DATA_BITS_8;
    default:
        return -EINVAL;
    }

    return 0;
#else
    return -ENOSYS;
#endif
}

int swifthal_uart_char_put(void *arg, unsigned char c) {
    struct swifthal_uart *uart = arg;

    return swifthal_uart_write(uart, &c, 1);
}

int swifthal_uart_char_get(void *arg, unsigned char *c, int timeout) {
    struct swifthal_uart *uart = arg;

    return swifthal_uart_read(uart, c, 1, timeout);
}

int swifthal_uart_write(void *arg, const unsigned char *buf, int length) {
    struct swifthal_uart *uart = arg;
    struct pollfd pollfd;
    int err;
    const unsigned char *bufp;
    size_t nremain;

    if (uart == NULL)
        return -EINVAL;

    pollfd.fd = uart->fd;
    pollfd.events = POLLOUT;
    pollfd.revents = 0;

    for (bufp = buf, nremain = (size_t)length; nremain;) {
        err = poll(&pollfd, 1, -1);
        if (err < 0)
            return -errno;

        if (pollfd.revents == POLLOUT) {
            size_t nbytes = write(uart->fd, bufp, nremain);
            if (nbytes < 0)
                return -errno;

            nremain -= nbytes;
            bufp += nbytes;
        }
    }

    return 0;
}

int swifthal_uart_read(void *arg, unsigned char *buf, int length, int timeout) {
    struct swifthal_uart *uart = arg;
    struct pollfd pollfd;
    int err;
    unsigned char *bufp;
    size_t nremain;

    if (uart == NULL)
        return -EINVAL;

    pollfd.fd = uart->fd;
    pollfd.events = POLLIN;
    pollfd.revents = 0;

    for (bufp = buf, nremain = (size_t)length; nremain;) {
        ssize_t nbytes;

        err = poll(&pollfd, 1, timeout);
        if (err < 0)
            return -errno;
        else if (err == 0)
            return (int)nremain;

        if (pollfd.revents == POLLIN) {
            size_t nbytes = read(uart->fd, bufp, nremain);
            if (nbytes < 0)
                return -errno;

            nremain -= nbytes;
            bufp += nbytes;
        }
    }

    return 0;
}

int swifthal_uart_remainder_get(void *arg) {
    struct swifthal_uart *uart = arg;

    return uart->read_buf_len - uart->read_buf_offset;
}

int swifthal_uart_buffer_clear(void *arg) {
    struct swifthal_uart *uart = arg;

    if (uart == NULL)
        return -EINVAL;

    uart->read_buf_offset = 0;

    return 0;
}

int swifthal_uart_dev_number_get(void) { return 0; }

int swifthal_uart_async_enable(void *arg) {
    struct swifthal_uart *uart = arg;

    if (uart == NULL)
        return -EINVAL;

    if (uart->channel)
        return -EEXIST;

    return swifthal_uart__io_create(arg);
}
