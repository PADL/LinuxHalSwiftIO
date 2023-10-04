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
#include <sched.h>
#include <pthread.h>
#include <semaphore.h>
#ifdef __linux__
#include <mqueue.h>
#endif
#include <stdatomic.h>

#include "swift_hal_internal.h"

void swifthal_os_task_yield(void) { sched_yield(); }

struct swifthal_os_task {
    swifthal_task fn;
    void *p1, *p2, *p3;
};

static void *swifthal_os_task__start(void *arg) {
    struct swifthal_os_task *param = arg;
    param->fn(param->p1, param->p2, param->p3);
    return NULL;
}

void *swifthal_os_task_create(char *name,
                              swifthal_task fn,
                              void *p1,
                              void *p2,
                              void *p3,
                              int prio,
                              int stack_size) {
    pthread_attr_t attr;
    struct sched_param param;
    struct swifthal_os_task task;
    pthread_t thread;
    int err;

    task.fn = fn;
    task.p1 = p1;
    task.p2 = p2;
    task.p3 = p3;

    err = pthread_attr_init(&attr);
    if (err == 0)
        err = pthread_attr_getschedparam(&attr, &param);
    if (err == 0) {
        param.sched_priority = prio;
        err = pthread_attr_setschedparam(&attr, &param);
    }
    if (err == 0)
        err = pthread_attr_setstacksize(&attr, stack_size);
    err = pthread_create(&thread, &attr, swifthal_os_task__start, &task);

    pthread_attr_destroy(&attr);

    if (err)
        return NULL;

    return (void *)((intptr_t)thread);
}

#ifdef __linux__
struct swifthal_os_task__mqueue {
    mqd_t mq;
    int mq_size;
    char name[NAME_MAX];
};

static _Atomic(uintptr_t) mq_id = 0;
#endif

const void *swifthal_os_mq_create(ssize_t mq_size, ssize_t mq_num) {
#ifdef __linux__
    struct swifthal_os_task__mqueue *mq = calloc(1, sizeof(*mq));
    struct mq_attr attr;

    if (mq == NULL)
        return NULL;

    memset(&attr, 0, sizeof(attr));
    attr.mq_maxmsg = mq_num;
    attr.mq_msgsize = mq_size;

    snprintf(mq->name, sizeof(mq->name), "/LinuxHalSwiftIO.%d.%lu", getpid(),
             atomic_fetch_add(&mq_id, 1));

    mq->mq = mq_open(mq->name, O_RDWR | O_CREAT, 0600, &attr);
    if (mq->mq == -1) {
        free(mq);
        return NULL;
    }

    mq->mq_size = mq_size;

    return mq;
#else
    return NULL;
#endif
}

int swifthal_os_mq_destroy(const void *mp) {
#ifdef __linux__
    struct swifthal_os_task__mqueue *mq = (struct swifthal_os_task__mqueue *)mp;

    if (mq) {
        if (mq_close(mq->mq) != 0 || mq_unlink(mq->name) != 0)
            return -errno;
        free(mq);
        return 0;
    }

    return -EINVAL;
#else
    return -ENOSYS;
#endif
}

static struct timespec *swifthal_timeout_to_timespec(int timeout,
                                                     struct timespec *ts) {
    if (timeout == -1)
        return NULL;

    ts->tv_sec = timeout / 1000;
    ts->tv_nsec = (timeout % 1000) * NSEC_PER_MSEC;

    return ts;
}

int swifthal_os_mq_send(const void *mp, const void *data, int timeout) {
#ifdef __linux__
    const struct swifthal_os_task__mqueue *mq = mp;

    if (timeout == -1) {
        if (mq_send(mq->mq, data, mq->mq_size, 0) != 0)
            return -errno;
    } else {
        struct timespec ts;

        swifthal_timeout_to_timespec(timeout, &ts);

        if (mq_timedsend(mq->mq, data, mq->mq_size, 0, &ts) != 0)
            return -errno;
    }

    return 0;
#else
    return -ENOSYS;
#endif
}

int swifthal_os_mq_recv(const void *mp, void *data, int timeout) {
#ifdef __linux__
    const struct swifthal_os_task__mqueue *mq = mp;
    unsigned int prio;

    if (timeout == -1) {
        if (mq_receive(mq->mq, data, mq->mq_size, &prio) != 0)
            return -errno;
    } else {
        struct timespec ts;

        swifthal_timeout_to_timespec(timeout, &ts);

        if (mq_timedreceive(mq->mq, data, mq->mq_size, &prio, &ts) != 0)
            return -errno;
    }

    return 0;
#else
    return -ENOSYS;
#endif
}

