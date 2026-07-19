//
// Copyright (c) 2026 PADL Software Pty Ltd
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

// termios2 line-configuration helpers for the native-Swift UART (UART.swift).
// termios2 lives in <asm/termbits.h>, which redefines `struct termios` and so
// cannot be exposed to Swift alongside Glibc's <termios.h>. Keeping it in this
// isolated .c (declared via plain prototypes in swift_hal_native.h) confines that
// conflict to C while Swift owns the open/buffering/poll logic.

#include <errno.h>
#include <inttypes.h>
#ifdef __linux__
#include <asm/termbits.h>
#include <sys/ioctl.h>
#endif

#include "swift_uart_native.h"

int swifthal_uart__set_baud(int fd, uint32_t baud) {
#ifdef __linux__
  struct termios2 tty;

  if (baud == 0)
    return -EINVAL;
  if (ioctl(fd, TCGETS2, &tty) < 0)
    return -errno;

  tty.c_cflag &= ~(CBAUD);
  tty.c_cflag |= BOTHER;
  tty.c_ospeed = baud;

  tty.c_cflag &= ~(CBAUD << IBSHIFT);
  tty.c_cflag |= BOTHER << IBSHIFT;
  tty.c_ispeed = baud;

  if (ioctl(fd, TCSETS2, &tty) < 0)
    return -errno;
  return 0;
#else
  return -ENOSYS;
#endif
}

int swifthal_uart__set_parity(int fd, int parity) {
#ifdef __linux__
  struct termios2 tty;

  if (ioctl(fd, TCGETS2, &tty) < 0)
    return -errno;

  switch (parity) {
  case 0: // none
    tty.c_cflag &= ~(PARENB | PARODD);
    break;
  case 1: // odd
    tty.c_cflag |= PARENB | PARODD;
    break;
  case 2: // even
    tty.c_cflag |= PARENB;
    tty.c_cflag &= ~(PARODD);
    break;
  default:
    return -EINVAL;
  }

  if (ioctl(fd, TCSETS2, &tty) < 0)
    return -errno;
  return 0;
#else
  return -ENOSYS;
#endif
}

int swifthal_uart__set_stop_bits(int fd, int two) {
#ifdef __linux__
  struct termios2 tty;

  if (ioctl(fd, TCGETS2, &tty) < 0)
    return -errno;

  if (two)
    tty.c_cflag |= CSTOPB;
  else
    tty.c_cflag &= ~(CSTOPB);

  if (ioctl(fd, TCSETS2, &tty) < 0)
    return -errno;
  return 0;
#else
  return -ENOSYS;
#endif
}

int swifthal_uart__set_data_bits_8(int fd) {
#ifdef __linux__
  struct termios2 tty;

  if (ioctl(fd, TCGETS2, &tty) < 0)
    return -errno;

  tty.c_cflag |= CS8;

  if (ioctl(fd, TCSETS2, &tty) < 0)
    return -errno;
  return 0;
#else
  return -ENOSYS;
#endif
}

int swifthal_uart__set_raw(int fd) {
#ifdef __linux__
  struct termios2 tty;

  if (ioctl(fd, TCGETS2, &tty) < 0)
    return -errno;

  tty.c_iflag &=
      ~(IGNBRK | BRKINT | PARMRK | ISTRIP | INLCR | IGNCR | ICRNL | IXON);
  tty.c_oflag &= ~OPOST;
  tty.c_lflag &= ~(ECHO | ECHONL | ICANON | ISIG | IEXTEN);

  if (ioctl(fd, TCSETS2, &tty) < 0)
    return -errno;
  return 0;
#else
  return -ENOSYS;
#endif
}

// Output: *baud, *parity (0/1/2), *stop2 (0/1). Returns -EINVAL if the data
// width is not 8 bits (the only supported value), matching the original.
int swifthal_uart__get_config(int fd,
                                  uint32_t *baud,
                                  int *parity,
                                  int *stop2) {
#ifdef __linux__
  struct termios2 tty;

  if (ioctl(fd, TCGETS2, &tty) < 0)
    return -errno;

  *baud = tty.c_ispeed < tty.c_ospeed ? tty.c_ispeed : tty.c_ospeed;

  if (tty.c_cflag & PARENB)
    *parity = (tty.c_cflag & PARODD) ? 1 : 2;
  else
    *parity = 0;

  *stop2 = (tty.c_cflag & CSTOPB) ? 1 : 0;

  if ((tty.c_cflag & CSIZE) != CS8)
    return -EINVAL;

  return 0;
#else
  return -ENOSYS;
#endif
}
