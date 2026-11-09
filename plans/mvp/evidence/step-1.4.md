# Step 1.4 evidence

## Final owner acceptance

The owner ran Vite, Next, and Astro simultaneously, terminated Dev Manager from Xcode, relaunched it, and successfully started all three again. They reported, “I think I'm comfortable calling this done.” Recorded this as acceptance of Step 1.4's best-effort recovery after the child-count and per-run journal fixes; the final verification task is checked. This supersedes earlier pending/reopened Step 1.4 status below. No additional agent-side tests, app launches, process signals, or code changes were performed for this acceptance. Unreported synthetic metadata/error cases are not claimed as live-tested.

## Latest correction: child-count API and per-run records

The owner still saw Astro PID 84176 after app relaunch. Passive inspection showed the live app-origin orphan chain zsh 84160 → pnpm 84175 → Astro 84176, with Astro in its own group. RunJournal's actual diagnostic was `Could not inspect descendants of journal PID 84160: errno 5; leaving recovery alone`. A read-only libproc metadata query returned `proc_listchildpids = 1`, child PID 84175: this API returns a PID count, unlike `proc_listpids`. Corrected the C wrapper that incorrectly treated that count as bytes and returned EIO.

Also corrected journal record/removal/recovery matching to use the complete run identity rather than project ID alone. A failed subsequent Start can no longer overwrite or remove an unresolved older run for that project. No journal schema fields or recovery infrastructure were added.

Final incremental unsigned build passed (exit 0) using the existing `/tmp/dev-manager-astro-recovery-fix` command below; only the generic-destination metadata warning remained. No app launches, hosted tests, server commands, or process signals were performed. Read-only process metadata and app diagnostics were inspected. The current journal is empty, so the existing untracked Astro needs owner cleanup once before a newly tracked run can validate recovery. Step 1.4 and G1 remain unchecked pending that fresh owner walkthrough.

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

Source inspection found `dm_process_identity` read stale `errno == ESRCH` after successful `proc_pidinfo`, and rejected zombies during freshly spawned child identity capture. The approved narrow fix now separates conservative recovery identity from unreaped-created-child capture, and uses a bounded current descendant-tree query to signal positively attributed extra group leaders before the recorded root. Full identities are rechecked before every child/root TERM or KILL; unverifiable groups are left alone. The journal schema remains unchanged and historical orphan adoption is not added.

## Follow-up verification limits

- The owner approved the source fix with `okcoolareyougoodtotryfixthis`. The one scoped build-only check passed with the requested Xcode command and `/tmp/dev-manager-astro-recovery-fix` derived data after one compile-only `Int32` count correction; only the generic-destination metadata warning appeared.
- No app launch, hosted test, dev command, listener, dependency, live-process, or signal-control check was performed. The earlier measured Astro facts and empty journal remain diagnosis only; the empty journal does not establish historical record loss.
- Step 1.4 verification remains unchecked. G1 remains blocked until the owner performs one-time manual `pnpm exec astro dev stop`, then a fresh tracked run/recovery procedure. Normal Stop/quit behavior and general daemon cleanup are not claimed by this fix.
