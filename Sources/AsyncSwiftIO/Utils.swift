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

func getObj(_ self: AnyObject) -> UnsafeMutableRawPointer? {
    let mirror = Mirror(reflecting: self)
    var obj: UnsafeMutableRawPointer?

    for case let (label?, value) in mirror.children {
        if label == "obj" {
            obj = value as? UnsafeMutableRawPointer
            break
        }
    }

    return obj
}

@inlinable
func validateLength(
    _ array: [UInt8],
    count: Int?,
    length: inout Int
) -> Result<(), SwiftIO.Errno> {
    if let count = count {
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
    if let count = count {
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
    if let count = count {
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
