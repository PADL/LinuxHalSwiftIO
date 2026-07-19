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

// C helpers for the native-Swift HAL implementation (Sources/LinuxHalSwiftIO/).
//
// Two jobs:
//
//   1. Expose system headers whose declarations the Swift code needs but which
//      the Glibc module map does not surface (mqueue, sys/random, sys/sysinfo,
//      semaphore, pthread, sched). Once included here they become visible to
//      Swift via `import CLinuxHalSwiftIO`.
//
//   2. Wrap the two things Swift's C interop cannot call directly:
//        - function-like ioctl request-number macros (SPI_IOC_MESSAGE(n), the
//          _IOR/_IOW-expanding SPI_IOC_* constants);
//        - the variadic mq_open(), whose trailing attr pointer Swift's importer
//          turns into an un-passable `Any`/CVarArg.
//      (Plain object-like constants such as SPI_CPOL and `struct
//      spi_ioc_transfer` import into Swift natively and need no wrapper.)

#pragma once

#include <inttypes.h>
#include <fcntl.h>
#include <sys/stat.h>
#include <sys/types.h>
#include <pthread.h>
#include <sched.h>
#include <semaphore.h>
#include <syslog.h>

// syslog() is variadic and thus not callable from Swift; wrap a preformatted
// message. Callers do their own interpolation and pass a plain string.
static inline void swifthal__syslog(int priority, const char *msg) {
  syslog(priority, "%s", msg);
}

#ifdef __linux__
#include <sys/ioctl.h>
#include <sys/random.h>
#include <sys/sysinfo.h>
#include <mqueue.h>
#include <linux/spi/spidev.h>
#include <linux/i2c.h>
#include <linux/i2c-dev.h>
#include <dirent.h>
#include <sys/vfs.h>
#endif

#ifdef __linux__

///
/// SPI mode bits: the SPI_* macros expand via _BITUL(), which Swift's importer
/// reports as "structure not supported", so re-expose them as typed constants.
///

static const uint8_t swifthal_spi__cpha = SPI_CPHA;
static const uint8_t swifthal_spi__cpol = SPI_CPOL;
static const uint8_t swifthal_spi__loop = SPI_LOOP;
static const uint8_t swifthal_spi__lsb_first = SPI_LSB_FIRST;

///
/// Message queue (variadic mq_open cannot be called from Swift)
///

static inline mqd_t swifthal_os__mq_open(const char *name,
                                          int oflag,
                                          mode_t mode,
                                          struct mq_attr *attr) {
  return mq_open(name, oflag, mode, attr);
}

///
/// SPI ioctls (request numbers are function-like macros)
///

static inline int swifthal_spi__rd_max_speed(int fd, uint32_t *speed) {
  return ioctl(fd, SPI_IOC_RD_MAX_SPEED_HZ, speed);
}

static inline int swifthal_spi__wr_max_speed(int fd, const uint32_t *speed) {
  return ioctl(fd, SPI_IOC_WR_MAX_SPEED_HZ, speed);
}

static inline int swifthal_spi__rd_mode(int fd, uint8_t *mode) {
  return ioctl(fd, SPI_IOC_RD_MODE, mode);
}

static inline int swifthal_spi__wr_mode(int fd, const uint8_t *mode) {
  return ioctl(fd, SPI_IOC_WR_MODE, mode);
}

static inline int swifthal_spi__rd_lsb_first(int fd, uint8_t *lsb) {
  return ioctl(fd, SPI_IOC_RD_LSB_FIRST, lsb);
}

static inline int swifthal_spi__rd_bits_per_word(int fd, uint8_t *bits) {
  return ioctl(fd, SPI_IOC_RD_BITS_PER_WORD, bits);
}

static inline int swifthal_spi__wr_bits_per_word(int fd, const uint8_t *bits) {
  return ioctl(fd, SPI_IOC_WR_BITS_PER_WORD, bits);
}

// Issue a two-transfer full-duplex SPI message.
static inline int swifthal_spi__message2(int fd,
                                             struct spi_ioc_transfer *xfer) {
  return ioctl(fd, SPI_IOC_MESSAGE(2), xfer);
}

///
/// I2C ioctls (I2C_SLAVE takes a scalar; I2C_RDWR takes a pointer — neither is
/// callable through Swift's variadic ioctl import).
///

static inline int swifthal_i2c__set_slave(int fd, unsigned long addr) {
  return ioctl(fd, I2C_SLAVE, addr);
}

static inline int swifthal_i2c__rdwr(int fd,
                                         struct i2c_rdwr_ioctl_data *data) {
  return ioctl(fd, I2C_RDWR, data);
}

#endif // __linux__
