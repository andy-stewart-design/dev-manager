# Agreed planning changes

## Step 2.1 source placement and compile compatibility

The user authorized Step 2.1 after approving feature-oriented source organization, with `Discovery/` added when discovery work begins. Its expected files now use `Discovery/` in app and test sources rather than root-level parser files. The compile-only check also required existing runner-test constructors to pass the process start time introduced in 1.4; this aligns an existing API consumer and adds no process behavior or test execution. Requirement/acceptance IDs and parser-only scope are unchanged.

## Step 1.2a responsibility split

The owner approved “ok, let's do 1.2a” after the proposed split explicitly assigned log reading/decoding/partial-line assembly to the existing log components. The step's expected files now include `Runs/LogBuffer.swift`, where `RunOutputAccumulator` was extracted. This is part of that approved behavior-preserving decomposition, not new product scope. Implementation checkboxes reflect performed source work; manual composition checks remain unchecked in the plan and pending in `step-1.2a.md`.

## Minimum macOS version

- Change: set the app and native unit-test minimum deployment targets to macOS 15.0 (Sequoia), replacing the previously unspecified target in the spec/plan. No macOS 14 compatibility work is planned.
- Actual agreement: after the assistant recommended macOS 14, the owner responded, “Honestly, 15.0 seems fine. That was released 2+ years ago.” The owner's chosen compatibility boundary takes precedence over that recommendation.
- Updated the spec's platform scope/remaining scaffold decisions and the plan's execution constraints/Step 0.1. Step IDs, task completion, acceptance mappings, and evidence paths are unchanged. This records a planning decision only; no Xcode configuration was changed and no build or runtime check was performed.

## Explicit request: complete the missing native test scaffold

- Change: for the current request to finish the technical scaffold portion of Phase 0/Step 0.1, add the missing lightweight native macOS unit-test target and one Swift Testing smoke-test source within the existing owner-created Xcode scaffold. Wire the existing `dev-manager` scheme's Test action through a shared scheme only as needed for the repeatable native test command.
- Actual authorization: the user explicitly asked to “do what we need to do to finish out 0.1” after the missing native target and build/test/launch validation were identified. This changes only who adds the missing target: the implementation worker may complete that target in the existing scaffold instead of the earlier owner-through-Xcode-only instruction.
- Narrow plan amendment: Step 0.1 now permits this explicit in-scaffold target addition and records it as the completed target task. IDs, gates, verification requirements, owner environment coordination, signing/security boundaries, and all other tasks remained unchanged at that point. The remaining handoff was subsequently resolved as recorded below.

## Correct premature scaffold prerequisites

- Owner reported “project runs fine” and asked why Vite/Next paths were needed when projects can be added manually through the app. The assistant accepted that correction: no upfront real-repository paths or listener permissions are required to finish the scaffold handoff. Owner-driven real-project validation still happens in the relevant implementation steps through the app.
- Narrow plan correction: Step 0.1 records the statically inspected shell/tool setup rather than blocking on approved live-project paths; native build/test evidence plus the owner's starter-launch confirmation satisfy the baseline. Redundant UI Build/Test repetition is unnecessary; full window/process-lifetime checks stay with Step 1.3. No close/reopen observation or owner approval of unperformed tests is invented.
- Checked Step 0.1's remaining tasks and recorded G0's conclusion in `step-0.1.md`. Acceptance IDs, later lifecycle/discovery gates, signing/security boundaries, and manual-first validation remain unchanged. This does not authorize starting Phase 1 automatically.

## Step 1.1 sequencing correction: move App Sandbox disablement

- Change: move the already-planned app-target App Sandbox disablement from Step 1.2 into Step 1.1, before owner validation of persisted folder settings. This resolves the sequencing risk that sandboxed folder access and app-support storage could differ across relaunch without adding bookmarks or a migration.
- Exact user authorization: parent question, “Can I move the already-planned sandbox disable from1.2 into this step?” Owner response: “yes”.
- Narrow plan amendment: Step 1.1 now includes the minimal `PROJECT` app-target configuration change; Step 0.1's forward reference and Step 1.2's expected-configuration wording now point to that completed Step 1.1 change. No IDs, checkboxes, acceptance mappings, dependencies, gates, or unrelated spec behavior changed. The Step 1.1 verification checkbox remains unchecked pending the owner's add/edit/quit/relaunch walkthrough.
- Actual setting change: app target `ENABLE_APP_SANDBOX` changed from `YES` to `NO`. Existing signing style/team, hardened runtime, macOS 15 deployment settings, user-selected-files setting, app groups setting, and all unrelated app/test/security settings were preserved. No entitlements workaround, provisioning/account change, process runner, command execution, Phase 1.2 work, bookmarks, installer, dependency, or cleanup work was added.
- Settings data check: the expected non-sandboxed settings file and sandbox-container settings path were absent when checked. No owner settings data was copied, deleted, migrated, or printed. A later prior-sandbox settings file must be surfaced to the owner rather than reset or migrated automatically.

