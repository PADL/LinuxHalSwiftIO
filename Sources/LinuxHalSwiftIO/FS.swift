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

// Native-Swift port of the filesystem HAL (previously swift_fs.c), mapping the
// HAL onto POSIX stdio / dirent / stat / statfs.

#if canImport(Glibc)
import Glibc
#elseif canImport(Darwin)
import Darwin
#endif
import CLinuxHalSwiftIO

// Glibc leaves DIR opaque, so dirent calls take an OpaquePointer; Darwin exposes
// the struct, so DIR* imports as UnsafeMutablePointer<DIR>. Bridge the raw handle
// to whichever the platform's readdir/dirfd/closedir expect.
#if canImport(Darwin)
typealias DIRPointer = UnsafeMutablePointer<DIR>
private func dirPointer(_ dp: UnsafeMutableRawPointer) -> DIRPointer {
  dp.assumingMemoryBound(to: DIR.self)
}
#else
typealias DIRPointer = OpaquePointer
private func dirPointer(_ dp: UnsafeMutableRawPointer) -> DIRPointer {
  OpaquePointer(dp)
}
#endif

// swifthal_mount_point_get() stays in C (swift_fs_native.c): it must return a
// permanent C string, and a string literal there is infallible — unlike a
// Swift String (no stable char* without a scoped withCString) or strdup (can
// fail with nil).

@c
func swifthal_fs_open(
  _ fp: UnsafeMutablePointer<UnsafeMutableRawPointer?>?,
  _ path: UnsafePointer<CChar>?,
  _ flags: UInt8
) -> CInt {
  fp?.pointee = nil

  let f = Int32(flags)
  let modeBits = f & SWIFT_FS_O_MODE_MASK
  let flagBits = f & SWIFT_FS_O_FLAGS_MASK
  let mode: String

  if modeBits == SWIFT_FS_O_READ, flagBits == 0 {
    mode = "r"
  } else if modeBits == SWIFT_FS_O_WRITE, flagBits == SWIFT_FS_O_CREATE {
    mode = "w"
  } else if modeBits == SWIFT_FS_O_WRITE, flagBits == (SWIFT_FS_O_CREATE | SWIFT_FS_O_APPEND) {
    mode = "a"
  } else if modeBits == SWIFT_FS_O_RDWR, flagBits == 0 {
    mode = "r+"
  } else if modeBits == SWIFT_FS_O_RDWR, flagBits == SWIFT_FS_O_CREATE {
    mode = "w+"
  } else if modeBits == SWIFT_FS_O_READ, flagBits == (SWIFT_FS_O_CREATE | SWIFT_FS_O_APPEND) {
    mode = "a+"
  } else {
    return -EINVAL
  }

  guard let handle = fopen(path, mode) else { return -errno }
  fp?.pointee = UnsafeMutableRawPointer(handle)
  return 0
}

@c
func swifthal_fs_close(_ fp: UnsafeMutableRawPointer?) -> CInt {
  guard let fp else { return -EINVAL }
  if fclose(fp.assumingMemoryBound(to: FILE.self)) != 0 { return -errno }
  return 0
}

@c
func swifthal_fs_remove(_ path: UnsafePointer<CChar>?) -> CInt {
  guard let path else { return -EINVAL }
  if unlink(path) != 0 { return -errno }
  return 0
}

@c
func swifthal_fs_rename(_ from: UnsafePointer<CChar>?, _ to: UnsafeMutablePointer<CChar>?) -> CInt {
  guard let from, let to else { return -EINVAL }
  if rename(from, to) != 0 { return -errno }
  return 0
}

@c
func swifthal_fs_write(
  _ fp: UnsafeMutableRawPointer?,
  _ buf: UnsafeRawPointer?,
  _ size: Int
) -> CInt {
  if size < 0 { return -EINVAL }
  if size == 0 { return 0 } // a zero-byte write is not an error
  guard let fp else { return -EINVAL }
  let file = fp.assumingMemoryBound(to: FILE.self)

  let nbytes = fwrite(buf, 1, size, file)
  if nbytes == 0 {
    if ferror(file) != 0 { return -errno }
    return -EIO
  }
  return CInt(truncatingIfNeeded: nbytes)
}

