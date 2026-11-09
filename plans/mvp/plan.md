# Dev Manager MVP Implementation Plan

## Governing source

- Governing spec: [spec.md](spec.md)
- Orientation: [overview.md](overview.md)
- Additional owner direction: the owner creates the Xcode scaffold and participates heavily in setup/manual validation; prioritize a useful MVP over elaborate architecture or testing infrastructure.

This plan is an execution contract. Routine changes are limited to checking performed task boxes. Scope, IDs, dependencies, expected files, verification definitions, gates, and acceptance mappings change only with explicit owner agreement, recorded in `evidence/changes.md`. A checkbox is not acceptance, approval, publication, deployment, or release. Supervised-workflow approvals remain in extension state; evidence may cite actual approval but never invent it.

## Execution constraints

- Project root: `/Users/andy/Documents/Development/dev-manager`. Paths below are relative to that root; evidence links are relative to this plan.
- Authoring inspection found only `plans/mvp/spec.md` and `overview.md`: no application scaffold, existing tests/tooling, applicable project instructions, or Git metadata. No build, test, launch, or runtime verification was performed. There is no established green baseline.
- Minimum deployment target: **macOS 15.0 (Sequoia)** for the app and its unit tests, explicitly selected by the owner. Build with the owner's current Xcode/SDK; no macOS 14 compatibility work is required.
- **Owner scaffold gate:** application work depends on Step 0.1. The owner supplies the app scaffold; under the explicit request recorded in `evidence/changes.md`, a missing native unit-test target may be added within that existing scaffold. Do not generate or replace the Xcode project, choose a signing identity, or initialize Git on the owner's behalf.
- File aliases accommodate the deliberately owner-created layout: `APP` is the actual app target's Swift source directory; `TESTS` is its native unit-test source directory; `PROJECT` is the owner's Xcode project/workspace and target configuration. Step 0.1 records their concrete paths in evidence. Leaf files below are proposed additions, not existing files. Existing equivalent files should be reused; a material scope/layout conflict requires an agreed plan amendment, not an opportunistic rewrite.
- Use SwiftUI, Foundation/AppKit, and minimal macOS process/socket APIs or bundled system tools. No third-party terminal emulator, dependency framework, generic job orchestration layer, release pipeline, or custom integration harness is planned.
- Implement one project model, one owner of each run, and one per-run discovery coordinator; avoid redundant service abstractions. A small launch wrapper is acceptable only if needed to establish reliable process-group ownership.
- The app may execute only explicitly started commands under current-user privileges. Never signal a process because it owns a familiar port, modify repository/shell files, install project dependencies, or use automatic elevation. Preserve unrelated work and unrelated services.
- Use a bounded pipe/log experience, not a PTY. Start and cleanup must be delivered together before exposing live command execution. Keep UI consumers and their state changes buildable within each step.
- Proposed initial internal limits: a 2 MiB bounded log buffer per run, retained after Stop or exit until the next Start; each successful Start begins a fresh buffer rather than cross-run history. Graceful interrupt runs for up to 3 seconds, terminate for another 2 seconds, then kill and allow 1 second for confirmation; 10-second bounded environment-initialization attempt; 2-second per-request probe deadline; at most four concurrent probes per run; owned-listener scan every 2 seconds while the run is active; show an informational no-site result after 15 seconds without ending discovery. A successful startup verification is cached for that run and is not continuously HTTP health-polled; listener/announcement scans continue for new targets and ownership changes. Quit shuts down runs concurrently rather than multiplying the per-run budget. Unexpected cleanup failure must remain visible. These are planned defaults to validate, not observed behavior or permission to change the contract silently.
- Focused checks stay small and manual-first: proposed `LocalURLCandidateTests` plus focused run-freshness checks in the existing `TESTS/Runs/ProjectRunnerTests.swift` remain optional owner-approved checks. No UI tests, CI setup, coverage target, exhaustive shell matrix, persistent fixture service, or new hosted-test infrastructure. Use owner-run manual commands/servers and existing owner projects for live proof; do not automatically launch the app or run hosted tests because app-hosted tests launch the app.
- Future verification gates should use the actual owner-approved Xcode build procedure and owner manual behavior checks first. A focused native test or isolated metadata check is optional only with explicit owner approval; historical test/build evidence remains historical and is not rewritten as new proof.
- Before touching owner projects, starting listeners, occupying ports, running high-output commands, or building an artifact, coordinate the session with the owner. The owner supplies safe project paths, available ports, installed tools, and necessary platform access. Missing prerequisites block their specific checks; they are not passes.
- Every completed step gets a short note at its predetermined evidence location. Record check/action, observed result, and material caveat, usually in a few bullets. No empty evidence files during planning, chronological diaries, raw transcripts, or duplicate progress ledgers. Failed/blocked/skipped/waived gates remain unchecked; record rationale, known approval owner, and follow-up. A waiver is not a pass.

## Phase overview and delivery boundary

| Phase | Outcome | Dependencies | Exit gate |
| --- | --- | --- | --- |
| 0 | Owner-provided scaffold and reproducible native build baseline | Owner Xcode handoff | G0: inspect real targets/settings, build and launch the supplied app |
| 1 | Useful project/process manager with logs, safe lifecycle, separated supervision/state composition, and bounded stale-run recovery | G0 | G1: two independent live projects, bounded cleanup, window/quit behavior, Step 1.2a composition, and best-effort Step 1.4 recovery review |
| 2 | Automatic current-run localhost discovery and browser opening | G1 | G2 initial baseline: HTTP dynamic-port/browser flow, filtering, and stale-run isolation; compatibility checks remain separately deferred |
| 3 | Owner acceptance of the initial baseline and separate direct-distribution check | G2 initial baseline; owner access to representative projects as needed | G3: baseline acceptance reconciliation; G-share: artifact suitability before sharing |

Delivery boundary: one feature-complete change set and, if the owner proceeds, one alpha app artifact for direct distribution outside the Mac App Store (a ZIP is a possible packaging form, subject to the separate Step 3.2 check). Phases are review increments, not separate PR requirements. No commit, push, sharing, or release is authorized by this plan.

