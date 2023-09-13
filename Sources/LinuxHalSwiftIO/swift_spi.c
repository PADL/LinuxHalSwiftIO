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
#include <fcntl.h>
#include <string.h>
#include <limits.h>
#include <inttypes.h>
#include <sys/ioctl.h>
#ifdef __linux__
#include <linux/spi/spidev.h>
#include <gpiod.h> // for DATA_AVAILABLE pin
#endif
#include <dispatch/dispatch.h>

#include "swift_hal_internal.h"

struct swifthal_spi {
    dispatch_fd_t fd;
    uint32_t speed_old;
    uint16_t operation_old;
    void (*w_notify)(void *);
    void (*r_notify)(void *);
    dispatch_queue_t queue;
    dispatch_source_t source;
    struct swifthal_gpio *data_avail;
};

static void swifthal_spi__data_available_handler(struct swifthal_spi *spi,
                                                 bool value);

// FIXME is async I/O actually supported by the Linux SPI subsystems? appears
// not
static int swifthal_spi__enable_nbio(struct swifthal_spi *spi) {
    int flags = fcntl(spi->fd, F_GETFL, 0);
    if ((flags & O_NONBLOCK) == 0) {
        if (fcntl(spi->fd, F_SETFL, flags | O_NONBLOCK) < 0) {
            fprintf(
                stderr,
                "LinuxHalSwiftIO: failed to enable non-blocking I/O on SPI fd "
                "%d: %m\n",
                spi->fd);
            return -errno;
        }
    }
    return 0;
}

static int swifthal_spi__io_create(struct swifthal_spi *spi) {
    int err;

    err = swifthal_spi__enable_nbio(spi);
    if (err < 0)
        return err;

    spi->source = dispatch_source_create(DISPATCH_SOURCE_TYPE_READ, spi->fd, 0,
                                         spi->queue);
    if (spi->source)
        return -errno;

    return 0;
}

static int swifthal_spi__read_config(struct swifthal_spi *spi,
                                     uint32_t *speed,
                                     uint16_t *operation) {
#ifdef __linux__
    uint8_t tmp;

    *speed = 0;
    *operation = 0;

    if (ioctl(spi->fd, SPI_IOC_RD_MAX_SPEED_HZ, speed) < 0)
        return -errno;

    if (ioctl(spi->fd, SPI_IOC_RD_MODE, &tmp) < 0)
        return -errno;

    if (tmp & SPI_CPOL)
        *operation |= SWIFT_SPI_MODE_CPOL;
    if (tmp & SPI_CPHA)
        *operation |= SWIFT_SPI_MODE_CPHA;
    if (tmp & SPI_LOOP)
        *operation |= SWIFT_SPI_MODE_LOOP;

    if (ioctl(spi->fd, SPI_IOC_RD_LSB_FIRST, &tmp) < 0)
        return -errno;

    *operation |= tmp ? SWIFT_SPI_TRANSFER_LSB : SWIFT_SPI_TRANSFER_MSB;

    if (ioctl(spi->fd, SPI_IOC_RD_BITS_PER_WORD, &tmp) < 0)
        return -errno;

    switch (tmp) {
    case 8:
        *operation |= SWIFT_SPI_TRANSFER_8_BITS;
        break;
    default:
        return -EINVAL;
    }

    return 0;
#else
    return -ENOSYS;
#endif
}

void *swifthal_spi_open(int id,
                        int speed,
                        unsigned short operation,
                        void (*w_notify)(void *),
                        void (*r_notify)(void *)) {
    struct swifthal_spi *spi;
    int err;

    spi = swifthal_spi_open_ex(
        id, speed, operation,
        dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0));
    if (spi == NULL)
        return NULL;

    if (w_notify || r_notify) {
        err = swifthal_spi__io_create(spi);
        if (err) {
            swifthal_spi_close(spi);
            return NULL;
        }

        spi->w_notify = w_notify;
        spi->r_notify = r_notify;
    }

    return spi;
}

void *swifthal_spi_open_ex(int id,
                           int speed,
                           unsigned short operation,
                           dispatch_queue_t queue) {
    struct swifthal_spi *spi;
    char device[PATH_MAX + 1];
    int err;

    spi = calloc(1, sizeof(*spi));
    if (spi == NULL)
        return NULL;

    // FIXME: how to integrate with CS from calling library
    snprintf(device, sizeof(device), "/dev/spidev%d.0", id);

    spi->fd = open(device, O_RDWR);
    if (spi->fd < 0) {
        swifthal_spi_close(spi);
        return NULL;
    }

    dispatch_retain(queue);
    spi->queue = queue;

    // save previous configuration so we can restore it
    if (swifthal_spi__read_config(spi, &spi->speed_old, &spi->operation_old) <
            0 ||
        swifthal_spi_config(spi, speed, operation) < 0) {
        swifthal_spi_close(spi);
        return NULL;
    }

    return spi;
}

