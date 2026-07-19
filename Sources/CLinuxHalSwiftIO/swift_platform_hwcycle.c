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

// The rest of the platform HAL (sleep/wait/uptime/random) is implemented in
// native Swift (Sources/LinuxHalSwiftIO/Platform.swift). The two hardware-cycle
// functions remain in C because they require inline assembly to read the
// per-architecture cycle counter, which Swift cannot express.

#include <inttypes.h>
#include <time.h>
#include <stdatomic.h>

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
