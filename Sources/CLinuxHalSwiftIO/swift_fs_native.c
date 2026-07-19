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

// The filesystem HAL is implemented in Swift (FS.swift); this one entry stays
// in C because it must return a permanent C string. A string literal here is
// infallible, whereas a Swift String has no stable char* and strdup() can fail.

char *swifthal_mount_point_get(void) { return "/"; }
