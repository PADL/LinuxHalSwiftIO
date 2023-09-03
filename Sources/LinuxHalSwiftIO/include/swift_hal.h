#pragma once

#include <swift_adc.h>
#include <swift_counter.h>
#include <swift_eth.h>
#include <swift_fs.h>
#include <swift_gpio.h>
#include <swift_i2c.h>
#include <swift_i2s.h>
#include <swift_lcd.h>
#include <swift_os.h>
#include <swift_platform.h>
#include <swift_pwm.h>
#include <swift_spi.h>
#include <swift_timer.h>
#include <swift_uart.h>
#include <swift_wifi.h>

#include <dispatch/dispatch.h>

int swifthal_spi_read_source_get(void *arg, dispatch_source_t *source);
int swifthal_spi_write_source_get(void *arg, dispatch_source_t *source);

