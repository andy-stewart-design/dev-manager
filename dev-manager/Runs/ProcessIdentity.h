#ifndef DEV_MANAGER_PROCESS_IDENTITY_H
#define DEV_MANAGER_PROCESS_IDENTITY_H

#include <sys/types.h>
#include <stdint.h>
#include <stddef.h>

/// Returns 1 for a live, inspectable process, 0 for an absent/zombie process,
/// and a negative errno value when inspection is ambiguous. Outputs the process's
/// native start time and current process group for the caller's identity checks.
int dm_process_identity(pid_t process_id, pid_t *current_process_group_id,
                        uint64_t *start_seconds, uint32_t *start_microseconds);

/// Same as dm_process_identity, but permits SZOMB for the unreaped child that
/// the caller has just created. This is not a recovery identity reader.
int dm_created_process_identity(pid_t process_id, pid_t *current_process_group_id,
                               uint64_t *start_seconds, uint32_t *start_microseconds);

/// Lists direct children into the caller's bounded buffer. Returns a count, or a
/// negative errno value; -EOVERFLOW means the buffer was too small.
int dm_process_children(pid_t parent_process_id, pid_t *children, size_t capacity);

/// Returns 1 when a non-zombie member exists, 0 when the group has only zombies
/// or no members, and a negative errno value when inspection is not possible.
int dm_group_has_non_zombie_members(pid_t process_group_id, pid_t leader_process_id);

#endif