int swifthal_spi_close(void *arg) {
    struct swifthal_spi *spi = arg;

    if (spi) {
        if (spi->speed_old)
            (void)swifthal_spi_config(spi, spi->speed_old, spi->operation_old);
        if (spi->fd != -1)
            close(spi->fd);
        if (spi->queue)
            dispatch_release(spi->queue);
        if (spi->source) {
            dispatch_source_cancel(spi->source);
            dispatch_release(spi->source);
        }
        if (spi->data_avail)
            swifthal_gpio_close(spi->data_avail);
        free(spi);
        return 0;
    }

    return -EINVAL;
}

int swifthal_spi_set_data_available(void *arg, int data_avail) {
    struct swifthal_spi *spi = arg;

    if (spi == NULL)
        return -EINVAL;

    if (data_avail == -1) {
        int err = swifthal_gpio_close(spi->data_avail);
        if (err == 0)
            spi->data_avail = NULL;
    }

    spi->data_avail = swifthal_gpio_open(data_avail, SWIFT_GPIO_DIRECTION_IN,
                                         SWIFT_GPIO_MODE_PULL_NONE);
    if (spi->data_avail == NULL)
        return EINVAL;

    swifthal_gpio__set_handler(spi->data_avail, ^{
      bool rising_edge;

      if (swifthal_gpio__event_read(spi->data_avail, &rising_edge) == 0)
          swifthal_spi__data_available_handler(spi, rising_edge);
    });

    return 0;
}

int swifthal_spi_config(void *arg, int speed, unsigned short operation) {
#ifdef __linux__
    struct swifthal_spi *spi = arg;
    uint8_t mode = 0;
    uint8_t lsb;
    uint8_t bpw;
    uint32_t freq = speed;

    if (spi == NULL)
        return -EINVAL;

    if (operation & SWIFT_SPI_MODE_CPOL) {
        mode |= SPI_CPOL;
    }
    if (operation & SWIFT_SPI_MODE_CPHA) {
        mode |= SPI_CPHA;
    }
    if (operation & SWIFT_SPI_MODE_LOOP) {
        mode |= SPI_LOOP;
    }

    if (ioctl(spi->fd, SPI_IOC_WR_MODE, &mode) < 0)
        return -errno;

    if (operation & SWIFT_SPI_TRANSFER_LSB) {
        lsb = 1;
    } else {
        lsb = 0;
    }
    if (ioctl(spi->fd, SPI_IOC_WR_LSB_FIRST, &lsb) < 0)
        return -errno;

    if (operation & SWIFT_SPI_TRANSFER_8_BITS) {
        bpw = 8;
    } else {
        bpw = 0;
    }
    if (bpw) {
        if (ioctl(spi->fd, SPI_IOC_WR_BITS_PER_WORD, &bpw) < 0)
            return -errno;
    }

    if (freq) {
        if (ioctl(spi->fd, SPI_IOC_WR_MAX_SPEED_HZ, &freq) < 0)
            return -errno;
    }
#else
    return -ENOSYS;
#endif
    return 0;
}

int swifthal_spi_write(void *arg, const unsigned char *buf, int length) {
    struct swifthal_spi *spi = arg;

    if (spi) {
        ssize_t nbytes = write(spi->fd, buf, length);
        if (nbytes < 0)
            return -errno;
        else
            return (int)nbytes;
    }

    return -EINVAL;
}

int swifthal_spi_read(void *arg, unsigned char *buf, int length) {
    struct swifthal_spi *spi = arg;

    if (spi) {
        ssize_t nbytes = read(spi->fd, buf, length);
        if (nbytes < 0)
            return -errno;
        else
            return (int)nbytes;
    }

    return -EINVAL;
}

