//
// Copyright (c) 2024 PADL Software Pty Ltd
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

import CSwiftIO
import LinuxHalSwiftIO
@_spi(SwiftIOPrivate)
import SwiftIO

private extension DigitalOut {
  func withObj(_ body: (_: UnsafeMutableRawPointer) -> CInt) throws(SwiftIO.Errno) {
    let err = body(obj)
    guard err == 0 else { throw SwiftIO.Errno(err) }
  }
}

public extension DigitalOut {
  func pulse(width: Duration) async throws {
    toggle()
    try await Task.sleep(for: width)
    toggle()
  }
}