Atomic groups: each step's implementation, state consumers, target membership, and focused verification land/revert together. In particular, Step 1.2 must never expose a launcher without its stop/isolation behavior; Step 1.2a must keep supervision and main-actor state transitions together; Step 1.4 must keep journal writes, recovery decisions, and confirmed-cleanup removal together. There is no replacement implementation or schema migration to remove.

## Phase 0 — Owner scaffold and baseline handoff

Outcome: a real Xcode project, known app/test source locations, and an observable native baseline.
Depends on: owner availability and Xcode/macOS access.
Review boundary: owner-created scaffold and read-only inspection/build characterization; no feature implementation.

### Step 0.1 — Accept the owner's Xcode scaffold

Requirements / acceptance: R10; AC16 (configuration baseline only; runtime proof in 1.2 and sharing proof in 3.2). Prerequisite for the remaining requirements.
Depends on: None; wait for the owner's scaffold rather than creating one automatically.
Review boundary: setup handoff and baseline evidence, not runtime architecture.

Expected files:

- Owner-provided `PROJECT`, app entry point, and initial SwiftUI view, plus a native unit-test target either supplied by the owner or added within the existing scaffold under the explicit request recorded in `evidence/changes.md`. These did not exist at authoring time.
- `plans/mvp/evidence/step-0.1.md` — concrete aliases, scheme/build procedure, owner environment, baseline observations.

Tasks:

- [x] Owner-created macOS SwiftUI app in this project directory has the app name and macOS 15.0 baseline; under the explicit request recorded in `evidence/changes.md`, the missing small native unit-test target was added to this existing scaffold. UI tests and unrelated generated examples were omitted; no second build system was introduced.
- [x] Inspect the resulting source/targets and applicable instructions. Record concrete `APP`, `TESTS`, `PROJECT` paths, selected scheme, actual macOS/Xcode versions, sandbox/signing settings, and any preexisting failure.
- [x] Record the available shell/Node-manager and alternative-command setup from local evidence, without installing tools or claiming runtime compatibility. The owner will select real projects through the app during later manual validation; upfront repository paths or listener permissions are not scaffold prerequisites.
- [x] Satisfy the verification and completion gate below, and record concise evidence.

Verification:

- Automated: no existing command is assumed. After scaffold handoff, derive any `xcodebuild` invocation from its actual project/workspace and scheme, from the project root, and record it in evidence. Do not add a CLI wrapper merely to standardize this.
- Manual: owner confirms the starter app runs from Xcode. Combine that observation with the native build/test checks above; a second UI-driven Build/Test pass is not required merely to repeat those results. Full window-close/reopen and process-lifetime behavior remains part of the Step 1.2 lifecycle requirement. Generated tests prove only the scaffold, not feature behavior.

Completion gate: supplied scaffold builds/launches on macOS 15 or later with app/test deployment targets set to 15.0, its actual paths and repeatable build/test procedure are known, and inherited failures are distinguished from future regressions. Missing scaffold/platform access blocks all application implementation.
Evidence location: [evidence/step-0.1.md](evidence/step-0.1.md).

Phase exit gate **G0**: after Step 0.1 checks, confirm the owner-created app builds/launches and its tooling/permissions can support a non-sandboxed current-user workflow. If Xcode selected App Sandbox by default, record it for the minimal configuration change in 1.1; do not pretend the empty shell already manages commands. Record G0 in `evidence/step-0.1.md` before dependent work or supervised approval to advance.

## Phase 1 — Real commands, logs, and owned process lifecycle

Outcome: users can save projects, safely run their actual development commands, keep supervision off the UI actor, and review bounded stale-run recovery without website-opening functionality yet.
Depends on: G0.
Review boundary: project settings, minimal useful UI, execution/cleanup ownership, narrow runner composition, and best-effort recovery; no URL guessing or browser action.

### Step 1.1 — Persist project folders and editable commands

Requirements / acceptance: R1, R10, R11; AC1, AC3 (input validation portion; execution errors/alternate commands in 1.2), AC18.
Depends on: Step 0.1 and G0.
Review boundary: saved settings and project-selection UI, no process execution.

Expected files:

- `APP/Projects/Project.swift`, `APP/Projects/ProjectStore.swift` — simple Codable settings and stable project identity.
- `APP/App/ContentView.swift` — split-view composition, selection/folder-picker coordination, and the small store-error banner.
- `APP/Projects/Views/ProjectSidebar.swift` — project list/row and Add Project action.
- `APP/Projects/Views/ProjectDetailView.swift` — selected-project `Execution` and `Output` sections plus the per-project settings-sheet entry point.
- `APP/Projects/Views/ProjectSettingsSheet.swift` — captured-project read-only identity/folder, command draft with Save/Cancel, and bottom removal confirmation.
- `APP/App/devManagerApp.swift` — initialize one store, not a background auto-starter.
- `APP/Assets.xcassets/` — existing root asset catalog, unchanged.
- `TESTS/ScaffoldSmokeTests.swift`, `TESTS/Projects/ProjectStoreTests.swift` — existing native tests organized under the test source root.
- `PROJECT` app-target configuration — apply the approved minimal move of App Sandbox disablement into Step 1.1; preserve signing, hardened runtime, deployment, and unrelated settings.

Tasks:

- [x] Add folder registration with explicit directory/nonempty-command validation and editable `pnpm dev` default; do not require Git metadata or install dependencies.
- [x] Persist project identity, folder, and command in app-owned settings; handle read/write errors visibly without replacing unreadable data with a silent destructive overwrite.
- [x] Connect the minimal project list/detail UI; restoring settings never starts a command. Keep execution controls absent/disabled until 1.2 supplies a safe runner.
- [x] Add stable-ID app-entry removal with native confirmation; leave the selected entry and disk contents unchanged on cancellation or save failure, disable removal in read-only mode, and explicitly leading-align the command field.
- [x] Reorganize the existing source and test files into the approved folders, including the exact `devManagerApp.swift` filename, without changing command-layout behavior or store/model semantics.
- [ ] Satisfy the verification and completion gate below, and record concise evidence.

