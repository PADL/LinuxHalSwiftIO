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

// Native-Swift reimplementation of the OS-primitives HAL (previously
// swift_os.c): threads, POSIX message queues, mutexes and counting semaphores.

#if canImport(Glibc)
import Glibc
#elseif canImport(Darwin)
import Darwin
#endif
import CLinuxHalSwiftIO
import Synchronization

@c
func swifthal_os_task_yield() {
  _ = sched_yield()
}

private typealias TaskFn = @convention(c) (
  UnsafeMutableRawPointer?, UnsafeMutableRawPointer?, UnsafeMutableRawPointer?
) -> ()

private struct TaskParam {
  var fn: TaskFn
  var p1: UnsafeMutableRawPointer?
  var p2: UnsafeMutableRawPointer?
  var p3: UnsafeMutableRawPointer?
}

private func taskMain(_ arg: UnsafeMutableRawPointer) -> UnsafeMutableRawPointer? {
  let param = arg.assumingMemoryBound(to: TaskParam.self)
  let p = param.pointee
  p.fn(p.p1, p.p2, p.p3)
  param.deinitialize(count: 1)
  param.deallocate()
  return nil
}

// pthread_create's start routine takes a nullable argument on Linux but a
// non-nullable one on Darwin.
#if os(Linux)
private func taskStart(_ arg: UnsafeMutableRawPointer?) -> UnsafeMutableRawPointer? {
  guard let arg else { return nil }
  return taskMain(arg)
}
#else
private func taskStart(_ arg: UnsafeMutableRawPointer) -> UnsafeMutableRawPointer? {
  taskMain(arg)
}
#endif

@c
func swifthal_os_task_create(
  _ name: UnsafeMutablePointer<CChar>?,
  _ fn: swifthal_task?,
  _ p1: UnsafeMutableRawPointer?,
  _ p2: UnsafeMutableRawPointer?,
  _ p3: UnsafeMutableRawPointer?,
  _ prio: CInt,
  _ stackSize: CInt
) -> UnsafeMutableRawPointer? {
  guard let fn else { return nil }

  let param = UnsafeMutablePointer<TaskParam>.allocate(capacity: 1)
  param.initialize(to: TaskParam(fn: fn, p1: p1, p2: p2, p3: p3))

  var attr = pthread_attr_t()
  var err = pthread_attr_init(&attr)
  if err == 0 { err = pthread_attr_setdetachstate(&attr, CInt(PTHREAD_CREATE_DETACHED)) }
  var sched = sched_param()
  if err == 0 { err = pthread_attr_getschedparam(&attr, &sched) }
  if err == 0 {
    sched.sched_priority = prio
    err = pthread_attr_setschedparam(&attr, &sched)
  }
  if err == 0 { err = pthread_attr_setstacksize(&attr, Int(stackSize)) }

  #if os(Linux)
  var thread = pthread_t()
  #else
  var thread: pthread_t?
  #endif
  if err == 0 { err = pthread_create(&thread, &attr, taskStart, param) }

  pthread_attr_destroy(&attr)

  if err != 0 {
    param.deinitialize(count: 1)
    param.deallocate()
    return nil
  }

  // The opaque handle is the pthread_t itself: an integer on Linux, an opaque
  // pointer on Darwin.
  #if os(Linux)
  return UnsafeMutableRawPointer(bitPattern: UInt(thread))
  #else
  return thread.map { UnsafeMutableRawPointer($0) }
  #endif
}

#if os(Linux)
private func timeoutToTimespec(_ timeout: CInt) -> timespec {
  var ts = timespec()
  clock_gettime(CLOCK_REALTIME, &ts)
  ts.tv_sec += Int(timeout) / 1000
  ts.tv_nsec += (Int(timeout) % 1000) * 1_000_000
  if ts.tv_nsec >= 1_000_000_000 {
    ts.tv_sec += ts.tv_nsec / 1_000_000_000
    ts.tv_nsec %= 1_000_000_000
  }
  return ts
}

private struct MQueue {
  var mq: mqd_t
  var size: Int
  var name: String
}

private let mqID = Atomic<UInt>(0)
#endif

@c
func swifthal_os_mq_create(_ mqSize: Int, _ mqNum: Int) -> UnsafeRawPointer? {
  #if os(Linux)
  var attr = mq_attr()
  attr.mq_maxmsg = mqNum
  attr.mq_msgsize = mqSize

  let id = mqID.wrappingAdd(1, ordering: .relaxed).oldValue
  let name = "/LinuxHalSwiftIO.\(getpid()).\(id)"

  let mqd = name.withCString {
    swifthal_os__mq_open($0, O_RDWR | O_CREAT, 0o600, &attr)
  }
  if mqd == -1 { return nil }

  let p = UnsafeMutablePointer<MQueue>.allocate(capacity: 1)
  p.initialize(to: MQueue(mq: mqd, size: mqSize, name: name))
  return UnsafeRawPointer(p)
  #else
  return nil
  #endif
}

