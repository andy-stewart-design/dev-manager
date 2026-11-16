# Step 2.1 evidence

Status: Step 2.1 verification and completion gate are recorded complete from the user's reported VM walkthrough and the source guard review below. The VM walkthrough used the user's Xcode-built Debug artifact; it is not an agent-run result or the plan's exact CLI `xcodebuild` invocation. No build, test, `xcodebuild`, app launch, installation, download, or VM action was run by the agent.

## Source-only implementation review

- Runtime installation now invokes `fnm install 24.22.2`; `--skip-shell` was removed because it is not a valid `fnm install` CLI flag. The standalone `fnm exec --using VERSION ...` checks and fixture command retain an explicit version without `fnm env` or `FNM_MULTISHELL_PATH`; the fixture also sets `FNM_COREPACK_ENABLED=false`. A GUI-safe PATH is supplied when the parent environment has no PATH.
- The `fnm list` preflight is read-only: standalone `fnm exec` fails when the requested version is absent and does not install it. `FNM_COREPACK_ENABLED=false` remains set; pnpm is installed only through npm in the selected Node runtime, and conflicting/unusable tools stop the dependent sequence.
- Installer execution uses a local `posix_spawn` process group, drains both output streams, bounds process-group cleanup and pipe draining, and closes owned pipe ends on spawn success/failure. No shared runner or `ProcessLauncher` behavior was changed.
- Fixture creation preflights owned paths with `lstat`, refuses symlinks/conflicts, writes a marker and exact files into an app-owned staging directory, then moves the completed directory into place. An exact marked fixture is reused; unexpected contents remain unchanged.
- Fixture handoff reuses only an existing entry with the identical command. A user-modified command is reported and left unchanged; unrelated projects are not mutated.

## User-reported walkthrough

The user replied exactly 'That succeeded' after receiving instructions to build in Xcode/transfer the VM artifact; use Setup to install the runtime and prepare the fixture; confirm fnm, Node, and pnpm; show the fixture, Start it, open its discovered HTTP site, Stop/Start, then quit/reopen and repeat setup with reuse, no duplicates, and no shell edits. This records reported success only; no screenshots or logs were furnished.

## Shell-file result and completion gate

The user reported the instructed runtime/fixture walkthrough succeeded, exactly: **“That succeeded.”** This report covers the pinned runtime and fixture, the discovered HTTP site, Stop, restart, quit/reopen, repeated setup, reuse of the working versions, and no duplicate fixture/configuration.

For the shell-file check, the user explicitly reported that **neither `.zshrc` nor `.zprofile` exists in the VM user's home**, so no shell-file changes were made. This is recorded as a user report, not as agent disk inspection. The earlier user-provided clean baseline, together with the reported absence of both files after the run, establishes the no-shell-edit result for this scoped path. No claim is made about any other shell file or machine.

The failure/not-ready invariant is resolved by source inspection, not by claiming a live disabled-button click or error injection: `ProvisioningModel.canInstallRuntime` requires a completed supported-environment check, ready Homebrew, and acceptable fnm/Node/pnpm states, and also requires that the fixture is not already prepared. `ProvisioningView` disables **Install runtime / prepare fixture** when that guard is false, and only presents **Show fixture project** once both `fixtureURL` and `fixtureCommand` exist. `installRuntimeAndPrepareFixture()` repeats the guard and returns before work; each failed prerequisite/install check returns without preparing the fixture. This supports the required blocking behavior without adding a manual failure run to the evidence.

Accordingly, the Step 2.1 verification task and completion gate are checked in the plan. The manual evidence remains user-reported rather than agent-observed, and the exact planned CLI Debug build command was not run in this closeout. Historical build notes remain preserved elsewhere in this evidence set; no agent build of the latest changes is implied. No Phase 2.2 work or findings document was created.

### Remaining Step 2.1 caveat

There is no remaining manual Step 2.1 blocker based on the reported walkthrough and source review. The evidence has the normal provenance limitation: no screenshots/logs were supplied here, and the planned CLI build command is not independently claimed as run by the agent.
