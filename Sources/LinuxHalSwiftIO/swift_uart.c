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

#include <assert.h>
#include <stdlib.h>
#include <stdio.h>
#include <unistd.h>
#include <errno.h>
#include <string.h>
#include <poll.h>
#include <limits.h>
#ifdef __linux__
#include <asm/termbits.h>
#elif defined(__APPLE__)
#include <sys/time.h>
#include <sys/param.h>
#endif
#include <sys/ioctl.h>
#include <dispatch/dispatch.h>

#include "swift_hal_internal.h"

struct swifthal_uart {
    int fd;
    dispatch_queue_t queue;
    dispatch_io_t channel;
    size_t read_buf_len;
    off_t read_buf_offset;
    size_t read_buf_consumed;
    uint8_t read_buf[0];
};

#define SWIFTHAL_UART_REMAIN(uart)                                             \
    ((uart)->read_buf_len - (uart)->read_buf_offset)

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

    swifthal_uart_buffer_clear(uart);

    return uart;
}

int swifthal_uart_close(void *arg) {
    struct swifthal_uart *uart = arg;

    if (uart) {
        if (uart->fd != -1)
            close(uart->fd);

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

static inline int64_t swifthal_uart__tv2ms(struct timeval *tv) {
    uint64_t ms;

    ms = tv->tv_sec * 1000;
    ms += tv->tv_usec / 1000;

    return ms;
}

// read a block of data, returning number of bytes remaining in the
// block if the timeout was reached, or a negative value indicating
// a non-recoverable error
//
// pass NULL for timeout if blocking indefinitely is desired
//
// on return timeout is updated to reflect the number of seconds
// remaining, in case a complete buffer was read within the timeout
static ssize_t swifthal_uart__read_buffer(struct swifthal_uart *uart,
                                          int64_t *timeout) {
    int err;
    struct pollfd pollfd;
    struct timeval now = {.tv_sec = 0, .tv_usec = 0};

    pollfd.fd = uart->fd;

    while (uart->read_buf_offset < uart->read_buf_len) {
        ssize_t nbytes;

        if (timeout) {
            struct timeval prev = now;

            gettimeofday(&now, NULL);

            if (prev.tv_sec) {
                int64_t diff =
                    swifthal_uart__tv2ms(&now) - swifthal_uart__tv2ms(&prev);
                *timeout -= diff;
            }

            if (*timeout < 0)
                break;
        }

        pollfd.events = POLLIN;
        pollfd.revents = 0;

        err = poll(&pollfd, 1, timeout ? *timeout : -1);
        if (err < 0)
            return -errno;
        else if (err == 0)
            break; // timed out

        if (pollfd.revents != POLLIN)
            continue;

        nbytes = read(pollfd.fd, &uart->read_buf[uart->read_buf_offset],
                      SWIFTHAL_UART_REMAIN(uart));
        if (nbytes < 0)
            return -errno;

        uart->read_buf_offset += nbytes;
        assert(uart->read_buf_offset <= uart->read_buf_len);
    }

    return SWIFTHAL_UART_REMAIN(uart);
}

int swifthal_uart_read(void *arg, unsigned char *buf, int length, int timeout) {
    struct swifthal_uart *uart = arg;
    int64_t timeout64 = (int64_t)timeout;
    ssize_t nremain = (size_t)length;
    ssize_t res;

    if (uart == NULL)
        return -EINVAL;

    assert(length > 0);
    assert(buf);

    while (nremain) {
        // check for consumed bytes to return
        if (uart->read_buf_consumed < uart->read_buf_offset) {
            size_t nconsume = MIN(SWIFTHAL_UART_REMAIN(uart), nremain);

            memcpy(buf, &uart->read_buf[uart->read_buf_consumed], nconsume);
            uart->read_buf_consumed += nconsume;
            assert(uart->read_buf_consumed <= uart->read_buf_offset);
            nremain -= nconsume;
        }

        if (nremain == 0)
            break; // all data read

        // reset buffer if it has been completely read
        if (uart->read_buf_offset == uart->read_buf_len) {
            assert(uart->read_buf_consumed == uart->read_buf_offset);
            swifthal_uart_buffer_clear(uart);
        }

        // attempt to read a complete buffer (subject to timeout)
        res =
            swifthal_uart__read_buffer(uart, timeout == -1 ? NULL : &timeout64);
        if (res < 0)
            return res;

        if (timeout64 < 0)
            break; // we timed out
    }

    return (int)nremain;
}

int swifthal_uart_remainder_get(void *arg) {
    struct swifthal_uart *uart = arg;

    return SWIFTHAL_UART_REMAIN(uart);
}

int swifthal_uart_buffer_clear(void *arg) {
    struct swifthal_uart *uart = arg;

    if (uart == NULL)
        return -EINVAL;

    uart->read_buf_offset = 0;
    uart->read_buf_consumed = 0;

#ifndef NDEBUG
    memset(uart->read_buf, 0xff, uart->read_buf_len);
#endif

    return 0;
}

int swifthal_uart_dev_number_get(void) { return 0; }

int swifhtal_uart_get_fd(void *arg) {
    struct swifthal_uart *uart = arg;

    if (uart == NULL)
        return -EINVAL;

    return uart->fd;
}
