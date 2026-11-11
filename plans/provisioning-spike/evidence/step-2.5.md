# Step 2.5 — Bounded shared provisioning command runner

Status: Source-only implementation pass. Cleanup review fixes and focused regression sources were updated; no build, test process, Swift parse, app launch, installation, download, or VM action was performed by the agent. The Step 2.5 gate, user-owned Debug Xcode verification, test execution, VM smoke, Release/setup-absence, ordinary-project, and final integration gates remain pending and unchecked.

## Source fixes recorded

- `ProvisioningCommandRunner` keeps one `ProvisioningProcessResult` for checks and installs, with separate eight-second and fifteen-minute caller policies.
- stdout and stderr are drained concurrently while each process runs, with bounded 12,000-byte tails. The focused large-output case now produces both streams concurrently in the same owned group, waits for both producers, and checks exact tail markers plus output bounds.
- Leader detection during cleanup explicitly supplements `dm_group_has_non_zombie_members`, whose contract excludes the leader. A timeout cannot skip signaling a leader-only group, and success is not returned while the owned leader remains live or inspection is uncertain; the leader is then reaped within finite grace.
- Timeout elapsed bounds are asserted in both failure-mode cases using the injected deadline, the two documented two-second cleanup phases, the 0.25-second drain-cancellation grace, and a generous five-second scheduling allowance.
- `/dev/null` normalization closes the original low descriptor in its failure catch because the normalizer leaves it open on duplication failure; successful normalization still owns its own close path without a double close.
- Cleanup and output cancellation are explicitly scoped to the spawned process group. Detached `setsid` descendants are not tracked or chased; cancellation still bounds output capture if an escaped writer retains an inherited pipe. No broad process-tree tracking or detached-process fixture was added.
- `dev-manager/Runs` and the existing `ProcessIdentity` C bridge semantics remain unchanged.

## Focused tests added or corrected (not run)

- `ProvisioningCommandRunnerTests.drainsLargeOutputWithoutPipeBackpressure`
- `ProvisioningCommandRunnerTests.leaderOnlyTimeoutReapsLeader`
- `ProvisioningCommandRunnerTests.descendantHoldingPipesCannotExtendCommandDeadline`

The tests use temporary scripts and the existing DEBUG Swift Testing conventions only. The leader-only case records the actual launcher PID, verifies timeout and bounded elapsed time, and checks that the leader is no longer alive after the runner returns. The descendant-held-pipes case checks group members after the leader has exited/reaped; its descendant-only `isGroupAlive` assertion is appropriate because that helper intentionally excludes the leader.

No test or gate is claimed by this source-only pass.
