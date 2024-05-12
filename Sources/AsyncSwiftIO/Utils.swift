//=== Utils.swift ---------------------------------------------------------===//
//
// Copyright (c) MadMachine Limited
// Licensed under MIT License
//
// Authors: Andy Liu
// Created: 12/08/2021
//
// See https://madmachine.io for more information
//
//===----------------------------------------------------------------------===//

import struct SwiftIO.Errno
import struct SystemPackage.Errno

@inlinable
func validateLength(
  _ array: [UInt8],
  count: Int?,
  length: inout Int
) -> Result<(), SwiftIO.Errno> {
  if let count {
    if count > array.count || count < 0 {
      return .failure(Errno.invalidArgument)
    } else {
      length = count
    }
  } else {
    length = array.count
  }

  return .success(())
}

@inlinable
func validateLength(
  _ buffer: UnsafeMutableRawBufferPointer,
  count: Int?,
  length: inout Int
) -> Result<(), SwiftIO.Errno> {
  if let count {
    if count > buffer.count || count < 0 {
      return .failure(Errno.invalidArgument)
    } else {
      length = count
    }
  } else {
    length = buffer.count
  }

  return .success(())
}

@inlinable
func validateLength(
  _ buffer: UnsafeRawBufferPointer,
  count: Int?,
  length: inout Int
) -> Result<(), SwiftIO.Errno> {
  if let count {
    if count > buffer.count || count < 0 {
      return .failure(Errno.invalidArgument)
    } else {
      length = count
    }
  } else {
    length = buffer.count
  }

  return .success(())
}

@discardableResult
func rethrowingSystemErrnoAsSwiftIOErrno<T>(_ body: () throws -> T) rethrows -> T {
  do {
    return try body()
  } catch let error as SystemPackage.Errno {
    throw SwiftIO.Errno(rawValue: error.rawValue)
  }
}

@discardableResult
func rethrowingSystemErrnoAsSwiftIOErrno<T>(_ body: () async throws -> T) async rethrows -> T {
  do {
    return try await body()
  } catch let error as SystemPackage.Errno {
    throw SwiftIO.Errno(rawValue: error.rawValue)
  }
}

#if !canImport(IORing)
// no-ops just for building on Darwin for testing things that depend on this

import Foundation

typealias FileHandle = Foundation.FileHandle

protocol FileDescriptorRepresentable: Sendable {
  var fileDescriptor: CInt { get }
}

extension Foundation.FileHandle: FileDescriptorRepresentable {}

actor IORing {
  static let shared = IORing()

  func read(count: Int, from fd: FileDescriptorRepresentable) async throws -> [UInt8] {
    throw SystemPackage.Errno.noFunction
  }

  func write(
    _ data: [UInt8],
    count: Int? = nil,
    offset: Int = -1,
    to fd: FileDescriptorRepresentable
  ) async throws -> Int {
    throw SystemPackage.Errno.noFunction
  }

  func readFixed<U>(
    count: Int? = nil,
    offset: Int = -1,
    bufferIndex: UInt16,
    bufferOffset: Int = 0,
    from fd: FileDescriptorRepresentable,
    _ body: (UnsafeMutableBufferPointer<UInt8>) throws -> U
  ) async throws -> U {
    throw SystemPackage.Errno.noFunction
  }

  func writeFixed(
    _ data: [UInt8],
    count: Int? = nil,
    offset: Int = -1,
    bufferIndex: UInt16,
    bufferOffset: Int = 0,
    to fd: FileDescriptorRepresentable
  ) async throws -> Int {
    throw SystemPackage.Errno.noFunction
  }

  func writeReadFixed(
    _ data: inout [UInt8],
    count: Int? = nil,
    offset: Int = -1,
    bufferIndex: UInt16,
    bufferOffset: Int = 0,
    fd: FileDescriptorRepresentable
  ) async throws {
    throw SystemPackage.Errno.noFunction
  }

  func registerFixedBuffers(count: Int, size: Int) throws {
    throw SystemPackage.Errno.noFunction
  }
}

#endif
