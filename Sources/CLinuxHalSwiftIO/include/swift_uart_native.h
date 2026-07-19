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

// Plain prototypes for the UART termios2 helpers implemented in
// swift_uart_native.c. Deliberately does NOT include <asm/termbits.h> so it can
// be part of the module Swift imports without colliding with Glibc's
// <termios.h> (both define `struct termios`).

#pragma once

#include <inttypes.h>

int swifthal_uart__set_baud(int fd, uint32_t baud);
int swifthal_uart__set_parity(int fd, int parity); // 0 none, 1 odd, 2 even
int swifthal_uart__set_stop_bits(int fd, int two);
int swifthal_uart__set_data_bits_8(int fd);
int swifthal_uart__set_raw(int fd);
int swifthal_uart__get_config(int fd,
                                  uint32_t *baud,
                                  int *parity,
                                  int *stop2);
