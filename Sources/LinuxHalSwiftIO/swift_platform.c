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
#include <inttypes.h>
#include <sys/random.h>
#ifdef __linux__
#include <sys/sysinfo.h>
#endif

#include "swift_hal.h"

void swifthal_ms_sleep(int ms) { usleep(ms * 1000); }

void swifthal_us_wait(unsigned int us) { usleep(us); }

long long swifthal_uptime_get(void) {
#ifdef __linux__
    struct sysinfo info;
    if (sysinfo(&info) < 0)
        return -errno;

    return info.uptime * 1000;
#else
    return 0;
#endif
}

unsigned int swifthal_hwcycle_get(void) {
#if __x86_64__
    unsigned a, d;
    asm volatile("rdtsc" : "=a"(a), "=d"(d));
    return ((unsigned long)a) | (((unsigned long)d) << 32);
#elif defined(__ARM_ARCH_ISA_A64)
    uint64_t val;
    asm volatile("mrs %0, cntvct_el0" : "=r"(val));
    return (unsigned int)val;
#else
#error implement swifthal_hwcycle_get() for your platform
#endif
}

unsigned int swifthal_hwcycle_to_ns(unsigned int cycles) {
    return (unsigned int)sysconf(_SC_CLK_TCK);
}

void swiftHal_randomGet(unsigned char *buf, int length) {
#if defined(__linux__)
    getrandom(buf, length, 0);
#elif defined(__APPLE__)
    arc4random_buf(buf, length);
#else
#error define swiftHal_randomGet for your platform
#endif
}
