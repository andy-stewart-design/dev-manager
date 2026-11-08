# Step 1.2 — Start and stop an isolated real command with live output

## Implementation status

Step 1.2 code is present, but the last worker was cancelled during follow-up review corrections. The latest build-only result below does not establish runtime correctness; earlier test results describe their earlier source revision. This remains an implementation record, not owner acceptance: Finder launch, the owner's real `pnpm dev`/toolchain, two real projects plus an unrelated server, startup cancellation, and normal-Quit observation remain pending. No Step 1.3 Restart/window/discovery work was added.

- `Runs/ProcessLauncher.swift` now uses `posix_spawn` with a dedicated process group, explicit signal-default/mask reset, checked file-action/attribute initialization and additions, descriptor normalization above stdin/stdout/stderr, and protected cleanup for every spawn failure. The command is passed as a positional argument; readiness is an exact private inherited-pipe byte, not a log marker.
- The launcher observes the direct child with `waitid(... WNOWAIT ...)` and keeps that child unreaped through the one shared per-run cleanup task. Native process-group inspection ignores the owned leader once it is a zombie and checks non-zombie members before each group signal. The leader is reaped only after the group is gone; no production path signals a bare/recycled PGID.
- `Runs/ProcessIdentity.c/.h` is the narrow native wrapper for macOS `libproc` group-member/status inspection. It conservatively treats inspection failure as live/unknown. Created children are directly terminated/reaped on post-spawn ownership verification failure without signaling an unexpected observed group.
- `Runs/ProjectRunner.swift` joins duplicate Stop/quit cleanup to one task and keeps `activeRuns` ownership until cleanup, both output streams, and the anchored launcher completion are finished. Late ready/exit/output events cannot turn a terminal run back into running. Startup readiness has a separate 10-second timeout.
- `Runs/OutputReader.swift` adds a bounded per-run pending handoff (256 KiB), one scheduled main-actor drain, dropped-byte notices, bounded incomplete UTF-8-safe-ish line storage (64 KiB per stream), and coalesced publication. `LogBuffer` remains capped at 2 MiB.
- `App/AppLifecycle.swift` sets the runner termination gate before awaiting, performs blocking OS cleanup in detached tasks, replies false on cleanup failure, and retains ownership. Start/Stop/remove controls derive from runner ownership and the quit gate. Removal confirmation rechecks `runner.canRemove` immediately before synchronous store mutation.

## Actual native checks

All commands were run from the project root with the requested scoped developer directory, unsigned build, and fresh temporary derived data. No TCP servers, installs, external repositories, credentials, or global settings were used.

```sh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
  xcodebuild -project dev-manager.xcodeproj -scheme dev-manager \
  -configuration Debug -destination 'generic/platform=macOS' \
  -derivedDataPath /tmp/dev-manager-last-build \
  CODE_SIGNING_ALLOWED=NO build
```

Result: exit 0; unsigned native Debug build succeeded. A prior `-quiet` invocation emitted an Xcode diagnostic despite a successful non-quiet rerun; the non-quiet command completed successfully.

```sh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
  xcodebuild -project dev-manager.xcodeproj -scheme dev-manager \
  -configuration Debug -destination 'platform=macOS,arch=arm64' \
  -derivedDataPath /tmp/dev-manager-finalverify CODE_SIGNING_ALLOWED=NO test
```

Result: exit 0; all 13 Swift Testing tests passed, including the existing persistence tests and real subprocess checks for cwd/stdout/stderr, duplicate Start, separate process-group survival, concurrent Stop joining, missing-command reporting, and 500 KiB unterminated high-rate output with bounded retained/truncation-accounted state.

The focused subprocess tests clean up their owned groups in normal and deferred paths. They do not prove the owner's Finder environment, real `fnm`/Homebrew setup, or arbitrary detached daemons.

## Verification / handoff status

- The earlier build/test checks above were performed, but do not constitute verification of all subsequent review fixes. The latest working tree has only the build-only check below; runtime behavior is unverified.
- Step 1.2 owner verification checkbox: **pending**. The owner must still launch the built app through Finder and validate real projects/tool versions, independent project/server isolation, startup cancellation, and normal Quit.
- Step 1.1 manual walkthrough remains pending in its own evidence. Step 1.3 and all URL/discovery/browser work remain untouched.
- No claim is made that cleanup after crash/Force Quit or deliberately detached daemon ownership is guaranteed; those remain outside the governing MVP scope.

## Readiness descriptor correction

Owner screenshot showed `zsh:1: command not found: 11`: the wrapper's `exec 11>&-` was interpreted as a command, not a multi-digit descriptor close. Changed only the launcher script to close through zsh's parameter-based redirection (`exec {_dev_manager_ready_fd}>&-`). At the owner's request for a quick manual retest, no build, test, app launch, or development command was run after this edit. Runtime confirmation remains pending.