Verification:

- Owner-approved only: use the native build procedure from 0.1 and, if explicitly approved, run only small native store checks for persisted removal, unchanged folder/file bytes, failed-save retention, and safe unknown-ID handling; no persistence testing framework is added and no hosted test command is automatic.
- Manual-first: add a safe folder, edit its command, relaunch, and inspect retained values. Try blank command and missing/non-directory folder. No command should run, and the user's folder contents remain unchanged. For a missing registered folder, recover by removing the app entry and re-adding the correct folder rather than switching it in place. Confirm the command field is leading-aligned, cancel removal, then confirm removal and verify the folder/files remain. Use an isolated app settings copy for any corrupt-data check; do not corrupt the owner's live configuration.
- Source proof: inspect the detail view and store implementation to confirm the native confirmation text, stable-ID save-before-memory ordering, read-only disablement, selection reconciliation, and absence of folder-deletion or folder-switch calls. The owner owns the UI walkthrough; source inspection is implementation evidence only.

Completion gate: AC1 and AC18 are observable without any execution service; invalid input is recoverable and settings survive normal relaunch. The verification task remains pending until the owner performs the add/edit/relaunch/blank/remove/cancel checks.
Evidence location: [evidence/step-1.1.md](evidence/step-1.1.md).

### Step 1.2 — Start and stop an isolated real command with live output

Requirements / acceptance: R2, R3, R5, R10; AC2, AC3 (execution portion), AC4 (Start/Stop isolation), AC6 (concurrent capture and bounded logs), AC16 (current-user runtime configuration; artifact check in 3.2).
Depends on: Step 1.1.
Review boundary: real launch, per-run ownership, live output, and bounded Stop as one atomic increment.

Expected files:

- `APP/Runs/ProjectRunner.swift`, `APP/Runs/RunState.swift`, `APP/Runs/LogBuffer.swift` — per-project run identity, owned process lifecycle, bounded output.
- `APP/Runs/ShellEnvironment.swift` — minimal owner-validated shell/environment loading.
- Optional narrow `APP/Runs/ProcessLauncher.swift` or native launch wrapper only if required for process-group control; corresponding `PROJECT` target membership.
- Project detail/root views — Start/Stop, separate process status, live logs and visible errors.
- `PROJECT` settings/entitlements — App Sandbox is disabled for this workflow by the approved Step 1.1 correction; no global network/TLS exceptions or privilege helpers.

Tasks:

- [x] Add a unique run identity and serialized lifecycle per project. Launch from the configured directory under the user's shell/environment; validate missing tools and report startup/initialization failures. Keep shell bootstrap diagnostic output distinct from dev-command output where practical. When project removal is connected to a runner, disallow unregistering projects that are active or stopping; removal must never forget a managed run.
- [x] Establish a dedicated owned process group before executing the command, with command-shell job control disabled or equivalent demonstrated containment. If Foundation cannot guarantee this, use a small native spawn wrapper rather than assuming `Process.terminate()` kills descendants. Do not return a successful launch unless ownership is established.
- [x] Implement graceful interrupt/terminate/kill escalation using the finite budgets above, retain ownership through launcher exit while known children remain, and never signal unrelated processes or recycled identifiers. Block duplicate Start and new runs while known cleanup is unresolved.
- [x] Drain both pipes concurrently away from UI work, preserve stream/run identity, and keep a bounded per-run log buffer with truncation feedback; retain it after Stop or exit until the next Start, which begins a fresh buffer. Close unused stdin rather than offering terminal interaction.
- [x] Wire real Start/Stop and errors atomically; keep window close/reopen and normal app termination with owned cleanup in this lifecycle boundary so it cannot strand live runs through ordinary Quit. There is no separate Restart UI/API: a user can Stop and then Start manually after cleanup.
- [x] Audit `POSIX_SPAWN_CLOEXEC_DEFAULT` support and use it where available, while explicitly auditing stdin/stdout/stderr and private-readiness inheritance before declaring 1.2 finished. The audit must show that only intended descriptors survive spawn and that the explicit file actions remain correct; do not claim this task complete from the current launcher alone.
- [x] Keep process launch/setup and blocking supervision off the main actor, while rendering and published run state remain main-actor-owned. Preserve `duplicateStart`, `pendingStartStop`, project-Remove, and Quit ownership safety across every `await`; do not allow an asynchronous handoff to forget or duplicate a run.
- [ ] Satisfy the verification and completion gate below, and record concise evidence.

Verification:

- Focused, owner-approved only: review the `ProcessLauncher` descriptor-inheritance audit and run small run-state checks for duplicate Start, Stop immediately after Start/await, pending start/Stop, active-or-stopping removal, and Quit while setup/cleanup is pending. No hosted test command is automatic and no process-orchestration harness is added.
- Manual, owner-owned: launch the built `.app` from Finder and start a real `pnpm dev` project. Confirm correct directory/tool version/output without editing shell files. Start a second project and separately owned unrelated server, stop the first, and verify only its children/listeners disappear. Try another installed package-manager command or ordinary shell command, a missing executable, and an initialization failure. A short-lived launcher with a still-running ordinary child must remain safely owned rather than enabling a second run. Quit the app and observe cleanup. These behavior checks remain pending until the owner performs them.

Completion gate: a useful Start/Stop/log loop works from a GUI launch, stdout/stderr both drain, ordinary children are covered, unrelated-process isolation is demonstrated, descriptor inheritance is audited, and actor-boundary ownership checks are focused and safe. If isolation, environment loading, descriptor inheritance, or async ownership is unresolved, do not advance with an unsafe launcher.
Evidence location: [evidence/step-1.2.md](evidence/step-1.2.md).

### Step 1.2a — Separate process supervision from main-actor UI state

Requirements / acceptance: R2, R3, R4, R5; AC2, AC4, AC5, AC6, AC14 (composition and ownership safety only; no new product behavior).
Depends on: Step 1.2 and its existing ownership/isolation gate; must complete before Step 1.4.
Review boundary: a narrow decomposition of the existing runner so OS launch/setup, blocking supervision, and process identity checks are separate from `@MainActor` rendering/state publication. Do not introduce a framework, dependency-injection layer, protocol forest, or a mandatory `AsyncStream` product API when a simple bounded callback is sufficient.