int swifthal_spi_transceive(void *arg,
                            const unsigned char *w_buf,
                            int w_length,
                            unsigned char *r_buf,
                            int r_length) {
#ifdef __linux__
    struct swifthal_spi *spi = arg;
    struct spi_ioc_transfer xfer;

    if (spi == NULL || w_buf == NULL || r_buf == NULL)
        return -EINVAL;

    memset(&xfer, 0, sizeof(xfer));
    memset(r_buf, 0, r_length);

    xfer.tx_buf = (uintptr_t)w_buf;
    xfer.rx_buf = (uintptr_t)r_buf;
    xfer.len = MIN(w_length, r_length); // FIXME: fix API

    if (ioctl(spi->fd, SPI_IOC_MESSAGE(1), &xfer) < 0)
        return -errno;

    return 0;
#else
    return -ENOSYS;
#endif
}

int swifthal_spi_async_enable(void *arg) {
    struct swifthal_spi *spi = arg;

    if (spi == NULL)
        return -EINVAL;

    if (spi->source)
        return -EEXIST;

    return swifthal_spi__io_create(arg);
}

int swifthal_spi_async_write(void *arg, const unsigned char *buf, int length) {
    struct swifthal_spi *spi = arg;
    dispatch_data_t data;

    if (spi == NULL || spi->source == NULL || spi->w_notify == NULL)
        return -EINVAL;

    data = dispatch_data_create(buf, length, spi->queue,
                                DISPATCH_DATA_DESTRUCTOR_DEFAULT);
    if (data == NULL)
        return -ENOMEM;

    dispatch_write(spi->fd, data, spi->queue,
                   ^(dispatch_data_t data, int error) {
                     spi->w_notify(spi);
                   });

    dispatch_release(data);

    return 0;
}

int swifthal_spi_async_read(void *arg, unsigned char *buf, int length) {
    struct swifthal_spi *spi = arg;

    if (spi == NULL || spi->source == NULL || spi->r_notify == NULL)
        return -EINVAL;

    return -ENOSYS;
}

// FIXME: implement this by interrogating /sys/class/spi_master
int swifthal_spi_dev_number_get(void) { return 0; }

static int swifthal_spi__async_read_single(
    struct swifthal_spi *spi,
    size_t length, /* buffer size */
    bool (^handler)(bool done, const uint8_t *data, size_t count, int error)) {

    dispatch_read(
        spi->fd, length, spi->queue, ^(dispatch_data_t data, int error) {
          if (data == NULL) {
              handler(true, NULL, 0, error);
              return;
          }
          dispatch_data_apply(data, ^(dispatch_data_t rgn, size_t offset,
                                      const void *loc, size_t size) {
            bool done = dispatch_data_get_size(data) == offset + size;
            return handler(done, loc, size, error);
          });
        });

    return 0;
}

static int swifthal_spi__async_read_available(
    struct swifthal_spi *spi,
    size_t length, /* buffer size */
    bool (^handler)(bool done, const uint8_t *data, size_t count, int error)) {

    return -EINVAL;
}

int swifthal_spi_async_read_with_handler(
    void *arg,
    size_t length,
    bool (^handler)(bool done, const uint8_t *data, size_t count, int error)) {
    struct swifthal_spi *spi = arg;

    if (spi == NULL)
        return -EINVAL;

    // if we have a DATA_AVAILABLE GPIO pin set, then keep reading until
    // we fill buffer or pin changes state
    if (spi->data_avail)
        return swifthal_spi__async_read_available(arg, length, handler);
    else
        return swifthal_spi__async_read_single(arg, length, handler);
}

int swifthal_spi_async_write_with_handler(
    void *arg,
    const uint8_t *buffer,
    size_t length,
    bool (^handler)(bool done, const uint8_t *data, size_t count, int error)) {
    struct swifthal_spi *spi = arg;
    dispatch_data_t data;

    if (spi == NULL)
        return -EINVAL;

    data = dispatch_data_create(buffer, length, spi->queue,
                                DISPATCH_DATA_DESTRUCTOR_DEFAULT);
    if (data == NULL)
        return -ENOMEM;

    dispatch_write(
        spi->fd, data, spi->queue, ^(dispatch_data_t data, int error) {
          if (data == NULL) {
              handler(true, NULL, 0, error);
              return;
          }
          dispatch_data_apply(data, ^(dispatch_data_t rgn, size_t offset,
                                      const void *loc, size_t size) {
            bool done = dispatch_data_get_size(data) == offset + size;
            return handler(done, loc, size, error);
          });
        });

    dispatch_release(data);

    return 0;
}

static void swifthal_spi__data_available_handler(struct swifthal_spi *spi,
                                                 bool value) {}