## Step 1.1 UI/removal addition

- Change: add explicit leading alignment for the editable command, remove the confusing in-place folder-switch control, and add a destructive-style `Remove Project…` action at the detail bottom. Confirmation states that only the app's saved entry is removed and the disk folder/files are untouched; cancellation is nonmutating. Removal saves atomically before changing memory, reports failed saves without losing the entry/selection, is disabled in read-only mode, and reconciles selection after success.
- Actual user approval: the parent proposal covering “left-align command; remove confusing Choose Different Folder button; add Remove Project… at bottom with confirmation” was answered by the user, “yes plz”. This is implementation approval only; it is not owner approval of the manual walkthrough or full acceptance.
- Narrow scope amendment: add stable R11 and AC18, focused native store tests for removal persistence/unchanged bytes, failed-save retention, and unknown-ID safety, plus the Step 1.2 integration note that future runner wiring must disallow removal of active/stopping projects. No runner, file deletion, Git operation, custom dialog framework, keyboard handler, Phase 1.2 work, signing/sandbox change, or new phase was added.
- Recovery clarification: because the folder-switch control is removed, a missing registered folder is recovered by removing the app entry and re-adding the correct folder. No in-place recovery behavior was invented.

## Approved Step 1.1 source organization refactor

- Actual user authorization: the owner accepted the proposed source structure with “This seems good to me” and explicitly requested the source filename rename `dev_managerApp.swift` → `devManagerApp.swift`.
- Scope: preserve the current command layout and all existing behavior while organizing the existing app/test sources under the approved folders. No target, bundle, module, scheme, dependency, signing, sandbox, runtime, or settings-format rename/change was authorized by this refactor.
- The exact current source map and verification are recorded in `evidence/step-1.1.md`; historical scaffold/implementation notes above retain their original paths and are not rewritten as if the new layout existed earlier.

## Explicit request: proceed with Step 1.2

- Actual user direction: after the Step 1.1 UI discussion, the owner said, “Nice. Let's do1.2”. This records approval to begin the Step 1.2 implementation review increment; it does not claim the still-pending Step 1.1 manual checkbox or any individual manual acceptance observation.
- Narrow source-layout amendment used for this increment: add `APP/Runs/` for `ProjectRunner`, `RunState`, `LogBuffer`, `ShellEnvironment`, `ProcessLauncher`, and `OutputReader`, plus `APP/App/AppLifecycle.swift` and `TESTS/Runs/ProjectRunnerTests.swift`. These are the plan's named leaf responsibilities and native integration points, not a new orchestration layer or new behavior outside Step 1.2.

## Agreed followups: Step 1.2 audit, composition, and bounded recovery

- Actual user direction: the owner agreed to do followups 1 and 2 now, endorsed the small bounded stale-run-recovery scope, and then asked, “Ok, so it sounds like we'll do1and2now. Should we update the plan to capture3and4?” This authorizes a documentation-only plan update; it does not approve code changes, app launches, live-process checks, hosted tests, or any unobserved runtime result.
- Followup 1 captured in Step 1.2: audit/use `POSIX_SPAWN_CLOEXEC_DEFAULT` where supported and explicitly audit stdin/stdout/stderr/readiness inheritance before the step can finish. The task remains unchecked.
- Followup 2 captured in Step 1.2: move launch/setup and blocking supervision off the main actor while keeping rendering/state main-actor-owned, preserving `duplicateStart`, `pendingStartStop`, Remove, and Quit ownership across awaits. The task remains unchecked.
- Followup 3 captured as stable Step 1.2a before Step 1.3: a bounded `ProcessSupervisor.swift` decomposition using the real `Runs/` paths, with no framework/DI/protocol forest and no mandatory `AsyncStream` product API. Existing Step 1.2 gates remain required; the new step and `evidence/step-1.2a.md` are future work and no evidence file was created.
- Followup 4 captured as stable Step 1.4 before G1/Phase 2: one atomic Application Support JSON `RunJournal.swift` entry per run (`projectID`, `pid`, `pgid`, `OSprocessStartTime`), written after spawn as soon as practical and removed only after confirmed stop. Recovery requires live PID, matching OS start time, and PID leadership of the recorded positive PGID; it rechecks identity before SIGTERM and SIGKILL, warns diagnostically, drops dead/mismatched records without signals, leaves ambiguous identity/group/permission alone, and deliberately drops dead-leader/live-child cases. The spawn-to-write window, unsupported concurrent instances, no adoption/reconnect/watchdog/locking/PTY/log archives, warning-only failures, and non-child orphan/no-`waitpid` handling are explicit. The new step and `evidence/step-1.4.md` are future work and no evidence file was created.
- Future verification gates were narrowed to owner manual-first checks, with one owner-approved Xcode build procedure and optional focused native/metadata checks only on explicit approval. Existing historical build/test evidence, including `evidence/step-1.2.md`, is preserved and is not reclassified as proof of these followups. Existing app/store/project/view structure and target settings were preserved.