Expected files:

- `APP/Runs/ProcessSupervisor.swift` — new narrow owner of off-main-actor launch/setup and blocking process supervision, using the existing launcher and bounded callbacks.
- `APP/Runs/ProjectRunner.swift`, `APP/Runs/RunState.swift`, `APP/Runs/ProcessLauncher.swift`, `APP/Runs/LogBuffer.swift` — existing run identity, UI projection, launch boundary, and extracted log assembly adapted without changing lifecycle semantics.
- `APP/App/AppLifecycle.swift` and existing project execution views only if needed to keep app termination, controls, and rendering on the main actor as one atomic group.
- `TESTS/Runs/ProjectRunnerTests.swift` — optional owner-approved focused state checks only; no new test infrastructure.

Tasks:

- [x] Extract the bounded process-supervision responsibility from `ProjectRunner` into `ProcessSupervisor` without changing the current process-group ownership, output, shutdown, or error contract.
- [x] Keep SwiftUI rendering and published state transitions on `@MainActor`; keep process launch/setup, waits, identity inspection, and blocking cleanup off-main-actor. Use the smallest callback/result boundary that preserves backpressure and cancellation.
- [x] Preserve `duplicateStart`, `pendingStartStop`, active-or-stopping Remove, and Quit ownership safety across `await` boundaries. A run remains owned until confirmed cleanup; stale completions cannot clear a newer run or re-enable a conflicting control.
- [x] Verify the decomposition as a composition change only: existing Step 1.2 isolation, output, cleanup, and app-lifetime gates remain required and no spec behavior is broadened.
- [x] Satisfy the verification and completion gate below, and record concise evidence.

Verification:

- Focused, owner-approved only: source/concurrency review plus small state checks for duplicate Start, pending Start/Stop, removal while active or stopping, Quit during setup/cleanup, and stale completion ordering. Do not run a broad suite, add a harness, or make hosted tests automatic.
- Manual, owner-owned: repeat only the narrow Start/Stop/Quit ownership observations needed to show the decomposition preserves Step 1.2 behavior; do not claim the existing historical runtime evidence proves this refactor.

Completion gate: process supervision is independently reviewable off the main actor, UI/state publication remains main-actor-owned, and all existing Step 1.2 ownership/isolation gates still pass. This step adds no user-visible behavior and remains unchecked until focused owner-approved review and manual composition checks occur.
Evidence location: [evidence/step-1.2a.md](evidence/step-1.2a.md).

### Step 1.4 — Best-effort stale-run recovery journal

Requirements / acceptance: R12; AC19.
Depends on: Step 1.2a (and the existing Step 1.2 gate); complete this bounded recovery increment before assessing G1 or starting Phase 2.
Review boundary: one warning-only, best-effort startup recovery component for verified stale managed process groups. No adoption/reconnect, crash-instant cleanup, watchdog, lock, owner-identity metadata, environment marker, PTY, log archive, or concurrent-instance support.

Expected files:

- `APP/Runs/RunJournal.swift` — one atomic JSON Application Support journal entry per run with exactly the recovery metadata needed: `{projectID, pid, pgid, OSprocessStartTime}`.
- `APP/Runs/ProcessIdentity.c/.h` — existing narrow libproc identity reader, created-child capture, and bounded direct-child query used by recovery; no persisted child records.
- Existing `APP/Runs/ProcessSupervisor.swift` or `APP/Runs/ProcessLauncher.swift` — minimal record-after-spawn and confirmed-cleanup removal calls; do not add a second process owner.
- Existing `APP/App/AppLifecycle.swift` — minimal launch-time inspection and warning diagnostics, without turning recovery into a UI gate.
- Optional `TESTS/Runs/RunJournalTests.swift` only if the owner explicitly approves isolated metadata fixtures; no new folder or complex harness.

Tasks:

- [x] Write one journal entry atomically after spawn as soon as practical and remove it only after confirmed stop. Do not write an intent record before exec; accept the spawn-to-write window. Journal I/O failure logs the problem and never deletes project settings or stops a process that is not positively owned.
- [x] On launch, recover only when the PID is alive, its OS process start time matches, and the PID is still leader of the recorded positive PGID. Before signaling, inspect the current descendant tree and capture only positively attributed additional group leaders; recheck each captured leader immediately before SIGTERM/SIGKILL and signal those groups before the launcher root. Recheck the root through discovery and each root signal, use the existing finite TERM/KILL waits, and leave unverifiable groups alone. A recovery orphan is not the app's direct child and must not go through a child-only `waitpid` routine.
- [x] Drop dead-PID or start-time-mismatched records without signaling. Leave ambiguous permission, group, or identity cases alone with a diagnostic warning; do not silently require a UI warning. Deliberately drop a dead leader with live children rather than attempting recovery.
- [x] State explicitly that concurrent app instances are unsupported; do not add locking or owner-identity metadata. Keep this one bounded component and do not promise an exact line count.
- [x] Satisfy the verification and completion gate below, and record concise evidence.

Verification:

- Manual-first, owner-owned: use an owner-approved controlled start/stop/relaunch walkthrough for one managed server and inspect warning-only behavior. Use isolated metadata fixtures only if the owner approves; cover confirmed cleanup removal, dead/mismatched metadata with no signals, ambiguous metadata left alone, identity recheck before each signal, and journal I/O failure without settings loss. No automatic app launch, hosted test command, live-process recovery test, or new harness is authorized in this planning increment.
- Optional focused check, only with explicit owner approval: exercise JSON atomicity/identity decision logic with isolated metadata fixtures. It does not prove OS signal safety or replace owner behavior checks.

Completion gate: AC19 is manually reviewed as best-effort only; normal cleanup removes its entry, positive identity is required before each signal, ambiguous/stale metadata is not signaled, and all existing process ownership/lifecycle gates remain intact. Do not broaden G1 or claim guaranteed crash cleanup.
Evidence location: [evidence/step-1.4.md](evidence/step-1.4.md).

