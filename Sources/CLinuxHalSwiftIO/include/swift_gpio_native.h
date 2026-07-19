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

// Exposes libgpiod to the native-Swift GPIO implementation (GPIO.swift). The
// request-type/flag values are enum constants (not bare macros) and the structs
// import cleanly, so no wrappers are needed; Swift calls gpiod directly.

#pragma once

#ifdef __linux__
#include <gpiod.h>
#endif

// The libgpiod consumer label, as a permanent C string literal (infallible,
// unlike a Swift String or strdup()).
static inline const char *swifthal_gpio__consumer(void) { return "SwiftIO"; }
