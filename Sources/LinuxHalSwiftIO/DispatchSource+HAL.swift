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

import Dispatch

// Shared idempotent suspend/resume/teardown helpers for the dispatch sources
// backing the GPIO and timer HALs, which track suspension in an adjacent Bool.
extension DispatchSourceProtocol {
  // Resume only when suspended, so repeated enables do not over-resume.
  func resumeIfSuspended(_ suspended: inout Bool) {
    if suspended {
      resume()
      suspended = false
    }
  }

  // Suspend only when running, so repeated disables do not over-suspend.
  func suspendIfRunning(_ suspended: inout Bool) {
    if !suspended {
      suspend()
      suspended = true
    }
  }

  // Cancel and bring the suspend count back to zero: a suspended source traps
  // when its last reference is dropped.
  func cancelForRelease(_ suspended: inout Bool) {
    cancel()
    resumeIfSuspended(&suspended)
  }
}