Phase exit gate **G1**: after Steps 1.2a and 1.4 checks, use one owner-approved Xcode build check and compose the existing Step 1.2 behavior: two saved projects, concurrent logs, independent Start/Stop, window close/reopen, normal Quit, and the bounded stale-run recovery review. Confirm no website button guesses a port yet and no unrelated listener is terminated. Include composition of the supervisor and recovery journal without demanding a broad suite or repeating every focused check. Record G1 in `evidence/step-1.4.md` before Phase 2 or supervised approval to advance.

## Phase 2 — Automatic current-run localhost discovery

Outcome: websites become openable using their current responding local address, including dynamic port rollover and commands that do not announce a URL.
Depends on: G1.
Review boundary: URL candidate parsing, owned listeners, bounded web probes, and browser UI. No framework-specific project modification or fixed-URL setting.

### Step 2.1 — Extract and normalize local URL candidates

Requirements / acceptance: R6, R7; AC11; AC7/AC8 (output interpretation only; real readiness/actions in 2.2/2.3).
Depends on: G1, after Step 1.4 and the existing Step 1.2/1.2a lifecycle behavior.
Review boundary: pure streaming parser and candidate model; candidates are not website actions yet.

Expected files:

- `APP/Discovery/LocalURLCandidate.swift`, `APP/Discovery/LocalURLParser.swift` — stream-aware extraction, filtering and normalized identity in the approved feature-oriented layout.
- `TESTS/Discovery/LocalURLCandidateTests.swift` — table-driven native cases using the supplied output shapes.
- Existing `TESTS/Runs/ProjectRunnerTests.swift` — constructor argument alignment with the previously added process start-time identity; no new process-test behavior or execution.

Tasks:

- [x] Parse each run's stdout/stderr incrementally, carrying incomplete text/control sequences across chunks and stripping ANSI formatting for detection without discarding useful log output.
- [x] Accept only HTTP/HTTPS on parsed `localhost`, `127.0.0.1`, or `::1`; reject LAN/public/deceptive hosts and non-web schemes. Preserve meaningful scheme/path; normalize the omitted root slash and repeated announcements.
- [x] Add a compact table of Vite/Next.js examples, ANSI/chunk splits, loopback forms, Network/public/documentation URLs, deceptive hosts, and path-preserving deduplication cases. No snapshot or terminal-emulation harness.
- [x] Satisfy the core parser verification gate through the owner-approved integration baseline and record concise evidence; native case execution remains unrun and is not claimed passed.

Verification:

- Owner-approved only: native `LocalURLCandidateTests` execution remains optional and unchecked. The test cases compiled, but were not executed; parser core was validated through the owner's integration cases rather than a native-test execution gate. Extra unit cases remain unrun. No Product > Test action is automatic.
- Manual-first: review the test literals against the supplied screenshots. The owner integration cases prove interpretation only in the observed flows, not a listening server or browser behavior for every table row.

Completion gate: AC11's parser policy is implemented and compiled, while native parser execution remains optional/unpassed; candidates cannot independently enable Open or bypass ownership/readiness checks.
Evidence location: [evidence/step-2.1.md](evidence/step-2.1.md).

### Step 2.2 — Attribute listeners and verify local web readiness

Requirements / acceptance: R6, R7, R8, R9; core discovery/readiness portions of AC13, AC14, and AC15, composed in 2.3. AC10 and AC17 are implemented compatibility capabilities whose live verification is deferred from the initial MVP baseline.
Depends on: Step 2.1.
Review boundary: automatic discovery engine integrated into current-run state, with no browser action before proof.

Expected files:

- `APP/Discovery/OwnedListenerInspector.swift` — owned process-group/descendant enumeration and machine-readable TCP listener inspection.
- `APP/Discovery/SiteDiscovery.swift`, `APP/Discovery/LocalSiteProbe.swift`, `APP/Discovery/LocalSite.swift` — candidate reconciliation, local-only probes, cancellation, and site-state values.
- `APP/Discovery/Views/SiteStatusView.swift` — read-only status for owner validation; no browser actions.
- Runner/state and log-consumer integration; existing `TESTS/Runs/ProjectRunnerTests.swift` — optional owner-approved stale-result assertions.

Tasks:

- [x] Inspect listeners using bundled system `lsof` machine-readable output and owned live process identities, or a comparably narrow native implementation if the scaffold/platform requires it. Keep inspection off the UI thread, bounded/cancellable, and limited to tracked process groups/ordinary descendants; do not discover by globally selecting a port. Revalidate ownership before promoting any candidate, including log-announced URLs.
- [x] Combine parser candidates with listener evidence. Derive loopback targets for owned wildcard listeners, prefer an announced scheme/base path, deduplicate alias/root fallback choices for the same endpoint, and avoid treating identifiable inspector/WebSocket-only ports as websites.
- [x] Probe candidates locally using finite deadlines, limited concurrency, and default TLS trust. For socket-only unknown protocols try bounded HTTP/HTTPS checks rather than assuming HTTP. Do not follow nonlocal redirects or downgrade an explicitly advertised HTTPS URL. An actual HTTP response, including 404, means responding; a bare socket does not.
- [x] Feed discovering/responding/no-site/error information into the run's website state, separate from process state. Continue scanning while active after the no-site notice; if listener inspection fails, show diagnostics without guessing an address or disabling process controls. A responding site is startup-verified rather than continuously health-monitored; the owner accepted startup-only checking without ongoing HEAD requests.
- [x] Cancel probes/scans and immediately invalidate results on Stop/exit/subsequent Start. Check project/run identity and current ownership before accepting results. The owner confirmed the delayed-start/Stop/fresh-run walkthrough; optional unit-state extensions were not added or executed.
- [x] Satisfy the owner-approved core verification gate below and record concise evidence; deferred compatibility fixtures are not marked passed.

Verification:

