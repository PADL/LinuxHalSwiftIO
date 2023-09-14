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

import CNewlib
import CSwiftIO
import SwiftIO

@inlinable
func getClassPointer<T: AnyObject>(_ obj: T) -> UnsafeRawPointer {
    UnsafeRawPointer(Unmanaged.passUnretained(obj).toOpaque())
}

func system_strerror(_ __errnum: Int32) -> UnsafeMutablePointer<Int8>! {
    strerror(__errnum)
}

@inlinable
func validateLength(
    _ array: [UInt8],
    count: Int?,
    length: inout Int
) -> Result<(), Errno> {
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
) -> Result<(), Errno> {
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
) -> Result<(), Errno> {
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
