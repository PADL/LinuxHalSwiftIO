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
#include <sys/param.h>
#endif
#include <sys/time.h>
#include <sys/ioctl.h>

#include "swift_hal_internal.h"

struct swifthal_uart {
  int fd;
  size_t read_buf_len;
};

#define SWIFTHAL_UART_REMAIN(uart)                                             \
  ((uart)->read_buf_len - (uart)->read_buf_offset)

static int swifthal_uart__enable_nbio(const struct swifthal_uart *uart) {
  int flags = fcntl(uart->fd, F_GETFL, 0);
  if ((flags & O_NONBLOCK) == 0) {
    if (fcntl(uart->fd, F_SETFL, flags | O_NONBLOCK) < 0) {
      syslog(LOG_INFO,
             "LinuxHalSwiftIO: failed to enable non-blocking I/O on UART fd "
             "%d: %m\n",
             uart->fd);
      return -errno;
    }
  }
  return 0;
}

static int swifthal_uart__raw_set(void *arg);

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
    err = swifthal_uart__raw_set(uart);
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
  struct swifthal_uart *uart = (struct swifthal_uart *)arg;

  if (uart) {
    if (uart->fd != -1)
      close(uart->fd);

    free(uart);
    return 0;
  }

  return -EINVAL;
}

int swifthal_uart_baudrate_set(void *arg, ssize_t baudrate) {
#ifdef __linux__
  const struct swifthal_uart *uart = arg;
  struct termios2 tty;

  if (uart == NULL || baudrate == 0)
    return -EINVAL;

  if (ioctl(uart->fd, TCGETS2, &tty) < 0)
    return -errno;

  tty.c_cflag &= ~(CBAUD);
  tty.c_cflag |= BOTHER;
  tty.c_ospeed = baudrate;

  tty.c_cflag &= ~(CBAUD << IBSHIFT);
  tty.c_cflag |= BOTHER << IBSHIFT;
  tty.c_ispeed = baudrate;

  if (ioctl(uart->fd, TCSETS2, &tty) < 0)
    return -errno;

  return 0;
#else
  return -ENOSYS;
#endif
}

int swifthal_uart_parity_set(void *arg, swift_uart_parity_t parity) {
#ifdef __linux__
  const struct swifthal_uart *uart = arg;
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
  const struct swifthal_uart *uart = arg;
  struct termios2 tty;

  if (uart == NULL)
    return -EINVAL;

  if (ioctl(uart->fd, TCGETS2, &tty) < 0)
    return -errno;

  switch (stop_bits) {
  case SWIFT_UART_STOP_BITS_2:
    tty.c_cflag |= CSTOPB;
    break;
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

int swifthal_uart_data_bits_set(const void *arg,
                                swift_uart_data_bits_t data_bits) {
#ifdef __linux__
  const struct swifthal_uart *uart = arg;
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
  const struct swifthal_uart *uart = arg;
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

int swifthal_uart_char_put(void *arg, uint8_t c) {
  struct swifthal_uart *uart = arg;

  return swifthal_uart_write(uart, &c, 1);
}

int swifthal_uart_char_get(void *arg, uint8_t *c, int timeout) {
  struct swifthal_uart *uart = arg;

  return swifthal_uart_read(uart, c, 1, timeout);
}

int swifthal_uart_write(void *arg, const uint8_t *buf, ssize_t length) {
  return -ENOSYS;
}

int swifthal_uart_read(void *arg, uint8_t *buf, ssize_t length, int timeout) {
  return -ENOSYS;
}

int swifthal_uart_remainder_get(void *arg) { return -ENOSYS; }

int swifthal_uart_buffer_clear(void *arg) { return -ENOSYS; }

int swifthal_uart_dev_number_get(void) { return 0; }

int swifthal_uart_get_fd(const void *arg) {
  const struct swifthal_uart *uart = arg;

  if (uart == NULL)
    return -EINVAL;

  return uart->fd;
}

static int swifthal_uart__raw_set(void *arg) {
#ifdef __linux__
  const struct swifthal_uart *uart = arg;
  struct termios2 tty;

  if (uart == NULL)
    return -EINVAL;

  if (ioctl(uart->fd, TCGETS2, &tty) < 0)
    return -errno;

  tty.c_iflag &=
      ~(IGNBRK | BRKINT | PARMRK | ISTRIP | INLCR | IGNCR | ICRNL | IXON);
  tty.c_oflag &= ~OPOST;
  tty.c_lflag &= ~(ECHO | ECHONL | ICANON | ISIG | IEXTEN);

  if (ioctl(uart->fd, TCSETS2, &tty) < 0)
    return -errno;

  return 0;
#else
  return -ENOSYS;
#endif
}