@c
func swifthal_fs_read(
  _ fp: UnsafeMutableRawPointer?,
  _ buf: UnsafeMutableRawPointer?,
  _ size: Int
) -> CInt {
  if size < 0 { return -EINVAL }
  if size == 0 { return 0 } // a zero-byte read is not an error
  guard let fp else { return -EINVAL }
  let file = fp.assumingMemoryBound(to: FILE.self)

  let nbytes = fread(buf, 1, size, file)
  if nbytes == 0 {
    if ferror(file) != 0 { return -errno }
    if feof(file) != 0 { return 0 }
    return -EIO
  }
  return CInt(truncatingIfNeeded: nbytes)
}

@c
func swifthal_fs_seek(_ fp: UnsafeMutableRawPointer?, _ offset: Int, _ whence: CInt) -> CInt {
  guard let fp else { return -EINVAL }
  let file = fp.assumingMemoryBound(to: FILE.self)

  var fwhence: Int32 = 0
  switch whence {
  case SWIFT_FS_SEEK_SET: fwhence = Int32(SEEK_SET)
  case SWIFT_FS_SEEK_CUR: fwhence = Int32(SEEK_CUR)
  case SWIFT_FS_SEEK_END: fwhence = Int32(SEEK_END)
  default: break
  }

  // fseeko/ftello use off_t so the seek itself is correct for >2GiB offsets.
  if fseeko(file, off_t(offset), fwhence) != 0 { return -errno }
  return 0
}

@c
func swifthal_fs_tell(_ fp: UnsafeMutableRawPointer?) -> CInt {
  guard let fp else { return -EINVAL }
  let offset = ftello(fp.assumingMemoryBound(to: FILE.self))
  if offset == -1 { return -errno }
  return CInt(truncatingIfNeeded: offset)
}

@c
func swifthal_fs_truncate(_ fp: UnsafeMutableRawPointer?, _ length: Int) -> CInt {
  guard let fp else { return -EINVAL }
  if ftruncate(fileno(fp.assumingMemoryBound(to: FILE.self)), off_t(length)) < 0 { return -errno }
  return 0
}

@c
func swifthal_fs_sync(_ fp: UnsafeMutableRawPointer?) -> CInt {
  guard let fp else { return -EINVAL }
  if fsync(fileno(fp.assumingMemoryBound(to: FILE.self))) < 0 { return -errno }
  return 0
}

@c
func swifthal_fs_mkdir(_ path: UnsafePointer<CChar>?) -> CInt {
  guard let path else { return -EINVAL }
  if mkdir(path, 0o777) < 0 { return -errno }
  return 0
}

@c
func swifthal_fs_opendir(
  _ dp: UnsafeMutablePointer<UnsafeMutableRawPointer?>?,
  _ path: UnsafePointer<CChar>?
) -> CInt {
  guard let path else { return -EINVAL }
  guard let handle = opendir(path) else {
    dp?.pointee = nil
    return -errno
  }
  dp?.pointee = UnsafeMutableRawPointer(handle)
  return 0
}

/// Copy a NUL-terminated C name into the `char[256]` dirent name field,
/// truncating like strncpy(dst, src, 255) with an explicit NUL terminator.
private func setDirentName(
  _ entry: UnsafeMutablePointer<swift_fs_dirent_t>,
  _ name: UnsafePointer<CChar>
) {
  withUnsafeMutablePointer(to: &entry.pointee.name) {
    $0.withMemoryRebound(to: CChar.self, capacity: 256) { dst in
      _ = strncpy(dst, name, 255)
      dst[255] = 0
    }
  }
}

/// Fill entry type/size from a stat result; false for types the HAL does not
/// surface (neither a regular file nor a directory).
private func setDirentTypeAndSize(
  _ entry: UnsafeMutablePointer<swift_fs_dirent_t>,
  _ sb: stat
) -> Bool {
  switch sb.st_mode & S_IFMT {
  case S_IFDIR:
    entry.pointee.type = SWIFT_FS_DIR_ENTRY_DIR
    entry.pointee.size = 0
  case S_IFREG:
    entry.pointee.type = SWIFT_FS_DIR_ENTRY_FILE
    entry.pointee.size = Int(sb.st_size)
  default:
    return false
  }
  return true
}

