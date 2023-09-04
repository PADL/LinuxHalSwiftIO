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
#include <linux/i2c.h>
#include <linux/i2c-dev.h>
#endif
#include <dispatch/dispatch.h>

#include "swift_hal.h"

struct swifthal_i2c {
    int fd;
    dispatch_queue_t queue;
};

void *swifthal_i2c_open(int id) {
    struct swifthal_i2c *i2c;
    char device[PATH_MAX + 1];

    i2c = calloc(1, sizeof(*i2c));
    if (i2c == NULL)
        return NULL;

    snprintf(device, sizeof(device), "/dev/i2c-%d", id);

    i2c->fd = open(device, O_RDWR);
    if (i2c->fd < 0) {
        swifthal_i2c_close(i2c);
        return NULL;
    }

    i2c->queue = dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0);

    return i2c;
}

int swifthal_i2c_close(void *arg) {
    struct swifthal_i2c *i2c = arg;

    if (i2c) {
        if (i2c->fd != -1)
            close(i2c->fd);
        free(i2c);
        return 0;
    }

    return -EINVAL;
}

int swifthal_i2c_config(void *arg, unsigned int speed) {
    // looks like this needs to be configured in the device tree
    return -ENOSYS;
}

int swifthal_i2c_write(void *arg,
                       unsigned char address,
                       const unsigned char *buf,
                       int length) {
#ifdef __linux__
    struct swifthal_i2c *i2c = arg;

    if (i2c == NULL)
        return -EINVAL;

    if (ioctl(i2c->fd, I2C_SLAVE, address) < 0 ||
        write(i2c->fd, buf, length) < 0)
        return -errno;

    return 0;
#else
    return -ENOSYS;
#endif
}

int swifthal_i2c_read(void *arg,
                      unsigned char address,
                      unsigned char *buf,
                      int length) {
#ifdef __linux__
    struct swifthal_i2c *i2c = arg;

    if (i2c == NULL)
        return -EINVAL;

    if (ioctl(i2c->fd, I2C_SLAVE, address) < 0 ||
        read(i2c->fd, buf, length) < 0)
        return -errno;

    return 0;
#else
    return -ENOSYS;
#endif
}

int swifthal_i2c_write_read(void *arg,
                            unsigned char addr,
                            const void *write_buf,
                            int num_write,
                            void *read_buf,
                            int num_read) {
#ifdef __linux__
    struct swifthal_i2c *i2c = arg;
    struct i2c_msg messages[2];
    struct i2c_rdwr_ioctl_data ioctl_data = {messages, sizeof(messages) /
                                                           sizeof(messages[0])};

    if (i2c == NULL)
        return -EINVAL;

    messages[0].addr = addr;
    messages[0].flags = 0;
    messages[0].len = num_write;
    messages[0].buf = (uint8_t *)write_buf;

    messages[1].addr = addr;
    messages[1].flags = I2C_M_RD | I2C_M_NOSTART;
    messages[1].len = num_read;
    messages[1].buf = read_buf;

    if (ioctl(i2c->fd, I2C_RDWR, &ioctl_data) < 0)
        return -errno;

    return 0;
#else
    return -ENOSYS;
#endif
}

int swifthal_i2c_dev_number_get(void) { return 0; }