@c
func swifthal_os_mq_destroy(_ mp: UnsafeRawPointer?) -> CInt {
  #if os(Linux)
  guard let mp else { return -EINVAL }
  let p = UnsafeMutableRawPointer(mutating: mp).assumingMemoryBound(to: MQueue.self)

  // Attempt both operations and always free: short-circuiting on the first
  // failure would leak the descriptor, the heap struct, and/or leave the named
  // queue behind in /dev/mqueue.
  var err: CInt = 0
  if mq_close(p.pointee.mq) != 0 { err = -errno }
  if p.pointee.name.withCString({ mq_unlink($0) }) != 0, err == 0 { err = -errno }
  p.deinitialize(count: 1)
  p.deallocate()
  return err
  #else
  return -ENOSYS
  #endif
}

@c
func swifthal_os_mq_send(
  _ mp: UnsafeRawPointer?,
  _ data: UnsafeRawPointer?,
  _ timeout: CInt
) -> CInt {
  #if os(Linux)
  guard let mp, let data else { return -EINVAL }
  let p = mp.assumingMemoryBound(to: MQueue.self)
  let msg = data.assumingMemoryBound(to: CChar.self)

  if timeout == -1 {
    if mq_send(p.pointee.mq, msg, p.pointee.size, 0) != 0 { return -errno }
  } else {
    var ts = timeoutToTimespec(timeout)
    if mq_timedsend(p.pointee.mq, msg, p.pointee.size, 0, &ts) != 0 { return -errno }
  }
  return 0
  #else
  return -ENOSYS
  #endif
}

@c
func swifthal_os_mq_recv(
  _ mp: UnsafeRawPointer?,
  _ data: UnsafeMutableRawPointer?,
  _ timeout: CInt
) -> CInt {
  #if os(Linux)
  guard let mp, let data else { return -EINVAL }
  let p = mp.assumingMemoryBound(to: MQueue.self)
  let buf = data.assumingMemoryBound(to: CChar.self)
  var prio: UInt32 = 0

  // NOTE: the original C (swift_os.c) tested `!= 0` here, but mq_receive returns
  // the number of bytes received on success (non-zero for any real message), so
  // it returned -errno on every successful receive. Corrected to `< 0`.
  if timeout == -1 {
    if mq_receive(p.pointee.mq, buf, p.pointee.size, &prio) < 0 { return -errno }
  } else {
    var ts = timeoutToTimespec(timeout)
    if mq_timedreceive(p.pointee.mq, buf, p.pointee.size, &prio, &ts) < 0 { return -errno }
  }
  return 0
  #else
  return -ENOSYS
  #endif
}

@c
func swifthal_os_mq_purge(_ mp: UnsafeRawPointer?) -> CInt {
  #if os(Linux)
  guard let mp else { return -EINVAL }
  let p = mp.assumingMemoryBound(to: MQueue.self)
  var prio: UInt32 = 0

  // Drain with a non-blocking receive (absolute deadline in the past) until the
  // queue reports empty. Trusting mq_curmsgs and then blocking in mq_receive
  // would hang if another consumer drained the queue in between, and a
  // caller-controlled alloca(mq_size) risks a stack overflow.
  let data = UnsafeMutableRawPointer.allocate(byteCount: max(p.pointee.size, 1), alignment: 1)
  defer { data.deallocate() }

  while true {
    var ts = timespec(tv_sec: 0, tv_nsec: 0)
    if mq_timedreceive(
      p.pointee.mq,
      data.assumingMemoryBound(to: CChar.self),
      p.pointee.size,
      &prio,
      &ts
    ) < 0 {
      if errno == ETIMEDOUT || errno == EAGAIN { break } // queue empty
      return -errno
    }
  }
  return 0
  #else
  return -ENOSYS
  #endif
}

@c
func swifthal_os_mutex_create() -> UnsafeRawPointer? {
  let m = UnsafeMutablePointer<pthread_mutex_t>.allocate(capacity: 1)
  m.initialize(to: pthread_mutex_t())
  if pthread_mutex_init(m, nil) != 0 {
    m.deinitialize(count: 1)
    m.deallocate()
    return nil
  }
  return UnsafeRawPointer(m)
}

@c
func swifthal_os_mutex_destroy(_ arg: UnsafeRawPointer?) -> CInt {
  guard let arg else { return -EINVAL }
  let m = UnsafeMutableRawPointer(mutating: arg).assumingMemoryBound(to: pthread_mutex_t.self)
  let err = pthread_mutex_destroy(m)
  if err != 0 { return -err }
  m.deinitialize(count: 1)
  m.deallocate()
  return 0
}

