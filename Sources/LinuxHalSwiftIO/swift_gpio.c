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
#ifdef __linux__
#include <gpiod.h>
#endif

#include "swift_hal_internal.h"

struct swifthal_gpio {
    swift_gpio_direction_t direction;
    swift_gpio_mode_t io_mode;
#ifdef __linux__
    struct gpiod_chip *chip;
    struct gpiod_line *line;
#endif
    dispatch_queue_t queue;
    dispatch_source_t source;
};

void *swifthal_gpio_open(int id,
                         swift_gpio_direction_t direction,
                         swift_gpio_mode_t io_mode) {
    return swifthal_gpio__open(id, SWIFTHAL_GPIOCHIP, direction, io_mode);
}

void *swifthal_gpio__open(int id,
                          const char *chip,
                          swift_gpio_direction_t direction,
                          swift_gpio_mode_t io_mode) {
    struct swifthal_gpio *gpio;

    gpio = calloc(1, sizeof(*gpio));
    if (gpio == NULL)
        return NULL;

#ifdef __linux__
    gpio->chip = gpiod_chip_open_by_name(chip);
    if (gpio->chip == NULL) {
        swifthal_gpio_close(gpio);
        return NULL;
    }

    gpio->line = gpiod_chip_get_line(gpio->chip, id);
    if (gpio->line == NULL) {
        swifthal_gpio_close(gpio);
        return NULL;
    }

    if (swifthal_gpio_config(gpio, direction, io_mode) < 0) {
        swifthal_gpio_close(gpio);
        return NULL;
    }
#endif

    gpio->queue = dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0);

    return gpio;
}

int swifthal_gpio_close(void *arg) {
    struct swifthal_gpio *gpio = (struct swifthal_gpio *)arg;

    if (gpio) {
#ifdef __linux__
        if (gpio->chip)
            gpiod_chip_close(gpio->chip);
#endif
        if (gpio->source)
            dispatch_release(gpio->source);
        free(gpio);
        return 0;
    }

    return -EINVAL;
}

static int swifthal_gpio__io_mode_flags(swift_gpio_mode_t io_mode, int *flags) {
#ifdef __linux__
    switch (io_mode) {
    case SWIFT_GPIO_MODE_PULL_UP:
        *flags |= GPIOD_LINE_REQUEST_FLAG_BIAS_PULL_UP;
        break;
    case SWIFT_GPIO_MODE_PULL_DOWN:
        *flags |= GPIOD_LINE_REQUEST_FLAG_BIAS_PULL_DOWN;
        break;
    case SWIFT_GPIO_MODE_PULL_NONE:
        *flags |= GPIOD_LINE_REQUEST_FLAG_BIAS_DISABLE;
        break;
    case SWIFT_GPIO_MODE_OPEN_DRAIN:
        *flags |= GPIOD_LINE_REQUEST_FLAG_OPEN_DRAIN;
        break;
    default:
        *flags = 0;
        return -EINVAL;
    }

    return 0;
#else
    return -ENOSYS;
#endif
}

int swifthal_gpio_config(void *arg,
                         swift_gpio_direction_t direction,
                         swift_gpio_mode_t io_mode) {
#ifdef __linux__
    int err;
    struct swifthal_gpio *gpio = (struct swifthal_gpio *)arg;
    struct gpiod_line_request_config lrc;

    if (gpio == NULL)
        return -EINVAL;

    lrc.consumer = SWIFTHAL_GPIO_CONSUMER;
    lrc.flags = 0;

    if (gpio->source) {
        dispatch_release(gpio->source);
        gpio->source = NULL;
    }

    switch (direction) {
    case SWIFT_GPIO_DIRECTION_OUT:
        lrc.request_type = GPIOD_LINE_REQUEST_DIRECTION_OUTPUT;
        break;
    case SWIFT_GPIO_DIRECTION_IN:
        lrc.request_type = GPIOD_LINE_REQUEST_DIRECTION_INPUT;
        break;
    default:
        return -EINVAL;
    }

    err = swifthal_gpio__io_mode_flags(io_mode, &lrc.flags);
    if (err)
        return err;

    if (gpiod_line_request(gpio->line, &lrc, 0) < 0)
        return -errno;

    gpio->direction = direction;
    gpio->io_mode = io_mode;

    return 0;
#else
    return -ENOSYS;
#endif
}

int swifthal_gpio_set(void *arg, int level) {
    const struct swifthal_gpio *gpio = arg;

    if (gpio == NULL)
        return -EINVAL;

#ifdef __linux__
    if (gpiod_line_set_value(gpio->line, level) < 0)
        return -errno;
    return 0;
#else
    return -ENOSYS;
#endif
}

int swifthal_gpio_get(void *arg) {
    const struct swifthal_gpio *gpio = arg;
    int value;

    if (gpio == NULL)
        return -EINVAL;

#ifdef __linux__
    value = gpiod_line_get_value(gpio->line);
    if (value < 0)
        return -errno;

    return value;
#else
    return -ENOSYS;
#endif
}

