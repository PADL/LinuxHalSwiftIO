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
#include <fcntl.h>
#include <errno.h>
#include <inttypes.h>
#include <time.h>
#include <stdatomic.h>
#include <sys/random.h>
#ifdef __linux__
#include <sys/sysinfo.h>
#endif

#include "swift_hal_internal.h"

void swifthal_ms_sleep(ssize_t ms) {
  struct timespec ts, rem;

  if (ms <= 0)
    return;

  // nanosleep avoids usleep's useconds_t (32-bit) truncation for large delays
  // and correctly handles interruption by a signal.
  ts.tv_sec = ms / 1000;
  ts.tv_nsec = (ms % 1000) * 1000000L;

  while (nanosleep(&ts, &rem) < 0 && errno == EINTR)
    ts = rem;
}

void swifthal_us_wait(uint32_t us) { usleep(us); }

int64_t swifthal_uptime_get(void) {
#ifdef __linux__
  struct sysinfo info;
  if (sysinfo(&info) < 0)
    return -errno;

  return (int64_t)info.uptime * 1000;
#else
  return 0;
#endif
}

uint32_t swifthal_hwcycle_get(void) {
#if __x86_64__
  unsigned a, d;
  asm volatile("rdtsc" : "=a"(a), "=d"(d));
  return a;
#elif defined(__aarch64__)
  uint64_t val;
  asm volatile("mrs %0, cntvct_el0" : "=r"(val));
  return (uint32_t)val;
#elif defined(__arm__)
  uint64_t val;
  asm volatile("mrrc p15, 1, %Q0, %R0, c14" : "=r" (val));
  return (uint32_t)val;
#else
#error implement swifthal_hwcycle_get() for your platform
#endif
}

uint32_t swifthal_hwcycle_to_ns(unsigned int cycles) {
  // swifthal_hwcycle_get() reads a raw hardware counter, so the conversion
  // must divide by the counter's frequency (NOT clock_getres(), which returns
  // the software clock's 1ns resolution and left this a no-op multiply).
#if defined(__aarch64__)
  uint64_t freq;
  asm volatile("mrs %0, cntfrq_el0" : "=r"(freq));
  if (freq == 0)
    return 0;
  return (uint32_t)((uint64_t)cycles * 1000000000ULL / freq);
#elif defined(__arm__)
  uint32_t freq;
  asm volatile("mrc p15, 0, %0, c14, c0, 0" : "=r"(freq)); // CNTFRQ
  if (freq == 0)
    return 0;
  return (uint32_t)((uint64_t)cycles * 1000000000ULL / freq);
#elif defined(__x86_64__)
  // The TSC frequency is not architecturally discoverable; calibrate it once
  // against CLOCK_MONOTONIC and cache the result.
  static _Atomic(uint64_t) tsc_hz = 0;
  uint64_t hz = atomic_load_explicit(&tsc_hz, memory_order_relaxed);

  if (hz == 0) {
    struct timespec cal = {.tv_sec = 0, .tv_nsec = 10 * 1000 * 1000}; // 10ms
    struct timespec t0, t1;
    unsigned a, d;
    uint64_t c0, c1, elapsed_ns;

    clock_gettime(CLOCK_MONOTONIC, &t0);
    asm volatile("rdtsc" : "=a"(a), "=d"(d));
    c0 = ((uint64_t)d << 32) | a;
    nanosleep(&cal, NULL);
    asm volatile("rdtsc" : "=a"(a), "=d"(d));
    c1 = ((uint64_t)d << 32) | a;
    clock_gettime(CLOCK_MONOTONIC, &t1);

    elapsed_ns = (uint64_t)(t1.tv_sec - t0.tv_sec) * 1000000000ULL +
                 (uint64_t)(t1.tv_nsec - t0.tv_nsec);
    if (elapsed_ns == 0)
      return 0;
    hz = (c1 - c0) * 1000000000ULL / elapsed_ns;
    if (hz == 0)
      return 0;
    atomic_store_explicit(&tsc_hz, hz, memory_order_relaxed);
  }

  return (uint32_t)((uint64_t)cycles * 1000000000ULL / hz);
#else
#error implement swifthal_hwcycle_to_ns() for your platform
#endif
}

#if defined(__linux__)
static int swifthal__urandom_fill(uint8_t *buf, ssize_t length) {
  ssize_t total = 0;
  int fd = open("/dev/urandom", O_RDONLY | O_CLOEXEC);

  if (fd < 0)
    return -1;

  while (total < length) {
    ssize_t n = read(fd, buf + total, (size_t)(length - total));
    if (n < 0) {
      if (errno == EINTR)
        continue;
      break;
    }
    if (n == 0)
      break;
    total += n;
  }

  close(fd);
  return total == length ? 0 : -1;
}
#endif

void swiftHal_randomGet(uint8_t *buf, ssize_t length) {
#if defined(__linux__)
  ssize_t total = 0;

  if (length < 0)
    return;

  // getrandom() may return short or fail with EINTR before the entropy pool is
  // initialized; ignoring that leaves the buffer partially/fully uninitialized
  // while callers treat it as random (key/nonce) material. Fill completely.
  while (total < length) {
    ssize_t n = getrandom(buf + total, (size_t)(length - total), 0);
    if (n < 0) {
      if (errno == EINTR)
        continue;
      // getrandom() may be unavailable (pre-3.17 kernel, or blocked by a
      // seccomp policy, returning ENOSYS/EFAULT). Fall back to /dev/urandom
      // rather than crashing the process or handing back non-random bytes.
      if (swifthal__urandom_fill(buf + total, length - total) == 0)
        return;
      abort(); // no entropy source available: fail closed
    }
    total += n;
  }
#elif defined(__APPLE__)
  arc4random_buf(buf, length);
#else
#error define swiftHal_randomGet for your platform
#endif
}