- Owner-approved only: use the native build and focused existing parser/state checks, if explicitly approved, to assert an old run's successful probe cannot promote a candidate. Stub only the probe completion if necessary; do not build a fake networking platform or run hosted tests automatically.
- Manual-first core baseline: use the owner's Vite/Next/Astro HTTP projects and delayed wrapper to validate actual current-run URLs, readiness, startup-only probes, and Stop/fresh-run stale-state invalidation. A missing URL must not fail an otherwise valid running command. Silent-server, multi-site, trusted-HTTPS, and expanded response fixtures are deferred compatibility checks, not initial completion gates. Default TLS validation and refusing probe redirects remain source-reviewed safeguards, not claims of additional live fixture execution.

Completion gate: the owner-approved initial HTTP baseline composes actual responding owned endpoints with delayed startup and Stop/fresh-run invalidation. The recorded 2.3 walkthrough closes this core gate. AC10 and AC17 remain unverified compatibility checks; certificate or silent-server fixtures are not blockers. Default trust, local-only probes, and current-run ownership guards remain required.
Evidence location: [evidence/step-2.2.md](evidence/step-2.2.md).

### Step 2.3 — Open the correct local site and validate dynamic ports

Requirements / acceptance: R6, R7, R8, R9; AC7, AC8, AC9, AC12; AC13/AC14/AC15/AC17 (remaining integrated website-action portions).
Depends on: Step 2.2.
Review boundary: user-visible website states/browser choices composed with the real runner; no custom primary-site guessing.

Expected files:

- `APP/Projects/Views/ProjectDetailView.swift` — parent-owned `Execution` and `Output` section boundaries; project command/removal controls live in the per-project settings sheet.
- `APP/Projects/Views/ProjectSettingsSheet.swift` — approved per-project settings modal and app-entry-only removal confirmation.
- `APP/Discovery/Views/SiteStatusView.swift` — website status/action row content within Execution, including single/multiple URL choices.
- `APP/Projects/Views/ProjectOutputView.swift` — bounded terminal output rendering within the parent-owned Output section.
- Run/discovery state integration — last-moment run validity check and default-browser opening via native macOS API.

Tasks:

- [x] Show process lifecycle and website discovery separately. Enable one Open action for one responding website, URL-labeled choices for multiple distinct websites, and informative no-site/probe errors without marking a running command failed.
- [x] Open the selected current-run URL in the default browser. Recheck run validity at action time; clear choices immediately on Stop/exit/subsequent Start and report browser-open failures without changing the process.
- [x] With the owner, close the initial core baseline across the current Vite, Next.js, and Astro HTTP flows: one needed local website per project, printed local URL discovery, dynamic ports, owned readiness/browser flow, delayed startup, and Stop/start stale-state invalidation. A valid running command with no discovered URL remains manageable. This records the owner's walkthrough/report, not an agent-run test or deterministic micro-race proof.
- [x] Record the owner-approved core verification and the prior positive core UI handoff in the evidence below; close Step 2.3's initial baseline without changing the deferred compatibility checks.

Verification:

- Owner-approved core report: the owner followed the delayed-start procedure (`DEV_SETUP_DELAY_MS=12000 pnpm dev`, Start, Stop after about one second, then wait) and the final Stop/stale-state walkthrough, including a fresh Start that did not inherit old Ready/Open state. The owner explicitly confirmed, "yep that all works as expected." This is owner-reported approval; no agent app launch, browser/network check, native test, or deterministic micro-race proof is claimed.
- Deferred checks remain unchecked and are not part of the initial baseline gate: AC10 silent-server/socket fallback, AC12 multisite choice behavior, and AC17 trusted-local-HTTPS acceptance. Additional AC15 response/HTTPS fixtures remain deferred. The existing default TLS trust, nonlocal-redirect guard, exit invalidation, and missing-URL/non-failing-process behavior remain implementation/source-reviewed safety and state invariants.

Completion gate: the initial baseline composes current-run HTTP discovery, dynamic-port/browser flow, owned readiness, delayed startup, and Stop/stale invalidation for the owner's Vite/Next/Astro coverage. AC10, AC12, and AC17 are explicitly not passed and are not G2/G3 release blockers for this initial baseline. Parser native execution and expanded response fixtures remain unverified; no broader compatibility claim is made.
Evidence location: [evidence/step-2.3.md](evidence/step-2.3.md).

Phase exit gate **G2**: the initial-baseline portion of G2 is recorded in `evidence/step-2.3.md` from the owner's accepted core walkthrough and prior positive core UI handoff. It covers current-run HTTP URL discovery, dynamic ports, owned readiness/browser flow, delayed startup, and Stop/stale invalidation; it does not require the unchecked AC10, AC12, or AC17 compatibility checks. This is not release approval. Socket fallback, multisite, and trusted HTTPS remain implemented but unverified compatibility checks.

## Phase 3 — Owner acceptance and optional sharing boundary

Outcome: owner reconciliation of the initial baseline, with a separate artifact check before any personal distribution.
Depends on: G2 initial baseline; owner time and representative projects as needed. Trusted-local-HTTPS, multisite, and silent-server fixtures are not prerequisites for the initial baseline. Signing/notarization credentials block sharing work only.
Review boundary: composition/acceptance and minimal owner-driven artifact preparation, not a polish pass or new testing platform.

### Step 3.1 — Perform the owner's integrated MVP walkthrough

Requirements / acceptance: R1–R12; the accepted initial-baseline portions of AC7–AC9, AC13, AC14, and the existing contracts mapped below, plus prior evidence for the remaining core requirements. AC10, AC12, and AC17 remain explicitly deferred/unpassed; expanded AC15 fixtures remain deferred. AC16 artifact suitability remains in 3.2, separate from local functional proof.
Depends on: Step 2.3 and G2 initial baseline.
Review boundary: compact final reconciliation and targeted fixes within this plan's scope. Reuse the accepted Step 2.3 core proof rather than repeating the entire matrix; material design changes require owner agreement.

Expected files:

- `plans/mvp/evidence/step-3.1.md` — concise cross-cutting acceptance summary linking prior step evidence.
- Only the already scoped app/test files for regressions discovered during acceptance; fix and recheck the affected earlier gate before counting it as resolved.

Tasks:

