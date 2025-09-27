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

#include <stdlib.h>
#include <stdio.h>
#include <unistd.h>
#include <errno.h>
#include <fcntl.h>
#include <string.h>
#include <limits.h>
#include <inttypes.h>
#include <dirent.h>
#include <sys/stat.h>
#ifdef __linux__
#include <sys/vfs.h>
#elif defined(__APPLE__)
#include <sys/mount.h>
#endif

#include "swift_hal_internal.h"

char *swifthal_mount_point_get(void) { return "/"; }

int swifthal_fs_open(void **fp, const char *path, uint8_t flags) {
  int oflags = 0;
  const char *mode;

  *fp = NULL;

  if ((flags & SWIFT_FS_O_MODE_MASK) == SWIFT_FS_O_READ &&
      (flags & SWIFT_FS_O_FLAGS_MASK) == 0) {
    mode = "r";
  } else if ((flags & SWIFT_FS_O_MODE_MASK) == SWIFT_FS_O_WRITE &&
             (flags & SWIFT_FS_O_FLAGS_MASK) == SWIFT_FS_O_CREATE) {
    mode = "w";
  } else if ((flags & SWIFT_FS_O_MODE_MASK) == SWIFT_FS_O_WRITE &&
             (flags & SWIFT_FS_O_FLAGS_MASK) ==
                 (SWIFT_FS_O_CREATE | SWIFT_FS_O_APPEND)) {
    mode = "a";
  } else if ((flags & SWIFT_FS_O_MODE_MASK) == SWIFT_FS_O_RDWR &&
             (flags & SWIFT_FS_O_FLAGS_MASK) == 0) {
    mode = "r+";
  } else if ((flags & SWIFT_FS_O_MODE_MASK) == SWIFT_FS_O_RDWR &&
             (flags & SWIFT_FS_O_FLAGS_MASK) == SWIFT_FS_O_CREATE) {
    mode = "w+";
  } else if ((flags & SWIFT_FS_O_MODE_MASK) == SWIFT_FS_O_READ &&
             (flags & SWIFT_FS_O_FLAGS_MASK) ==
                 (SWIFT_FS_O_CREATE | SWIFT_FS_O_APPEND)) {
    mode = "a+";
  }

  *fp = fopen(path, mode);
  if (*fp == NULL)
    return -errno;

  return 0;
}

int swifthal_fs_close(void *fp) {
  if (fclose(fp) != 0)
    return -errno;
  return 0;
}

int swifthal_fs_remove(const char *path) {
  if (unlink(path) != 0)
    return -errno;
  return 0;
}

int swifthal_fs_rename(const char *from, char *to) {
  if (rename(from, to) != 0)
    return -errno;
  return 0;
}

int swifthal_fs_write(void *fp, const void *buf, ssize_t size) {
  ssize_t nbytes;

  nbytes = fwrite(buf, size, 1, fp);
  if (nbytes < 0)
    return -errno;

  return (int)nbytes;
}

int swifthal_fs_read(void *fp, void *buf, ssize_t size) {
  ssize_t nbytes;

  nbytes = fread(buf, size, 1, fp);
  if (nbytes < 0)
    return -errno;

  return (int)nbytes;
}

int swifthal_fs_seek(void *fp, ssize_t offset, int whence) {
  int fwhence = 0;

  switch (whence) {
  case SWIFT_FS_SEEK_SET:
    fwhence = SEEK_SET;
    break;
  case SWIFT_FS_SEEK_CUR:
    fwhence = SEEK_CUR;
    break;
  case SWIFT_FS_SEEK_END:
    fwhence = SEEK_END;
    break;
  }

  if (fseek(fp, offset, fwhence) != 0)
    return -errno;
  return 0;
}

int swifthal_fs_tell(void *fp) {
  long offset = ftell(fp);
  if (offset == -1)
    return -errno;
  return (int)offset;
}

int swifthal_fs_truncate(void *fp, ssize_t length) {
  if (ftruncate(fileno(fp), length) < 0)
    return -errno;
  return 0;
}

int swifthal_fs_sync(void *fp) {
  if (fsync(fileno(fp)) < 0)
    return -errno;
  return 0;
}

int swifthal_fs_mkdir(const char *path) {
  if (mkdir(path, 0777) < 0)
    return -errno;
  return 0;
}

int swifthal_fs_opendir(void **dp, const char *path) {
  *dp = opendir(path);
  if (*dp == NULL)
    return -errno;
  return 0;
}

int swifthal_fs_readdir(void *dp, swift_fs_dirent_t *entry) {
  struct dirent *dentry;

next:
  dentry = readdir(dp);
  if (dentry == NULL) {
    if (errno != 0)
      return -errno;
    else {
      entry->name[0] = '\0';
      return 0;
    }
  }

  if (dentry->d_type == DT_DIR) {
    entry->type = SWIFT_FS_DIR_ENTRY_DIR;
    memcpy(entry->name, dentry->d_name, 256);
    entry->size = 0;
  } else if (dentry->d_type == DT_REG) {
    struct stat statbuf;

    entry->type = SWIFT_FS_DIR_ENTRY_FILE;
    memcpy(entry->name, dentry->d_name, 256);
    if (fstatat(dirfd(dp), dentry->d_name, &statbuf, 0) < 0)
      return -errno;
    entry->size = (unsigned int)statbuf.st_size;
  } else
    goto next;

  return 0;
}

int swifthal_fs_closedir(void *dp) {
  if (closedir(dp) < 0)
    return -errno;
  return 0;
}

int swifthal_fs_stat(const char *path, swift_fs_dirent_t *entry) {
  struct stat statbuf;

  if (stat(path, &statbuf) < 0)
    return -errno;

  switch (statbuf.st_mode) {
  case S_IFDIR:
    entry->type = SWIFT_FS_DIR_ENTRY_DIR;
  case S_IFREG:
    entry->type = SWIFT_FS_DIR_ENTRY_FILE;
  default:
    return -ENOENT;
  }

  return 0;
}

int swifthal_fs_statfs(const char *path, swift_fs_statvfs_t *stat) {
  struct statfs statfsbuf;

  if (statfs(path, &statfsbuf) < 0)
    return -errno;

  memset(stat, 0, sizeof(*stat));
  stat->f_bsize = statfsbuf.f_bsize;
#ifdef __linux__
  stat->f_frsize = statfsbuf.f_frsize;
#endif
  stat->f_blocks = statfsbuf.f_blocks;
  stat->f_bfree = statfsbuf.f_bfree;

  return 0;
}