int swifthal_gpio_interrupt_config(void *arg, swift_gpio_int_mode_t int_mode) {
#ifdef __linux__
    int err;
    struct swifthal_gpio *gpio = (struct swifthal_gpio *)arg;
    struct gpiod_line_request_config lrc;
    int fd;

    if (gpio == NULL)
        return -EINVAL;

    lrc.consumer = SWIFTHAL_GPIO_CONSUMER;
    lrc.flags = 0;

    switch (int_mode) {
    case SWIFT_GPIO_INT_MODE_RISING_EDGE:
        lrc.request_type = GPIOD_LINE_REQUEST_EVENT_RISING_EDGE;
        break;
    case SWIFT_GPIO_INT_MODE_FALLING_EDGE:
        lrc.request_type = GPIOD_LINE_REQUEST_EVENT_FALLING_EDGE;
        break;
    case SWIFT_GPIO_INT_MODE_BOTH_EDGE:
        lrc.request_type = GPIOD_LINE_REQUEST_EVENT_BOTH_EDGES;
        break;
    case SWIFT_GPIO_INT_MODE_HIGH_LEVEL:
    case SWIFT_GPIO_INT_MODE_LOW_LEVEL:
    default:
        return -EINVAL;
    }

    err = swifthal_gpio__io_mode_flags(gpio->io_mode, &lrc.flags);
    if (err)
        return err;

    if (gpiod_line_is_requested(gpio->line))
        gpiod_line_release(gpio->line);

    if (gpiod_line_request(gpio->line, &lrc, 0) < 0)
        return -errno;

    fd = gpiod_line_event_get_fd(gpio->line);
    if (fd < 0)
        return -errno;

    gpio->source = dispatch_source_create(
        gpio->direction == SWIFT_GPIO_DIRECTION_OUT ? DISPATCH_SOURCE_TYPE_WRITE
                                                    : DISPATCH_SOURCE_TYPE_READ,
        fd, 0, gpio->queue);
    if (gpio->source == NULL)
        return -ENOMEM;

    return 0;
#else
    return -ENOSYS;
#endif
}

static int swifthal_gpio__set_handler(void *arg, void (^handler)(void)) {
    const struct swifthal_gpio *gpio = arg;

    if (gpio == NULL || gpio->source == NULL)
        return -EINVAL;

    dispatch_source_set_event_handler(gpio->source, handler);

    return 0;
}

#if 0
int swifthal_gpio__event_read(void *arg, bool *rising_edge) {
    struct swifthal_gpio *gpio = arg;
    struct gpiod_line_event event;

    *rising_edge = false;

    if (gpio == NULL ||
        gpiod_line_direction(gpio->line) != GPIOD_LINE_DIRECTION_INPUT)
        return -EINVAL;

    if (gpiod_line_event_read(gpio->line, &event) < 0)
        return -errno;

    *rising_edge = event.event_type == GPIOD_LINE_EVENT_RISING_EDGE;

    return 0;
}
#endif

int swifthal_gpio_interrupt_callback_install(void *arg,
                                             const void *param,
                                             void (*callback)(const void *)) {
    return swifthal_gpio__set_handler(arg, ^{
#if 0
        struct gpiod_line_event event;
        int fd = dispatch_source_get_handle(gpio->source);

        memset(&event, 0, sizeof(event));

        // FIXME: should we be reading here or does the caller do it?
        if (gpiod_line_direction(gpio->line) == GPIOD_LINE_DIRECTION_INPUT &&
            gpiod_line_event_read_fd(fd, &event) < 0) {
            dispatch_source_cancel(gpio->source);
            return;
        }
#endif
      callback(param);
    });
}

int swifthal_gpio_interrupt_callback_uninstall(void *arg) {
    const struct swifthal_gpio *gpio = arg;

    if (gpio == NULL)
        return -EINVAL;

    dispatch_source_cancel(gpio->source);

    return 0;
}

int swifthal_gpio_interrupt_enable(void *arg) {
    const struct swifthal_gpio *gpio = arg;

    if (gpio == NULL)
        return -EINVAL;

    if (gpio == NULL || gpio->source == NULL)
        return -EINVAL;

    dispatch_resume(gpio->source);

    return 0;
}

int swifthal_gpio_interrupt_disable(void *arg) {
    const struct swifthal_gpio *gpio = arg;

    if (gpio == NULL || gpio->source == NULL)
        return -EINVAL;

    dispatch_suspend(gpio->source);

    return 0;
}

int swifthal_gpio_dev_number_get(void) {
#ifdef __linux__
    struct gpiod_chip *chip;
    struct gpiod_line_bulk bulk;

    chip = gpiod_chip_open_by_name(SWIFTHAL_GPIOCHIP);
    if (chip == NULL) {
        return 0;
    }

    memset(&bulk, 0, sizeof(bulk));
    gpiod_chip_get_all_lines(chip, &bulk);
    gpiod_chip_close(chip);

    return bulk.num_lines;
#else
    return 0;
#endif
}

int swifthal_gpio_get_fd(const void *arg) {
    const struct swifthal_gpio *gpio = arg;

    if (gpio == NULL)
        return -EINVAL;

#if __linux__
    return gpiod_line_event_get_fd(gpio->line);
#else
    return -ENOSYS;
#endif
}