- [x] Reconcile the existing compile/source evidence and the owner's reported core walkthrough instead of starting a new test round, Finder pass, or broad compatibility suite.
- [x] Carry forward the accepted Step 2.3 baseline and the latest Step 1.4 owner acceptance, distinguishing owner-reported behavior from agent-run checks and preserving earlier gate history.
- [x] Reconcile every acceptance ID against its owning evidence, explicitly retaining the deferred/unpassed AC10, AC12, AC17, and expanded AC15 checks. Do not convert unreported manual matrices, native-test execution, or compatibility fixtures into passes.
- [x] Record the owner's latest velocity direction and approval context, and close the core owner-acceptance reconciliation without claiming release, sharing, or artifact approval.

Verification:

- Documentation-only reconciliation: reuse the existing compile/source evidence and owner-reported walkthroughs in `evidence/step-2.3.md` and `evidence/step-1.4.md`. No new app launch, browser/Finder action, process check, native test, hosted test, or broad suite is required or claimed.
- The final exported-artifact Finder launch, signature/notarization, credentials, and sharing checks remain Step 3.2 work and are not part of this gate.

Completion gate: the Step 3.1/G3 core reconciliation is complete using the existing evidence. The initial baseline may reuse the accepted Step 2.3 core proof and Step 1.4 owner acceptance; it does not require the deferred AC10, AC12, or AC17 checks or the expanded AC15 fixture matrix. Those IDs remain unchecked/unpassed, as do any unreported manual matrices and optional native-test executions. AC16 artifact suitability and all release/sharing approval remain separate Step 3.2/G-share work; no release approval is implied.
Evidence location: [evidence/step-3.1.md](evidence/step-3.1.md).

### Step 3.2 — Check a direct-distribution artifact before sharing

Requirements / acceptance: R10; AC16 (artifact/pre-sharing portion). Signing/notarization is the recommended release path, not permission to distribute.
Depends on: Step 3.1 and G3 for a feature-complete sharing candidate; owner-controlled signing credentials and explicit approval for credential use/notarization submission. This step is not required to demonstrate a local working build.
Review boundary: one manually prepared app artifact and verification; no CI, installer/updater service, publication, or automated credential management.

Expected files:

- Existing `PROJECT` signing/entitlement configuration only where necessary and owner approved.
- An owner-chosen export/archive outside source control; do not commit credentials, private keys, certificates, or built app bundles.
- `plans/mvp/evidence/step-3.2.md` — artifact identity, checks and actual approval boundaries, without secrets.

Tasks:

- [ ] With the owner, inspect the final current-user/non-sandboxed configuration and prepare an app through the actual Xcode archive/export flow. Use the owner's chosen identity; do not infer one from account availability.
- [ ] If the owner approves and supplies credentials, sign/notarize the app and staple as appropriate using the tooling/workflow present on their machine. Record the actual invocation or Xcode action in evidence; no submission occurs merely because this plan exists.
- [ ] Owner launches the exported app through Finder, ideally on a known tester's Mac, and confirms normal opening plus one start/discover/open/stop cycle with that machine's installed tools. Compare artifact identity to the build whose evidence is cited.
- [ ] Satisfy the verification and completion gate below, and record concise evidence; do not send or publish the artifact automatically.

Verification:

- Automated: commands, if used, are derived from the owner's actual signing/export tools and artifact path and recorded at execution. Signature/notarization assessment proves artifact suitability, not functional acceptance.
- Manual: owner checks the exported artifact opens normally through Finder without disabling platform security, uses no elevation, and can manage a local project with its installed toolchain. Missing credentials/tester access blocks the relevant sharing check, not earlier local development.

Completion gate: **G-share** requires a checked artifact, current-user runtime behavior, and owner-controlled distribution decision; signature acceptance alone does not replace G3. No sharing or release is performed by this step.
Evidence location: [evidence/step-3.2.md](evidence/step-3.2.md).

Phase exit gates: **G3 core reconciliation is closed in `evidence/step-3.1.md`** using the existing acceptance map and owner-reported evidence; it is not release approval. If the owner proceeds toward sharing, assess **G-share** only after the separate Step 3.2 checks and record it in `evidence/step-3.2.md`. Supervised approvals happen only after the applicable gate is assessed.

## Final acceptance

Each row names the owning proof, not a progress field. G3 reconciles these notes without creating another acceptance checklist. Earlier partial coverage is completed only at the gates named here.

