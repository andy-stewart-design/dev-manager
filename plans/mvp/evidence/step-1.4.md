# Step 1.4 evidence

## Implementation

- Added `dev-manager/Runs/RunJournal.swift` (170 lines): atomic Application Support `Dev Manager/runs.json` JSON journal preserving other entries, with exactly `projectID`, `pid`, `pgid`, and full native `OSprocessStartTime` seconds/microseconds metadata. Records are written after verified spawn and removed only after confirmed cleanup; corrupt/unreadable journal data is logged and not overwritten.
- Extended the existing `ProcessIdentity.c/.h` libproc helper to read live/zombie state, current PGID, and native start time. `ProcessLauncher` captures that identity at spawn; `ProcessSupervisor` performs the minimal record/removal hooks.
- Startup recovery runs in detached work before `ProjectRunner` enables Start; normal Quit awaits any pending recovery before cleanup. It rechecks PID/start-time/leader-PGID identity before SIGTERM and before SIGKILL, waits 2 seconds then 1 second, drops dead/mismatched entries without signaling, and leaves ambiguous inspection/permission cases alone with OSLog diagnostics. Recovery does not use child `waitpid`, port matching, locking, adoption, or a second process owner. Concurrent app instances remain explicitly unsupported.
- Source choice: the existing native `ProcessIdentity` helper was narrowly extended rather than adding a subprocess or infrastructure layer. No UI warning/status panel was added; `isRecovering` only gates new Start until bounded recovery finishes.

## Verification

- Build-only check passed: `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -quiet -project dev-manager.xcodeproj -scheme dev-manager -configuration Debug -destination 'generic/platform=macOS' -derivedDataPath /tmp/dev-manager-1.4-build CODE_SIGNING_ALLOWED=NO build`.
- The first build exposed isolation warnings, corrected with explicit nonisolated data/recovery declarations. Source review also ordered start-time mismatch handling before group-leadership handling so reused PIDs are dropped as stale. A final incremental build using the same command/path passed (exit 0), emitting only the generic-destination metadata warning. No app launch, hosted test, dev command/listener, live-process smoke, or process manipulation was performed.
- Owner recovery walkthrough passed: after the requested updated-app Start → Xcode Stop without app Stop → relaunch cleanup → Start-again sequence, the owner replied, “Yes, that worked as intended.” That initial report was subsequently superseded by the Astro failure below; Step 1.4 verification is reopened and its final task is unchecked.
- No additional live identity-mismatch, ambiguous-metadata, or journal-I/O-failure fixtures were run, and normal-Stop journal-file deletion was not separately reported by the owner. Those branches have source inspection only; no unperformed runtime observation is claimed. G1 remains unverified.

## Reopened: Astro leftover and launcher identity failure

Owner reported Astro already running at PID 81203, followed by a launcher-start-identity error on another attempt. Read-only `ps` showed the app's orphaned zsh launcher PID/PGID 81187 (PPID 1), pnpm PID 81202 in PGID 81187, and Astro PID/PGID 81203. The Astro server is in a different group from its launcher; signaling only the recorded launcher group does not directly signal Astro. The current journal is empty, which does not establish when or why its former record was lost.

Source inspection found `dm_process_identity` reads stale `errno == ESRCH` even after a successful `proc_pidinfo`, potentially misclassifying a live PID as absent. It also rejects zombies during freshly spawned child identity capture, so a fast command failure can discard its real stderr and surface the wrapper identity error instead. No source fixes, app launches, tests, or process-control actions were performed during this diagnosis. These findings reopen 1.4 acceptance and block advancing to Phase 2.
