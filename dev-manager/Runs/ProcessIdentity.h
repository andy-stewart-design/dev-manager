#ifndef DEV_MANAGER_PROCESS_IDENTITY_H
#define DEV_MANAGER_PROCESS_IDENTITY_H

#include <sys/types.h>

/// Returns 1 when a non-zombie member exists, 0 when the group has only zombies
/// or no members, and a negative errno value when inspection is not possible.
int dm_group_has_non_zombie_members(pid_t process_group_id, pid_t leader_process_id);

#endif