## Explicit request: remove the planned Step 1.3 increment

- Actual authorization: the owner directed, “OK, I feel like we should just delete 1.3 and move onto 1.4. I don't think the remaining work in 1.3 is worthwhile/desireable”. The planned Step 1.3 section and its future Restart/failure-recovery work were removed; Step 1.4 now depends on completed Step 1.2a and the existing Step 1.2 gate. Stable requirement/acceptance IDs, completed work, unchecked verification status, and historical evidence were preserved.
- Scope intent: the owner further clarified, “Clearing logs when we restart feels like the right UX, not a bug”. This is recorded as intentional UX, not a defect: there is no new Restart button/API and no cross-run log history. A user can Stop and then Start manually after cleanup; a successful new run has fresh discovery and a fresh bounded log buffer. Existing window close/reopen and normal Quit behavior from Step 1.2 remains required and is not a reimplementation phase.
- Plan/spec corrections are limited to wording and cross-references: lifecycle language now says Start/Stop, stale-event language covers Stop/exit/subsequent Start, acceptance scenarios formerly saying Restart use Stop then Start without deleting their IDs, and mappings formerly owned by 1.3 point to existing 1.2/1.2a proof or Phase 1 G1 after 1.4. No runtime evidence was invented, and historical references in prior evidence/approval notes were not rewritten as though Step 1.3 never appeared in the earlier plan.

## Explicit approval: narrow Step 1.4 recovery fix

- Actual user approval: after the read-only diagnosis, the owner replied `okcoolareyougoodtotryfixthis`, authorizing concrete Step 1.4 source fixes only. No app launch, hosted test, dev command, listener, dependency, or live-process control was authorized or performed.
- Measured diagnosis facts preserved: orphan launcher zsh PID/PGID 81187 had PPID 1; pnpm PID 81202 was under launcher group 81187; Astro PID/PGID 81203 was a separate child group. The journal was `[]`; this does not establish historical record loss. The owner had an existing Astro server on localhost:4321, while a fresh start failed with `created launcher start identity could not be read`.
- Implementation scope: `ProcessIdentity` now uses the returned `proc_pidinfo` size before interpreting errno, returns conservative `EIO` for ambiguous short/permission reads, permits zombie identity only for the unreaped freshly-created child capture, and adds a bounded direct-child libproc query. `RunJournal` inspects the verified root's current descendant tree, signals positively attributed additional group leaders before the root, and rechecks full identities before each signal; journal fields remain unchanged and no child records are persisted.
- Verification: the single scoped Debug macOS build using `/tmp/dev-manager-astro-recovery-fix` passed after one compile-only correction (`Int32` count to `Int`). No runtime or process-control result is claimed. Step 1.4 verification remains unchecked and G1 remains blocked until the owner performs the one-time manual `pnpm exec astro dev stop` cleanup and a fresh tracked run/recovery procedure.

## Approved Step 2.2 startup-verification polling clarification

- User approval recorded for the narrow behavior: probe until the site first responds, stop HTTP polling once startup-ready, clear the per-run cache on Stop/exit/new run, and probe again only for a new URL/port or changed owned listener identity.
- Implementation uses small per-run coordinator dictionaries keyed by exact URL and full `LocalSiteListener` identity (PID, OS start time, process group, and listener port). It retains bounded listener/announcement scanning and ownership revalidation, without adding a persistent cache, service, registry, watcher, dependency, or process behavior.
- R8/spec wording is narrowly clarified: readiness is startup verification, not continuous health monitoring. Existing IDs, gates, and task boundaries remain unchanged; the final 2.2 manual verification is still pending and no owner result is claimed.