@c
func swifthal_os_mutex_lock(_ arg: UnsafeRawPointer?, _ timeout: CInt) -> CInt {
  guard let arg else { return -EINVAL }
  let m = UnsafeMutableRawPointer(mutating: arg).assumingMemoryBound(to: pthread_mutex_t.self)

  if timeout == -1 {
    let err = pthread_mutex_lock(m)
    if err != 0 { return -err }
  } else {
    #if os(Linux)
    var ts = timeoutToTimespec(timeout)
    let err = pthread_mutex_timedlock(m, &ts)
    if err != 0 { return -err }
    #else
    return -ENOSYS
    #endif
  }
  return 0
}

@c
func swifthal_os_mutex_unlock(_ arg: UnsafeRawPointer?) -> CInt {
  guard let arg else { return -EINVAL }
  let m = UnsafeMutableRawPointer(mutating: arg).assumingMemoryBound(to: pthread_mutex_t.self)
  let err = pthread_mutex_unlock(m)
  if err != 0 { return -err }
  return 0
}

private struct Semaphore {
  var sem = sem_t()
  var initCnt: CInt = 0
  var limit: CInt = 0
  var giveLock = pthread_mutex_t()
}

@c
func swifthal_os_sem_create(_ initCnt: UInt32, _ limit: UInt32) -> UnsafeRawPointer? {
  guard initCnt <= UInt32(CInt.max), limit <= UInt32(CInt.max) else { return nil }

  let s = UnsafeMutablePointer<Semaphore>.allocate(capacity: 1)
  s.initialize(to: Semaphore())
  if sem_init(&s.pointee.sem, 0, initCnt) != 0 {
    s.deinitialize(count: 1)
    s.deallocate()
    return nil
  }
  if pthread_mutex_init(&s.pointee.giveLock, nil) != 0 {
    sem_destroy(&s.pointee.sem)
    s.deinitialize(count: 1)
    s.deallocate()
    return nil
  }
  s.pointee.initCnt = CInt(initCnt)
  s.pointee.limit = CInt(limit)
  return UnsafeRawPointer(s)
}

@c
func swifthal_os_sem_destroy(_ arg: UnsafeRawPointer?) -> CInt {
  guard let arg else { return -EINVAL }
  let s = UnsafeMutableRawPointer(mutating: arg).assumingMemoryBound(to: Semaphore.self)

  // Always destroy the mutex and free, even if sem_destroy fails, so the
  // give_lock and heap struct are not leaked.
  var err: CInt = 0
  if sem_destroy(&s.pointee.sem) != 0 { err = -errno }
  pthread_mutex_destroy(&s.pointee.giveLock)
  s.deinitialize(count: 1)
  s.deallocate()
  return err
}

@c
func swifthal_os_sem_take(_ arg: UnsafeRawPointer?, _ timeout: CInt) -> CInt {
  guard let arg else { return -EINVAL }
  let s = UnsafeMutableRawPointer(mutating: arg).assumingMemoryBound(to: Semaphore.self)

  if timeout == -1 {
    if sem_wait(&s.pointee.sem) != 0 { return -errno }
  } else {
    #if os(Linux)
    var ts = timeoutToTimespec(timeout)
    if sem_timedwait(&s.pointee.sem, &ts) != 0 { return -errno }
    #else
    return -ENOSYS
    #endif
  }
  return 0
}

@c
func swifthal_os_sem_give(_ arg: UnsafeRawPointer?) -> CInt {
  guard let arg else { return -EINVAL }
  let s = UnsafeMutableRawPointer(mutating: arg).assumingMemoryBound(to: Semaphore.self)
  var value: CInt = 0

  // Enforce the counting-semaphore limit (POSIX sem_post would happily count up
  // to SEM_VALUE_MAX). Serialize give against itself so the getvalue/post pair is
  // atomic w.r.t. other givers. pthread_mutex_lock returns the error directly and
  // does not set errno.
  let lockErr = pthread_mutex_lock(&s.pointee.giveLock)
  if lockErr != 0 { return -lockErr }

  var err: CInt = 0
  if sem_getvalue(&s.pointee.sem, &value) != 0 {
    err = -errno
  } else if s.pointee.limit == 0 || value < s.pointee.limit {
    if sem_post(&s.pointee.sem) != 0 { err = -errno } // limit == 0 is uncapped
  }

  pthread_mutex_unlock(&s.pointee.giveLock)
  return err
}

@c
func swifthal_os_sem_reset(_ arg: UnsafeRawPointer?) -> CInt {
  guard let arg else { return -EINVAL }
  let s = UnsafeMutableRawPointer(mutating: arg).assumingMemoryBound(to: Semaphore.self)
  var value: CInt = 0

  if sem_getvalue(&s.pointee.sem, &value) != 0 { return -errno }
  while value > s.pointee.initCnt {
    if sem_trywait(&s.pointee.sem) != 0 {
      if errno == EAGAIN { break }
      return -errno
    }
    if sem_getvalue(&s.pointee.sem, &value) != 0 { return -errno }
  }
  return 0
}