| Spec acceptance ID | Owning step / gate | Verification and expected result | Evidence location |
| --- | --- | --- | --- |
| AC1 | 1.1; G3 relaunch composition | Saved folder/command persist; restore never executes a command. | [step-1.1](evidence/step-1.1.md), [G3](evidence/step-3.1.md) |
| AC2 | 1.2; G3 Finder launch | Owner's real command/toolchain works from GUI environment; both streams visible; no repository/profile modification. | [step-1.2](evidence/step-1.2.md), [G3](evidence/step-3.1.md) |
| AC3 | 1.1 + 1.2 | Alternate installed command works; invalid folder/command/tool failure is visible and recoverable. | [step-1.1](evidence/step-1.1.md), [step-1.2](evidence/step-1.2.md) |
| AC4 | 1.2 + 1.2a; G1/G3 isolation | Stop cleans owned children; a later manual Start begins only after cleanup; other project and unrelated server survive; supervision/state composition preserves ownership. | [step-1.2](evidence/step-1.2.md), [step-1.2a](evidence/step-1.2a.md), [G1](evidence/step-1.4.md), [G3](evidence/step-3.1.md) |
| AC5 | 1.2 + 1.2a; G1/G3 lifetime | Window close preserves work; Quit performs bounded escalation and exposes cleanup failure through the existing supervisor/state boundary. | [step-1.2](evidence/step-1.2.md), [step-1.2a](evidence/step-1.2a.md), [G1](evidence/step-1.4.md), [G3](evidence/step-3.1.md) |
| AC6 | 1.2; G1/G3 composition | Heavy stdout/stderr stays bounded/inspectable without freezing controls; logs remain available after Stop or exit until the next Start, which begins a fresh bounded buffer. | [step-1.2](evidence/step-1.2.md), [G1](evidence/step-1.4.md), [G3](evidence/step-3.1.md) |
| AC7 | 2.3; G2 initial baseline | Owner-reported Vite HTTP flow produces one verified local Open action; this is not an agent-run test claim. | [step-2.3](evidence/step-2.3.md) |
| AC8 | 2.3; G2 initial baseline | Owner-reported Next.js HTTP flow produces one local Open action, excluding Network URL; this is not a universal framework claim. | [step-2.3](evidence/step-2.3.md) |
| AC9 | 2.3; G2 initial baseline | Owner-reported current/dynamic-port flow opens the current run rather than an old/unrelated port. | [step-2.3](evidence/step-2.3.md) |
| AC10 | 2.2; deferred from G2 initial baseline | Silent owned HTTP/socket fallback remains implemented but unverified and is not an initial-baseline release blocker. | [step-2.2](evidence/step-2.2.md), [G2](evidence/step-2.3.md) |
| AC11 | 2.1 | Parser cases compiled but were not executed; parser core was validated through owner integration cases and extra unit cases remain unrun. | [step-2.1](evidence/step-2.1.md) |
| AC12 | 2.3; deferred from G2 initial baseline | Multisite choices remain implemented but unverified and are not an initial-baseline release blocker. | [step-2.3](evidence/step-2.3.md) |
| AC13 | 2.2 + 2.3; initial baseline portion | Delayed startup and graceful no-site behavior remain manageable; non-web is not a first-class MVP workflow/category. | [step-2.2](evidence/step-2.2.md), [step-2.3](evidence/step-2.3.md) |
| AC14 | 1.2 + 1.2a + 2.2 + 2.3; G1/G3 composition | Owner-reported Stop/stale-state walkthrough passes for the core baseline; this is not deterministic micro-race proof. | [step-1.2](evidence/step-1.2.md), [step-1.2a](evidence/step-1.2a.md), [G1](evidence/step-1.4.md), [step-2.2](evidence/step-2.2.md), [step-2.3](evidence/step-2.3.md) |
| AC15 | 2.2 + 2.3; partial core/invariant coverage | Exit invalidation, default TLS trust, and nonlocal-redirect safety remain implemented/source-reviewed; additional response and HTTPS fixtures are deferred. | [step-2.2](evidence/step-2.2.md), [step-2.3](evidence/step-2.3.md) |
| AC16 | 0.1/1.2 runtime; 3.2 G-share | Non-sandboxed current-user workflow and checked direct-distribution artifact before sharing. | [step-0.1](evidence/step-0.1.md), [step-1.2](evidence/step-1.2.md), [G-share](evidence/step-3.2.md) |
| AC17 | 2.2 + 2.3; deferred from G2 initial baseline | Trusted local HTTPS remains implemented but unverified and is not an initial-baseline release blocker. | [step-2.2](evidence/step-2.2.md), [step-2.3](evidence/step-2.3.md) |
| AC18 | 1.1; G3 relaunch/removal composition | Command is leading-aligned; cancel is nonmutating; confirmed stable-ID removal changes only app settings; failed save retains entry/selection; folder/file bytes remain unchanged. | [step-1.1](evidence/step-1.1.md), [G3](evidence/step-3.1.md) |
| AC19 | 1.4; G1/G3 recovery composition | One atomic post-spawn journal entry supports warning-only recovery only after positive PID/start-time/PGID checks; identity is rechecked before each signal; normal confirmed stop removes the entry; stale/mismatched/ambiguous records are not signaled; concurrent instances and orphan reaping are unsupported. | [step-1.4](evidence/step-1.4.md), [G1](evidence/step-1.4.md), [G3](evidence/step-3.1.md) |

Final regression scope: Step 3.1 reuses the existing owner-reported walkthrough and compile/source evidence rather than opening a new audit or retesting round. Future regressions may use one owner-approved native app build and optional focused native checks only with explicit approval; do not demand a nonexistent workspace-wide suite or hosted-test infrastructure. Artifact proof remains a separate Step 3.2/G-share boundary and does not imply permission to distribute.

## Rollback and recovery

- Revert complete step-sized implementation/UI/target-membership groups together, in reverse dependency order. First stop owned runs and verify cleanup before replacing the app. Never revert a runner while leaving controls that assume its newer lifecycle contract.
- Preserve the owner's scaffold, project folders, shell setup, and app settings. Before settings-format changes or isolated corruption checks, copy only app-owned settings to an owner-approved safe location; no destructive migration is planned. Do not delete settings merely to hide decode errors.
- On failed Stop, retain known ownership and block a new run for that project until cleanup is confirmed or the owner resolves the incident. Display useful run/process information without suggesting a broad `killall` or killing whatever now occupies the port.
- Crash/Force Quit can leave orphan servers. Do not adopt or terminate them by remembered PID/port alone on relaunch. The owner may manually inspect and stop confirmed orphan processes; record only material consequences in evidence.
- Temporary collision/test servers are owned by the validation session, not automatically by the app; stop them explicitly after checking unrelated-server survival. No fixture may use elevation or overwrite real project files.
- Signing/notarization/account access requires owner approval; no certificate trust changes are planned. If an exported artifact fails validation, do not share it. Fix and recheck the artifact instead of weakening platform security or asserting earlier build evidence covers it.

## Planned deferred checks

- Full UI automation, CI, stress/soak infrastructure, and a broad shell/version-manager matrix are deferred until real usage justifies them. This does not waive the focused isolation, rollover, cancellation, and shutdown checks above.
- Crash-proof supervision, detached-daemon ownership, arbitrary external/container services, LAN/public/custom-domain discovery, custom HTTPS trust, and deep application health remain outside the governing MVP scope.
- Tester-machine launch and notarization assessment wait for owner access/approval in 3.2; they block suitability for sharing, not a local MVP demonstration. Trusted local HTTPS remains deferred/unverified compatibility coverage, not an initial-MVP completion blocker; default certificate validation must remain enabled.

Execution-time blockers, results, skipped/waived checks, and accepted deviations belong in the predetermined evidence notes, not mutable plan status. Stop after planning until the owner explicitly begins the next workflow.
