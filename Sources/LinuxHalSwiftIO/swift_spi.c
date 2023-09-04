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
#endif
#include <dispatch/dispatch.h>

#include "swift_hal.h"

#ifndef SWIFT_SPI_TRANSFER_8_BITS
#define SWIFT_SPI_TRANSFER_8_BITS (1 << 5) // undocumented
#endif
#ifndef SWIFT_SPI_TRANSFER_32_BITS
#define SWIFT_SPI_TRANSFER_32_BITS (1 << 6) // undocumented
#endif

struct swifthal_spi {
    int fd;
    dispatch_queue_t queue;
    dispatch_source_t r_source;
    dispatch_source_t w_source;
};

void *swifthal_spi_open(int id,
                        int speed,
                        unsigned short operation,
                        void (*w_notify)(void *),
                        void (*r_notify)(void *)) {
    struct swifthal_spi *spi;
    char device[PATH_MAX + 1];

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

    spi->queue = dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0);

    if (w_notify) {
        spi->w_source = dispatch_source_create(DISPATCH_SOURCE_TYPE_WRITE,
                                               spi->fd, 0, spi->queue);
        if (spi->w_source == NULL) {
            swifthal_spi_close(spi);
            return NULL;
        }
        dispatch_source_set_event_handler(spi->w_source, ^{
          w_notify(spi);
        });
        dispatch_resume(spi->w_source);
    }

    if (r_notify) {
        spi->r_source = dispatch_source_create(DISPATCH_SOURCE_TYPE_READ,
                                               spi->fd, 0, spi->queue);
        if (spi->r_source == NULL) {
            swifthal_spi_close(spi);
            return NULL;
        }
        dispatch_source_set_event_handler(spi->r_source, ^{
          r_notify(spi);
        });
        dispatch_resume(spi->r_source);
    }

    return spi;
}

int swifthal_spi_close(void *arg) {
    struct swifthal_spi *spi = arg;

    if (spi) {
        if (spi->fd != -1)
            close(spi->fd);
        if (spi->r_source) {
            dispatch_cancel(spi->r_source);
            dispatch_release(spi->r_source);
        }
        if (spi->w_source) {
            dispatch_cancel(spi->w_source);
            dispatch_release(spi->w_source);
        }
        free(spi);
        return 0;
    }

    return -EINVAL;
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

    if (ioctl(spi->fd, SPI_IOC_RD_MODE, &mode) < 0 ||
        ioctl(spi->fd, SPI_IOC_WR_MODE, &mode) < 0)
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
    } else if (operation & SWIFT_SPI_TRANSFER_32_BITS) {
        bpw = 32;
    } else {
        bpw = 0;
    }
    if (ioctl(spi->fd, SPI_IOC_RD_BITS_PER_WORD, &bpw) < 0 ||
        ioctl(spi->fd, SPI_IOC_WR_BITS_PER_WORD, &bpw) < 0)
        return -errno;

    if (ioctl(spi->fd, SPI_IOC_RD_MAX_SPEED_HZ, &freq) < 0 ||
        ioctl(spi->fd, SPI_IOC_WR_MAX_SPEED_HZ, &freq) < 0)
        return -errno;
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

    if (spi) {
        struct spi_ioc_transfer xfer[2];

        memset(xfer, 0, sizeof(xfer));
        xfer[0].tx_buf = (uintptr_t)w_buf;
        xfer[0].len = w_length;
        xfer[1].rx_buf = (uintptr_t)r_buf;
        xfer[1].len = r_length;

        if (ioctl(spi->fd, SPI_IOC_MESSAGE(2), xfer) < 0)
            return -errno;

        return 0;
    }

    return -EINVAL;
#else
    return -ENOSYS;
#endif
}

int swifthal_spi_async_write(void *arg, const unsigned char *buf, int length) {
    struct swifthal_spi *spi = arg;

    if (spi) {
        dispatch_async(spi->queue, ^{
          write(spi->fd, buf, length);
        });
        return 0;
    }

    return -EINVAL;
}

int swifthal_spi_async_read(void *arg, unsigned char *buf, int length) {
    struct swifthal_spi *spi = arg;

    if (spi) {
        dispatch_async(spi->queue, ^{
          read(spi->fd, buf, length);
        });
        return 0;
    }

    return -EINVAL;
}

int swifthal_spi_dev_number_get(void) {
    // FIXME: implement this by scanning /dev
    return 0;
}

void swifthal_spi_async_read_with_handler(
    void *_Nonnull arg,
    size_t length,
    void (^_Nonnull handler)(swifthal_spi_dispatch_data_t _Nonnull data,
                             int error)) {
    struct swifthal_spi *spi = arg;
#ifdef __APPLE__
    dispatch_read(spi->fd, length, spi->queue,
                  ^(dispatch_data_t data, int error) {
                    handler((swifthal_spi_dispatch_data_t)data, error);
                  });
#else
    dispatch_read(spi->fd, length, spi->queue, handler);
#endif
}

void swifthal_spi_async_write_with_handler(
    void *_Nonnull arg,
    swifthal_spi_dispatch_data_t _Nonnull data,
    void (^_Nonnull handler)(swifthal_spi_dispatch_data_t _Nullable data,
                             int error)) {
    struct swifthal_spi *spi = arg;
#ifdef __APPLE__
    dispatch_write(spi->fd, (dispatch_data_t)data, spi->queue,
                   ^(dispatch_data_t data, int error) {
                     handler((swifthal_spi_dispatch_data_t)data, error);
                   });
#else
    dispatch_write(spi->fd, data, spi->queue, handler);
#endif
}