## Build-only handoff after worker cancellation

At the owner's request to shorten worker sessions and leave manual testing to them, ran one build only from the project root:

```sh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer /usr/bin/xcodebuild -quiet -project dev-manager.xcodeproj -scheme dev-manager -configuration Debug -destination 'generic/platform=macOS' -derivedDataPath /tmp/dev-manager-1.2-handoff.RA7WsD CODE_SIGNING_ALLOWED=NO build
```

Exit 0; Xcode emitted a generic-destination metadata warning. No app was launched and no tests or development commands were run. App-hosted test runs are no longer automatic because they launch the host app. The owner will first validate one project through the app: Start, Running/log output, Stop, Start again, then normal Quit cleanup. Step 1.2 acceptance remains unchecked.

## Live-log delivery fix

- `Runs/OutputReader.swift` now uses a dedicated-queue blocking POSIX `read`, which delivers currently available pipe bytes instead of waiting on the large `FileHandle` read request; EINTR, EOF, and existing cancellation/descriptor ownership are preserved.
- `Runs/ProjectRunner.swift` and `Runs/LogBuffer.swift` now upsert bounded unterminated output into one stream/run entry, finalize it on LF/EOF, treat CR as progress updates, and retain raw partial bytes across chunks for split UTF-8. `Projects/Views/ProjectDetailView.swift` keeps the log panel visible during an active empty run with `Waiting for output…`.

## Actual check for this fix

The initial unsigned Debug build exposed a SwiftUI conditional-branch inference error; wrapping those branches in `VStack` corrected it. A final incremental build from the project root succeeded (exit 0):

```sh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer /usr/bin/xcodebuild -quiet -project dev-manager.xcodeproj -scheme dev-manager -configuration Debug -destination 'generic/platform=macOS' -derivedDataPath /tmp/dev-manager-live-log-build CODE_SIGNING_ALLOWED=NO build
```

Xcode emitted a generic-destination metadata warning. No app launches, tests, servers, or development commands were run. This proves compilation only; live streaming still requires owner observation.

Owner next check: Start Astro and confirm initial logs appear while Running; trigger a code change and confirm newer logs arrive before Stop; Stop and confirm recent logs remain visible. Step 1.2 verification remains unchecked.

## Approved Step 1.2 follow-ups completed

- `Runs/ProcessLauncher.swift`: added `POSIX_SPAWN_CLOEXEC_DEFAULT`. The existing explicit `dup2` actions continue to inherit only stdin, stdout, stderr, and the private readiness descriptor; their target descriptors clear close-on-exec, while source descriptors and all other parent descriptors remain closed. Existing zsh multi-digit readiness close, positional command, checked spawn cleanup, process-group/signal flags, and cwd action are unchanged.
- `Runs/ProjectRunner.swift` / `Runs/RunState.swift`: reserved a run ID and active ownership state before detached environment/spawn work. Pending runs participate in authoritative Start/Stop/Remove/Quit checks. Stop and Quit cancel pending setup, await launch settlement, and clean any process that is created before cancellation; cleanup retains ownership until the existing output and group barriers finish.
- `Runs/ShellEnvironment.swift` and `Projects/Project.swift`: marked the environment factory and folder URL projection nonisolated so the detached launch boundary is explicit and buildable.
- `plans/mvp/plan.md`: checked only the two approved Step 1.2 follow-up implementation tasks. The Step 1.2 verification/completion gate remains unchecked; Step 1.2a/1.3/1.4 were not changed.

### Verification for this follow-up

Command run once, then one incremental recheck after a quick compile fix:

```sh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer /usr/bin/xcodebuild -quiet -project dev-manager.xcodeproj -scheme dev-manager -configuration Debug -destination 'generic/platform=macOS' -derivedDataPath /tmp/dev-manager-step12-followup CODE_SIGNING_ALLOWED=NO build
```

Initial compile reported actor-isolation diagnostics for the detached launch boundary; marking the existing pure environment/folder projections `nonisolated` corrected it. The single incremental recheck used the same command and exited 0 (Xcode emitted only its generic-destination metadata warning). No app launch, tests, hosted tests, development command, listener, or process smoke test was run.

Owner manual checklist still pending: Finder launch; one real project Start/Stop/Start; Stop during pending startup; duplicate Start while pending; project Remove during pending/stopping; Quit during pending startup and during cleanup; two-project and unrelated-server isolation; descriptor-leak observation. Earlier owner confirmation covers only the readiness-FD close fix and improved live streaming, not these follow-up behaviors. Final Step 1.2 verification remains **unchecked**.
