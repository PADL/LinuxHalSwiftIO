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
    unsigned short operation;
    dispatch_queue_t queue;
    void (*w_notify)(void *);
    void (*r_notify)(void *);
    dispatch_io_t channel;
};

// FIXME is async I/O actually supported by the Linux SPI subsystems? appears
// not
static int swifthal_spi__enable_nbio(struct swifthal_spi *spi) {
    int flags = fcntl(spi->fd, F_GETFL, 0);
    if ((flags & O_NONBLOCK) == 0) {
        if (fcntl(spi->fd, F_SETFL, flags | O_NONBLOCK) < 0) {
            fprintf(stderr,
                    "LinuxHalSwiftIO: failed to set non-blocked I/O on SPI fd "
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

    spi->channel = dispatch_io_create(DISPATCH_IO_STREAM, spi->fd, spi->queue,
                                      ^(int error){
                                      });
    if (spi->channel == NULL)
        return -ENOMEM;

    return 0;
}

void *swifthal_spi_open(int id,
                        int speed,
                        unsigned short operation,
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

    spi->queue = dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0);

    if (w_notify || r_notify) {
        err = swifthal_spi__io_create(spi);
        if (err) {
            swifthal_spi_close(spi);
            return NULL;
        }

        spi->w_notify = w_notify;
        spi->r_notify = r_notify;
    }

    if (swifthal_spi_config(spi, speed, operation) < 0) {
        swifthal_spi_close(spi);
        return NULL;
    }

    return spi;
}

int swifthal_spi_close(void *arg) {
    struct swifthal_spi *spi = arg;

    if (spi) {
        if (spi->fd != -1)
            close(spi->fd);
        if (spi->channel) {
            dispatch_io_close(spi->channel, DISPATCH_IO_STOP);
            dispatch_release(spi->channel);
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

    spi->operation = operation;
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

int swifthal_spi_async_enable(void *arg) {
    struct swifthal_spi *spi = arg;

    if (spi == NULL)
        return -EINVAL;

    if (spi->channel)
        return -EEXIST;

    return swifthal_spi__io_create(arg);
}

int swifthal_spi_async_write(void *arg, const unsigned char *buf, int length) {
    struct swifthal_spi *spi = arg;
    dispatch_data_t data;

    if (spi == NULL || spi->channel == NULL || spi->w_notify == NULL)
        return -EINVAL;

    data = dispatch_data_create(buf, length, spi->queue,
                                DISPATCH_DATA_DESTRUCTOR_DEFAULT);
    if (data == NULL)
        return -ENOMEM;

    dispatch_io_write(spi->channel, 0, data, spi->queue,
                      ^(bool done, dispatch_data_t data, int error) {
                        spi->w_notify(spi);
                      });

    dispatch_release(data);

    return 0;
}

int swifthal_spi_async_read(void *arg, unsigned char *buf, int length) {
    struct swifthal_spi *spi = arg;

    if (spi == NULL || spi->channel == NULL || spi->r_notify == NULL)
        return -EINVAL;

    dispatch_io_read(spi->channel, 0, length, spi->queue,
                     ^(bool done, dispatch_data_t data, int error) {
                       // FIXME: this API doesn't really make sense and probably
                       // won't work!
                       if (error == 0) {
                           dispatch_data_apply(
                               data, ^(dispatch_data_t rgn, size_t offset,
                                       const void *loc, size_t size) {
                                 memcpy(buf + offset, loc, size);
                                 return (bool)(offset + size == length);
                               });
                       }
                       spi->r_notify(spi);
                     });

    return 0;
}

// FIXME: implement this by interrogating /sys/class/spi_master
int swifthal_spi_dev_number_get(void) { return 0; }

int swifthal_spi_async_read_with_handler(
    void *arg,
    size_t length,
    bool (^handler)(bool done, const uint8_t *data, size_t count, int error)) {
    struct swifthal_spi *spi = arg;

    if (spi == NULL)
        return EINVAL;

    dispatch_io_read(
        spi->channel, 0, length, spi->queue,
        ^(bool done, dispatch_data_t data, int error) {
          if (data == NULL) {
            handler(done, NULL, 0, error);
            return;
          }
          dispatch_data_apply(data, ^(dispatch_data_t rgn, size_t offset,
                                      const void *loc, size_t size) {
            bool done2;

            if (done)
                done2 = dispatch_data_get_size(data) == offset + size;
            else
                done2 = false;
            return handler(done2, loc, size, error);
          });
        });

    return 0;
}

int swifthal_spi_async_write_with_handler(
    void *arg,
    const uint8_t *buffer,
    size_t length,
    bool (^handler)(bool done, const uint8_t *data, size_t count, int error)) {
    struct swifthal_spi *spi = arg;
    dispatch_data_t data;

    if (spi == NULL)
        return EINVAL;

    data = dispatch_data_create(buffer, length, spi->queue,
                                DISPATCH_DATA_DESTRUCTOR_DEFAULT);
    if (data == NULL)
        return -ENOMEM;

    dispatch_io_write(
        spi->channel, 0, data, spi->queue,
        ^(bool done, dispatch_data_t data, int error) {
          if (data == NULL) {
            handler(done, NULL, 0, error);
            return;
          }
          dispatch_data_apply(data, ^(dispatch_data_t rgn, size_t offset,
                                      const void *loc, size_t size) {
            bool done2;

            if (done)
                done2 = dispatch_data_get_size(data) == offset + size;
            else
                done2 = false;
            return handler(done2, loc, size, error);
          });
        });

    dispatch_release(data);

    return 0;
}
