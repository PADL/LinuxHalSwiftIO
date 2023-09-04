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

#pragma once

#include <dispatch/dispatch.h>

void swifthal_spi_read_notification_handler_set(
    void *_Nonnull arg, void (^_Nonnull handler)(_Nonnull dispatch_source_t));

void swifthal_spi_write_notification_handler_set(
    void *_Nonnull arg, void (^_Nonnull handler)(_Nonnull dispatch_source_t));
