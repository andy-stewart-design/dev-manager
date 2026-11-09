#include "ProcessIdentity.h"
#include <libproc.h>
#include <sys/proc_info.h>
#include <sys/proc.h>
#include <errno.h>
#include <stdlib.h>

int dm_process_identity(pid_t process_id, pid_t *current_process_group_id,
                        uint64_t *start_seconds, uint32_t *start_microseconds) {
    if (process_id <= 0 || !current_process_group_id || !start_seconds || !start_microseconds) {
        return -EINVAL;
    }
    struct proc_bsdinfo info;
    int size = proc_pidinfo(process_id, PROC_PIDTBSDINFO, 0, &info, sizeof(info));
    if (size == 0 || errno == ESRCH) return 0;
    if (size != sizeof(info)) return -errno;
    if (info.pbi_status == SZOMB) return 0;
    *current_process_group_id = (pid_t)info.pbi_pgid;
    *start_seconds = (uint64_t)info.pbi_start_tvsec;
    *start_microseconds = (uint32_t)info.pbi_start_tvusec;
    return 1;
}

int dm_group_has_non_zombie_members(pid_t process_group_id, pid_t leader_process_id) {
    size_t capacity = 256;
    for (int attempt = 0; attempt < 4; attempt++) {
        pid_t *pids = calloc(capacity, sizeof(pid_t));
        if (!pids) return -ENOMEM;
        int bytes = proc_listpids(PROC_PGRP_ONLY, (uint32_t)process_group_id,
                                  pids, (int)(capacity * sizeof(pid_t)));
        if (bytes < 0) {
            int result = -errno;
            free(pids);
            return result;
        }
        if ((size_t)bytes >= capacity * sizeof(pid_t) && capacity < 8192) {
            free(pids);
            capacity *= 2;
            continue;
        }
        size_t count = (size_t)bytes / sizeof(pid_t);
        for (size_t i = 0; i < count; i++) {
            if (pids[i] <= 0 || pids[i] == leader_process_id) continue;
            struct proc_bsdinfo info;
            int size = proc_pidinfo(pids[i], PROC_PIDTBSDINFO, 0,
                                    &info, sizeof(info));
            if (size == sizeof(info)) {
                if (info.pbi_status != SZOMB) {
                    free(pids);
                    return 1;
                }
            } else if (errno != ESRCH) {
                int result = -errno;
                free(pids);
                return result;
            }
        }
        free(pids);
        return 0;
    }
    return -EOVERFLOW;
}