/// Fill `entry` from one dirent: returns 0, a negative errno, or nil to skip.
/// d_name stays raw bytes: a String round-trip would mangle non-UTF-8 names.
private func fillDirent(
  _ dir: DIRPointer,
  _ dentry: UnsafeMutablePointer<dirent>,
  _ entry: UnsafeMutablePointer<swift_fs_dirent_t>
) -> CInt? {
  withUnsafePointer(to: &dentry.pointee.d_name) {
    $0.withMemoryRebound(
      to: CChar.self,
      capacity: MemoryLayout.size(ofValue: dentry.pointee.d_name)
    ) { name -> CInt? in
      let dType = dentry.pointee.d_type

      if dType == UInt8(DT_DIR) {
        // No stat needed: a directory entry's size is reported as 0.
        entry.pointee.type = SWIFT_FS_DIR_ENTRY_DIR
        entry.pointee.size = 0
      } else if dType == UInt8(DT_REG) || dType == DT_UNKNOWN {
        // DT_REG needs a stat for the size, and DT_UNKNOWN (filesystems that
        // never fill d_type) for classification too.
        var sb = stat()
        if fstatat(dirfd(dir), name, &sb, 0) < 0 {
          // Skip entries lost to an unlink race (or dangling symlinks); surface
          // any other failure rather than silently omitting entries.
          return errno == ENOENT ? nil : -errno
        }
        if !setDirentTypeAndSize(entry, sb) { return nil }
      } else {
        return nil // other types (symlink, socket, ...): skip
      }

      setDirentName(entry, name)
      return 0
    }
  }
}

@c
func swifthal_fs_readdir(
  _ dp: UnsafeMutableRawPointer?,
  _ entry: UnsafeMutablePointer<swift_fs_dirent_t>?
) -> CInt {
  guard let dp, let entry else { return -EINVAL }
  let dir = dirPointer(dp)

  while true {
    // readdir() returns NULL both at end-of-directory and on error; per POSIX,
    // errno must be cleared first to tell them apart.
    errno = 0
    guard let dentry = readdir(dir) else {
      if errno != 0 { return -errno }
      entry.pointee.name.0 = 0
      return 0
    }

    if let rc = fillDirent(dir, dentry, entry) { return rc }
  }
}

@c
func swifthal_fs_closedir(_ dp: UnsafeMutableRawPointer?) -> CInt {
  guard let dp else { return -EINVAL }
  if closedir(dirPointer(dp)) < 0 { return -errno }
  return 0
}

@c
func swifthal_fs_stat(
  _ path: UnsafePointer<CChar>?,
  _ entry: UnsafeMutablePointer<swift_fs_dirent_t>?
) -> CInt {
  guard let path, let entry else { return -EINVAL }
  var sb = stat()
  if stat(path, &sb) < 0 { return -errno }
  if !setDirentTypeAndSize(entry, sb) { return -ENOENT }

  // The name is not derivable from a path; make it a defined empty string.
  entry.pointee.name.0 = 0
  return 0
}

@c
func swifthal_fs_statfs(
  _ path: UnsafePointer<CChar>?,
  _ stat: UnsafeMutablePointer<swift_fs_statvfs_t>?
) -> CInt {
  guard let path, let stat else { return -EINVAL }
  var buf = statfs()
  if statfs(path, &buf) < 0 { return -errno }

  stat.pointee = swift_fs_statvfs_t()
  #if os(Linux)
  stat.pointee.f_bsize = UInt(bitPattern: buf.f_bsize)
  stat.pointee.f_frsize = UInt(bitPattern: buf.f_frsize)
  #else
  // Darwin's struct statfs has no f_frsize; leave it zero as the old C did.
  stat.pointee.f_bsize = UInt(buf.f_bsize)
  #endif
  stat.pointee.f_blocks = UInt(buf.f_blocks)
  stat.pointee.f_bfree = UInt(buf.f_bfree)
  return 0
}