int swifthal_os_mq_purge(const void *mp) {
#ifdef __linux__
    const struct swifthal_os_task__mqueue *mq = mp;
    struct mq_attr attr;
    unsigned int prio;
    void *data;

    if (mq_getattr(mq->mq, &attr) != 0)
        return -errno;

    data = alloca(mq->mq_size);

    while (attr.mq_curmsgs) {
        if (mq_receive(mq->mq, data, mq->mq_size, &prio) != 0)
            return -errno;
        attr.mq_curmsgs--;
    }

    return 0;
#else
    return -ENOSYS;
#endif
}

const void *swifthal_os_mutex_create(void) {
    pthread_mutex_t *mutex = calloc(1, sizeof(*mutex));
    if (mutex == NULL)
        return NULL;
    if (pthread_mutex_init(mutex, NULL) != 0) {
        free(mutex);
        return NULL;
    }

    return mutex;
}

int swifthal_os_mutex_destroy(const void *arg) {
    pthread_mutex_t *mutex = (pthread_mutex_t *)arg;
    int err;

    if (mutex) {
        err = pthread_mutex_destroy(mutex);
        if (err)
            return -err;
        free(mutex);
        return 0;
    }

    return -EINVAL;
}

int swifthal_os_mutex_lock(const void *mutex, int timeout) {
    int err;

    if (timeout == -1) {
        err = pthread_mutex_lock((pthread_mutex_t *)mutex);
        if (err)
            return -err;
    } else {
#ifdef __linux__
        struct timespec ts;

        swifthal_timeout_to_timespec(timeout, &ts);

        err = pthread_mutex_timedlock((pthread_mutex_t *)mutex, &ts);
        if (err)
            return -err;
#else
        return -ENOSYS;
#endif
    }

    return 0;
}

int swifthal_os_mutex_unlock(const void *mutex) {
    int err;

    err = pthread_mutex_unlock((pthread_mutex_t *)mutex);
    if (err)
        return -err;

    return 0;
}

struct swifthal_os_task__semaphore {
    sem_t sem;
    int init_cnt;
    int limit;
};

const void *swifthal_os_sem_create(uint32_t init_cnt, uint32_t limit) {
    struct swifthal_os_task__semaphore *sem;

    if (init_cnt > INT_MAX || limit > INT_MAX)
        return NULL;

    sem = calloc(1, sizeof(*sem));
    if (sem == NULL)
        return NULL;
    if (sem_init(&sem->sem, 0, init_cnt) != 0) {
        free(sem);
        return NULL;
    }
    sem->init_cnt = (int)init_cnt;
    sem->limit = (int)limit;

    return sem;
}

int swifthal_os_sem_destroy(const void *arg) {
    struct swifthal_os_task__semaphore *sem = (struct swifthal_os_task__semaphore *)arg;

    if (sem) {
        if (sem_destroy(&sem->sem) != 0)
            return -errno;
        free(sem);
        return 0;
    }

    return -EINVAL;
}

int swifthal_os_sem_take(const void *arg, int timeout) {
    struct swifthal_os_task__semaphore *sem = (struct swifthal_os_task__semaphore *)arg;

    if (timeout == -1) {
        if (sem_wait(&sem->sem) != 0)
            return -errno;
    } else {
#ifdef __linux__
        struct timespec ts;

        swifthal_timeout_to_timespec(timeout, &ts);

        if (sem_timedwait(&sem->sem, &ts) != 0)
            return -errno;
#else
        return -ENOSYS;
#endif
    }

    return 0;
}

int swifthal_os_sem_give(const void *arg) {
    struct swifthal_os_task__semaphore *sem = (struct swifthal_os_task__semaphore *)arg;

    if (sem_post(&sem->sem) != 0)
        return -errno;

    return 0;
}

int swifthal_os_sem_reset(const void *arg) {
    struct swifthal_os_task__semaphore *sem = (struct swifthal_os_task__semaphore *)arg;
    int value;

    if (sem_getvalue(&sem->sem, &value) != 0)
        return -errno;
    while (value > sem->init_cnt) {
        if (sem_trywait(&sem->sem) != 0 || sem_getvalue(&sem->sem, &value) != 0)
            return -errno;
    }

    return 0;
}
