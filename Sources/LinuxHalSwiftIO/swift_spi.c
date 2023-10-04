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

struct swifthal_spi {
    int fd;
    uint32_t speed_old;
    uint16_t operation_old;
};

static int swifthal_spi__read_config(const struct swifthal_spi *spi,
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
                        ssize_t speed,
                        uint16_t operation,
                        void (*w_notify)(void *),
                        void (*r_notify)(void *)) {
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
    struct swifthal_spi *spi = (struct swifthal_spi *)arg;

    if (spi) {
        if (spi->speed_old)
            (void)swifthal_spi_config(spi, spi->speed_old, spi->operation_old);
        if (spi->fd != -1)
            close(spi->fd);
        free(spi);
        return 0;
    }

    return -EINVAL;
}

int swifthal_spi_config(void *arg, ssize_t speed, uint16_t operation) {
#ifdef __linux__
    const struct swifthal_spi *spi = arg;
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

int swifthal_spi_write(void *arg, const uint8_t *buf, ssize_t length) {
    const struct swifthal_spi *spi = arg;

    if (spi) {
        ssize_t nbytes = write(spi->fd, buf, length);
        if (nbytes < 0)
            return -errno;
        else
            return (int)nbytes;
    }

    return -EINVAL;
}

int swifthal_spi_read(void *arg, uint8_t *buf, ssize_t length) {
    const struct swifthal_spi *spi = arg;

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
                            const uint8_t *w_buf,
                            ssize_t w_length,
                            uint8_t *r_buf,
                            ssize_t r_length) {
#ifdef __linux__
    const struct swifthal_spi *spi = arg;
    struct spi_ioc_transfer xfer[2];

    if (spi == NULL || w_buf == NULL || r_buf == NULL)
        return -EINVAL;

    memset(xfer, 0, sizeof(xfer));
    memset(r_buf, 0, r_length);

    xfer[0].tx_buf = (uintptr_t)w_buf;
    xfer[0].len = w_length;

    xfer[1].rx_buf = (uintptr_t)r_buf;
    xfer[1].len = r_length;

    if (ioctl(spi->fd, SPI_IOC_MESSAGE(2), xfer) < 0)
        return -errno;

    return 0;
#else
    return -ENOSYS;
#endif
}

int swifthal_spi_async_write(void *arg, const uint8_t *buf, ssize_t length) {
    return -ENOSYS;
}

int swifthal_spi_async_read(void *arg, uint8_t *buf, ssize_t length) {
    return -ENOSYS;
}

// FIXME: implement this by interrogating /sys/class/spi_master
int swifthal_spi_dev_number_get(void) { return 0; }

int swifthal_spi_get_fd(const void *arg) {
    const struct swifthal_spi *spi = arg;

    if (spi == NULL)
        return EINVAL;

    return spi->fd;
}
