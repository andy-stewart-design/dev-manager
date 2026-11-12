# Machine Provisioning Spike Implementation Plan

## Governing source

- Governing spec: [spec.md](spec.md)
- Orientation: [overview.md](overview.md)
- User direction: keep the spike tight; the user is available for manual VM testing.

This plan is an execution contract. Routine plan edits are task-checkbox updates only. Scope, step IDs, dependencies, expected files, verification, and acceptance mappings require explicit user agreement to change; record actual approved changes in `evidence/changes.md`. A checkbox is not approval, final acceptance, or permission to release. In supervised execution, manual approvals remain in extension state.

## Execution constraints

- Paths are relative to this repository unless stated otherwise. Preserve unrelated work.
- Use the user's disposable Apple Silicon macOS 15+ VM, logged-in administrator account, graphical console, internet, and restorable snapshots. The user owns credentials, installer approvals, transfer of the app, and snapshot resets.
- **Live gate:** before any installation or shell-file modification, obtain the user's approval for that VM action. Never provision the development host as a substitute. If VM access or the user is unavailable, stop the affected verification and record the blocker; a build alone does not complete the step.
- Build on the development host, not inside the clean VM: installing Xcode in the VM would invalidate the clean-machine experiment. Verify a tester-only Debug artifact can open in the VM before changing its prerequisites. Do not use the normal Release archive workflow, which excludes the setup screen. If signing/transport prevents launch, resolve that test-delivery blocker with the user; do not add a production distribution project or disable macOS security globally.
- Keep the production runner and unrelated project environments unchanged. Use an explicit fnm command only for the fixture. Direct, noninteractive subprocess calls plus a simple setup model are sufficient; no generic provisioning layer, PTY, privileged helper, workflow persistence, or new test harness.
- New files under `dev-manager/` are automatically included by the existing project configuration. Guard spike types and entry points with `#if DEBUG`; do not add build configurations or alter Release distribution.
- No current green baseline is established. Source inspection found the existing build/test commands below; historical evidence does not prove today's checkout passes.
- Each completed step needs a short note at its predetermined evidence location: check, outcome, and material caveat. No empty evidence files during planning, transcripts, or duplicate progress ledgers. Failed, blocked, skipped, or waived gates remain unchecked; note rationale, approval owner, and next action. A waiver is not a pass.

### Existing verification commands

Run from the repository root on the development host, with full Xcode available. These are existing repository build/test invocations adapted only to dedicated derived-data paths, not a new harness.

**Debug build:**

```sh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
/usr/bin/xcodebuild -quiet -project dev-manager.xcodeproj \
-scheme dev-manager -configuration Debug \
-destination 'generic/platform=macOS' \
-derivedDataPath /tmp/dev-manager-provisioning-debug \
CODE_SIGNING_ALLOWED=NO build
```

**Release build:** the same invocation with `-configuration Release` and `-derivedDataPath /tmp/dev-manager-provisioning-release`.

**Existing regression suite, once at final integration:**

```sh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
/usr/bin/xcodebuild -project dev-manager.xcodeproj \
-scheme dev-manager -configuration Debug \
-destination 'platform=macOS,arch=arm64' \
-derivedDataPath /tmp/dev-manager-provisioning-tests \
CODE_SIGNING_ALLOWED=NO test
```

Unsigned builds establish compilation, not VM launchability. Prepare the tester-only Debug copy through the available local Xcode signing route if needed, without committing credentials. VM artifact delivery is separate from the commands above. A missing local Xcode or signing requirement is a blocker to the affected check, not evidence that the feature works.

## Phase overview and delivery boundary

| Phase | Outcome | Dependencies | Exit gate |
| --- | --- | --- | --- |
| 1 | Development-only setup can detect prerequisites and hand off to Apple's graphical installers. | User-provided VM and approvals. | Clean VM completes developer-tool/Homebrew setup; cancellation and recheck behave correctly. |
| 2 | A pinned runtime runs the fixture without shell edits; optional shell configuration is reversible; the DEBUG setup presentation is simplified without changing provisioning guards; the final provisioning source tree and shared command collection are focused without behavior changes; the approved per-tool presentation and final bounded diagnostics cleanup are recorded as the current UI contract. | Phase 1 exit gate. | Steps 2.1, 2.2, bounded 2.3 presentation, bounded 2.4 architecture, bounded 2.5 runner follow-up, bounded 2.6 per-tool UI, and bounded 2.7 cleanup are reviewed; fixture, repeat/relaunch, shell experiment, Release isolation, and existing regressions remain required. |

Delivery boundary: one feature-complete spike change for review; no publication or production rollout. Each step is a bounded review/revert unit. No separate atomic migration group is needed; each step remains buildable with its prerequisites.

## Phase 1 — Terminal-free system prerequisites

Outcome: a usable development-only setup surface and verified graphical installation path.
Depends on: VM availability, administrator access, and host Xcode. Step 1.1 establishes Debug artifact launchability before any VM installation.
Review boundary: setup detection and Apple-owned installation; no runtime installation or shell editing yet.

### Step 1.1 — Debug setup, detection, and Apple's developer tools

Requirements / acceptance: R1, R2, R3, R6; AC1 (developer-tools portion), AC3 (representative cancellation/retry), AC7 (debug gating portion). Homebrew coverage belongs to 1.2; ordinary-project/Release integration to the Phase 2 gate.
Depends on: None.
Review boundary: the new setup entry, read-only tool inspection, and one graphical prerequisite action.

Expected files:

- `dev-manager/App/ContentView.swift` — add a DEBUG-only setup sheet/button using the existing store and runner.
- `dev-manager/App/ProvisioningView.swift` — new DEBUG-only status/actions/diagnostics view.
- `dev-manager/App/ProvisioningModel.swift` — new DEBUG-only small model with direct process execution and detection; later steps extend this same model.

Tasks:

- [ ] Establish host build and clean VM baseline: app opens, administrator/OS/architecture are suitable, prerequisites are absent or explicitly recorded, and a clean snapshot exists. Record relevant pre-existing failures separately.
- [x] Add the setup screen and read-only tool checks. Choose one exact compatible Node/pnpm pair for later fixture use; detect selected developer tools, Homebrew, fnm, and that runtime without sourcing or editing user shell files.
- [x] Add explicit-consent Command Line Tools installation via `/usr/bin/xcode-select --install`. Treat return as request submission; provide manual Check again and functional developer-tool verification. Reuse usable full Xcode rather than forcing standalone tools.
- [x] Satisfy the verification and completion gate below and record concise evidence.

Verification:

- Build: run the Debug build. Source inspection confirms all new entry points/types are DEBUG-only and normal project Start has no provisioning dependency.
- Manual, with the user in the VM: capture the initial baseline, launch setup, request CLT, cancel Apple's dialog, and recheck. The tools remain missing and dependent actions remain unavailable. Retry, accept Apple's license/install UI, then Check again; only working tools count as ready. No Terminal or app password field is used.

Completion gate: a launchable Debug spike demonstrates real CLT cancellation/retry and functional completion in the VM; mere installer request success is insufficient.
Evidence location: [evidence/step-1.1.md](evidence/step-1.1.md).

### Step 1.2 — Official Homebrew package handoff and state recovery

Requirements / acceptance: R2, R3, R6; AC1 (Homebrew portion; composes with 1.1), AC4 (relaunch at an installed-prerequisite boundary).
Depends on: Step 1.1.
Review boundary: download/open/verify Homebrew and reconstruct setup state; no Node/pnpm installation.

Expected files:

- `dev-manager/App/ProvisioningModel.swift` — official package download/open and ordinary-user Homebrew verification.
- `dev-manager/App/ProvisioningView.swift` — consent, waiting, error, and Check again presentation.

Tasks:

- [x] Download the Apple Silicon package from Homebrew's official GitHub release location and open it with macOS Installer. Retain system signature/security checks; do not invoke a privileged command-line installer or create an alternate-user plist.
- [x] Verify `/opt/homebrew/bin/brew` executes as the console user. Report launch/download/verification failures without advancing. Reopening the app must inspect the machine again rather than automatically relaunch an external installer.
- [x] Satisfy the verification and completion gate below and record concise evidence.

Verification:

- Build: run the Debug build; inspect for absence of sudo, credential handling, privilege helpers, and security-check bypasses.
- Manual, approved VM action: download/open the package, observe normal Installer authorization, and finish installation. Before Check again, no success is inferred merely from opening Installer. After verification, quit/reopen the app and recheck: developer tools and Homebrew are reused with no new install request.

Completion gate: Homebrew is usable under the intended user after normal Installer completion and app relaunch, with no Terminal use.
Evidence location: [evidence/step-1.2.md](evidence/step-1.2.md).

Phase exit gate: after 1.2 verification and before Phase 2, confirm the composition of 1.1 and 1.2: both prerequisites work in the VM, one real installer cancellation/retry was observed, and relaunch reconstructs prerequisite state. Reuse those observations rather than repeating every install. Record this gate in `evidence/step-1.2.md`; assess before requesting approval to advance.

## Phase 2 — Runtime proof and separate shell experiment

Outcome: the existing runner starts a reproducible fixture without shell edits; a separate shell addition is safe to repeat and reverse.
Depends on: Phase 1 exit gate.
Review boundary: one runtime/fixture and one narrow shell experiment; no provisioning framework or changes to normal runner behavior.

### Step 2.1 — Pinned runtime and the real project runner

Requirements / acceptance: R2, R4, R5, R6; AC2, AC5. AC6 is deliberately excluded until this proof passes.
Depends on: Step 1.2 and the Phase 1 exit gate.
Review boundary: ordinary-user tool installation, fixture creation, and a fixture-specific fnm execution command.

Expected files:

- `dev-manager/App/ProvisioningModel.swift` — install/check pinned runtime; create the dependency-free fixture under application support.
- `dev-manager/App/ProvisioningView.swift` — runtime action and fixture handoff into existing project UI.
- `dev-manager/App/ContentView.swift` — only the selection/fixture handoff needed to show the registered project.

Tasks:

- [x] Reuse a working fnm or install it through Homebrew. Install the chosen Node version and exact pnpm version within that fnm runtime, using noninteractive ordinary-user processes. Detect incompatible existing state rather than automatically upgrading or deleting it.
- [x] Materialize a tiny `package.json` and Node built-in HTTP server, recording the exact versions. Register/reuse its folder with `ProjectStore.addProject(folderURL:command:)` and use the existing `ProjectRunner`/project UI. Avoid duplicate fixture entries on repeat.
- [x] Give only the fixture an absolute-path fnm execution command selecting the pinned runtime and running pnpm. Do not modify `ProcessLauncher`, global shell environment, or shell initialization files. Surface tool failures and block fixture launch when prerequisites fail.
- [x] Satisfy the verification and completion gate below and record concise evidence.

Verification:

- Build: run the Debug build. Inspect the runtime invocation for explicit version selection and ordinary-user execution; confirm no shared runner changes.
- Manual, approved VM action: capture whether shell files exist and their contents before installing tools. Install runtime, inspect reported Node/pnpm versions, run the fixture through the usual project UI, open its discovered HTTP site, Stop, and restart. Confirm shell files are unchanged. Quit/reopen, repeat setup, and start again: working versions remain unchanged and no duplicate fixture/configuration appears.
- Failure/invariant check: before runtime prerequisites are ready, the fixture action must not start a successful-looking run. If an actual tool command fails during the walkthrough, retain the useful error and show the unmet prerequisite rather than continuing.

Completion gate: AC2 and AC5 are demonstrated in the VM with unchanged shell files, including HTTP readiness and successful Stop/restart. Process-start handshake alone is not acceptance.
Evidence location: [evidence/step-2.1.md](evidence/step-2.1.md).

### Step 2.2 — Opt-in shell addition and findings

Requirements / acceptance: R1, R7, R8; AC6, AC7 (remaining coverage), AC8. Phase exit integrates AC1–AC8.
Depends on: Step 2.1, including its no-shell-edit proof.
Review boundary: one clearly owned shell block plus concise findings; no general shell migration/repair. The Phase 2 integration exit gate remains required and is recorded after the approved Step 2.3 follow-up.

Expected files:

- `dev-manager/App/ProvisioningShellConfiguration.swift` — new DEBUG-only narrow backup/add/remove helper.
- `dev-manager/App/ProvisioningModel.swift` and `dev-manager/App/ProvisioningView.swift` — separate consent, configure, fresh-shell check, and restore actions.
- `plans/provisioning-spike/findings.md` — concise human-facing VM findings, created from actual observations.

Tasks:

- [x] Explain the separate shell benefit and offer opt-in configuration. Detect existing equivalent fnm initialization, back up before writing, and append only a marked app-owned block that makes fnm discoverable. Leave ambiguous/conflicting, symlinked, or unexpectedly changed configurations untouched rather than attempting repair.
- [x] Add restoration that removes only the app-owned block, preserving unrelated contents. Recheck the file before changing it; do not overwrite later user edits with a wholesale backup restore.
- [x] Write brief findings from the VM walkthrough: environment/version pins, actual dialogs/permissions and Homebrew execution user, explicit runtime strategy, observed outcomes, limitations, and the production go/no-go recommendation. Label unrun checks as unrun; do not duplicate the evidence notes as a chronological log.
- [ ] Satisfy the verification and completion gate below and record concise evidence.

Verification:

- Build: run Debug and Release builds; inspect DEBUG guards to confirm setup is absent from Release. Run the existing regression suite once at the Phase 2 integration gate after Step 2.3, not after each edit.
- Manual, approved VM action: after 2.1 passes, opt in, inspect the file/backup, repeat configuration, and invoke a fresh interactive Zsh from the app to verify fnm and Node/pnpm resolution. No Terminal is needed. Restore and compare: unrelated contents survive, no duplicate loader is added, and an originally absent file is not populated with an unwanted loader.
- Small safety check in the disposable VM: include one unrelated line before the opt-in/restore cycle and verify it survives; a clearly conflicting existing fnm block must be reported without rewriting it. Use disposable fixture data/app diagnostics or a graphical editor for tester setup, not a required end-user manual edit.
- Manual ordinary-project check: on the prepared VM or existing development machine, launch a known-working project through normal Start without entering setup. It still uses its own command and produces no provisioning/authorization prompt.

Completion gate: shell apply/repeat/fresh-shell/restore behavior and conflict refusal are observed, ordinary project behavior is unchanged, and findings accurately distinguish proven behavior from limitations. The required Release, regression, and Phase 2 integration checks remain pending and are recorded after Step 2.3.
Evidence location: [evidence/step-2.2.md](evidence/step-2.2.md).

### Step 2.3 — Tighter DEBUG provisioning presentation

Requirements / acceptance: R9, AC9; preserves all existing R1–R8 and AC1–AC8 contracts.
Depends on: the Step 2.2 implementation and the user's reported successful shell walkthrough. This dependency does not imply that Step 2.2's Release, regression, ordinary-project, or final integration gates passed.
Review boundary: a compact presentation follow-up only; retain the existing provisioning model guards, installer handoffs, fixture path, and optional shell helper. Do not add a workflow framework or change normal project UI.

Expected files:

- `dev-manager/App/ProvisioningModel.swift` — small computed next-action enum derived from current checks and external waiting/busy flags; no saved wizard progress.
- `dev-manager/App/ProvisioningView.swift` — one footer action, accessible close, grouped status presentation, a title context menu with a separate Advanced / spike tools sheet, and scroll-safe layout.
- `plans/provisioning-spike/spec.md` and `plans/provisioning-spike/overview.md` — stable R9/AC9 contract and concise orientation update.
- `plans/provisioning-spike/plan.md`, `plans/provisioning-spike/evidence/changes.md`, and `plans/provisioning-spike/evidence/step-2.3.md` — approved bounded scope, dependency/gate note, and source-only evidence.

Implementation tasks:

- [x] Add the computed next-action model and preserve all existing `can*` safety guards, explicit confirmations, external waiting flags, and conflict refusal paths. When runtime is ready, expose **Configure shell — optional** only for `.notConfigured`; keep `.configured` and `.conflict` machine-ready/Done.
- [x] Simplify the view to one primary footer action; retain Check again, fixture, output, and shell controls in a separate Advanced / spike tools sheet opened from the sheet-title context menu; group the runtime rows and keep actionable statuses visible. The optional shell action must map to the existing consent and never block readiness or close.
- [x] Add accessible close/Escape behavior, a clearly closeable Advanced / spike tools sheet, and a scrollable, reasonable default/minimum layout without unrelated UI redesign.
- [x] Record source-only evidence and leave user build/manual verification pending.

Verification:

- Source-only: inspect the diff for current-check derivation, waiting-state handling, preserved guards, DEBUG gating, title-context-menu access to the separate Advanced control surface, accessible close, and no new wizard state. Run no build, test, parse, launch, install, download, or VM action for this follow-up.
- User-owned pending gates: build the Debug artifact in Xcode, inspect the ready VM and a fresh clone missing prerequisites, exercise external installer waiting, verify busy labels/disabled duplicates, and confirm fixture/shell/ordinary-project behavior remains intact. Release, regression, and final Phase 2 gates remain pending.

Completion gate: source inspection and `git diff --check` only for this authoring pass; the Step 2.3 verification checkbox remains unchecked until the user reports the required Xcode/VM checks.
Evidence location: [evidence/step-2.3.md](evidence/step-2.3.md).

### Step 2.4 — Focused provisioning source architecture

Requirements / acceptance: R10, AC10; preserves R1–R9 and AC1–AC9.
Depends on: the Step 2.3 implementation and the user's reported positive UI feedback. This dependency records the bounded follow-up context; it does not claim that any build, test, VM, Release, ordinary-project, or final integration gate passed.
Review boundary: file-level architecture only. Move and extract provisioning implementation into focused source files without changing behavior, UI layout, button logic, normal runner/store/environment code, or tested shell safety boundaries.

Expected files:

- `dev-manager/Provisioning/ProvisioningModel.swift` — thin DEBUG-only state, guards, next-action derivation, and action coordination.
- `dev-manager/Provisioning/ProvisioningCheck.swift` — shared check states and inspection result values.
- `dev-manager/Provisioning/ProvisioningConfiguration.swift` — pinned versions, environment values, fixture constants, and official Homebrew metadata constants.
- `dev-manager/Provisioning/ProvisioningInspector.swift` — read-only developer-tools, Homebrew, fnm, Node, and pnpm checks.
- `dev-manager/Provisioning/HomebrewPackageInstaller.swift` — official GitHub release metadata, package validation/download, and installer handoff support.
- `dev-manager/Provisioning/ProvisioningRuntimeInstaller.swift` — missing fnm, pinned Node, and pinned pnpm installation orchestration.
- `dev-manager/Provisioning/ProvisioningFixture.swift` — fixture contents, staging, conflict checks, and atomic handoff.
- `dev-manager/Provisioning/ProvisioningCommandRunner.swift` — bounded read-only commands and installer POSIX-spawn/process-group/output primitives.
- `dev-manager/Provisioning/ProvisioningShellConfiguration.swift` — existing shell safety boundary moved without a parser/receipt/atomic-I/O rewrite.
- `dev-manager/Provisioning/Views/ProvisioningView.swift` — existing main DEBUG layout, consent, next-action, and handoff coordination.
- `dev-manager/Provisioning/Views/ProvisioningStatusView.swift` — status rows, icons, info controls, and aggregate runtime presentation.
- `dev-manager/Provisioning/Views/ProvisioningAdvancedView.swift` — existing advanced/debug recovery surface.
- `dev-manager/App/ContentView.swift` — unchanged DEBUG entry reference remains `ProvisioningView(onFixtureReady:)`.
- `plans/provisioning-spike/evidence/step-2.4.md` — source-only implementation evidence and pending user-owned gates.

Tasks:

- [x] Move all provisioning source files out of `App` into the focused `Provisioning` tree with a `Views` subfolder; keep new files automatically included by the folder-synced project.
- [x] Extract concrete inspection, Homebrew, runtime installation, fixture, command-runner, shared-value, check-type, and view responsibilities without introducing protocols, DI, global environment changes, a workflow framework, or a new testing harness.
- [x] Keep the existing shell configuration implementation as a cohesive safety boundary and keep the existing `Runs/ProcessIdentity` bridge and normal project runner untouched.
- [x] Record the actual file map, line counts, preserved contracts, source-only checks, and pending user Debug build/manual regression/Release/test/final-integration gates.

Verification:

- Source-only: inspect the focused file tree and diff for responsibility boundaries, DEBUG guards, unchanged public view handoff, preserved pins/guards/waiting state/generation invalidation, bounded command/process ownership, fixture conflict safety, shell safety boundary, and no unrelated changes. Run `git diff --check`.
- User-owned pending gate: build the Debug artifact in Xcode and perform the predetermined manual UI/VM regression, then separately complete Release/setup-absence, existing tests, ordinary-project isolation, and the final Phase 2 integration gate. No such gate is claimed by this authoring pass.

Completion gate: source inspection and `git diff --check` only for this implementation pass; Step 2.4 and the final integration gate remain unchecked until the user reports the required checks.
Evidence location: [evidence/step-2.4.md](evidence/step-2.4.md).

### Step 2.5 — Bounded shared provisioning command runner

Requirements / acceptance: R11, AC11; preserves R1–R10 and AC1–AC10.
Depends on: Step 2.4 source architecture. This is a bounded runner/consumer/test follow-up; it does not claim any prior user-owned gate passed.
Review boundary: shared DEBUG command collection only. Keep read-only checks read-only, preserve the eight-second check and fifteen-minute install policies, and leave the existing Runs process engine untouched.

Expected files:

- `dev-manager/Provisioning/ProvisioningCommandRunner.swift` — one shared result and POSIX-spawn/process-group engine with concurrent bounded drains, deadline-aware collection, partial timeout diagnostics, finite cleanup, and reap.
- `dev-manager/Provisioning/ProvisioningConfiguration.swift` — explicit bounded cleanup grace constants.
- `dev-manager/Provisioning/ProvisioningInspector.swift` — explicit check timeout formatting at each read-only caller.
- `dev-manager/Provisioning/ProvisioningRuntimeInstaller.swift` and `dev-manager/Provisioning/ProvisioningModel.swift` — shared `ProvisioningProcessResult` consumers.
- `dev-managerTests/Provisioning/ProvisioningCommandRunnerTests.swift` — three focused deterministic Swift Testing cases using temporary scripts and an isolated process group.
- `plans/provisioning-spike/spec.md`, `plans/provisioning-spike/evidence/changes.md`, and `plans/provisioning-spike/evidence/step-2.5.md` — stable R11/AC11 contract, approval/evidence, and pending user verification.

Tasks:

- [x] Replace the split check/install result and completion-claim path with one shared bounded POSIX-spawn engine; drain both streams concurrently and retain bounded tails while the child runs.
- [x] Keep the command deadline effective through output collection; on timeout or incomplete collection, clean the owned process group, reap within finite grace, and return partial output without success.
- [x] Preserve distinct eight-second read-only check and fifteen-minute install policies; make timeout formatting caller-explicit and keep the existing Runs bridge untouched.
- [x] Add three focused Swift Testing cases for concurrent large output, leader-only timeout/reap, and a same-group descendant holding pipes; do not run them in this authoring pass.
- [x] Record source-only implementation evidence and leave Debug build, test execution, VM smoke, and final integration gates unchecked.

Verification:

- Source-only authoring: inspect the shared engine, consumer call sites, DEBUG guards, process-group ownership, bounded cleanup, and test names; `git diff --check` is permitted. No build, test, parse, launch, install, download, or host-shell workflow is performed here.
- User-owned Xcode verification: run `drainsLargeOutputWithoutPipeBackpressure`, `leaderOnlyTimeoutReapsLeader`, and `descendantHoldingPipesCannotExtendCommandDeadline`, then perform the existing Debug/manual/VM, Release, regression, ordinary-project, and final integration gates. The user owns any diagnosis of compiler/runtime behavior.

Completion gate: implementation tasks may be recorded here, but Step 2.5, AC11, and the final integration gate remain unchecked until the user reports the named tests and required manual gates.
Evidence location: [evidence/step-2.5.md](evidence/step-2.5.md).

### Step 2.6 — Approved per-tool provisioning presentation

Requirements / acceptance: R12, AC12; preserves R1–R11 and AC1–AC11.
Depends on: the Step 2.5 source architecture and the user's explicit approval of the per-tool proposal. This dependency does not imply that any build, test, VM, Release, ordinary-project, or final integration gate passed.
Review boundary: three existing provisioning views plus the coordinating model and bounded plan/evidence documentation. No new installer, runner, fixture, shell parser, test framework, protocol, or dependency is authorized.

Expected files:

- `dev-manager/Provisioning/ProvisioningModel.swift` — per-tool row-action derivation, active-tool mutual exclusion, targeted reinspection, dedicated single-tool runtime installation, and separate fixture preparation.
- `dev-manager/Provisioning/Views/ProvisioningView.swift` — remove the superseded footer action and route one targeted consent type plus fixture/shell consent callbacks.
- `dev-manager/Provisioning/Views/ProvisioningStatusView.swift` — row-local Install/Check installation/Check again/progress actions, prerequisite explanations, optional shell row, and visible diagnostics.
- `dev-manager/Provisioning/Views/ProvisioningAdvancedView.swift` — retain Advanced recovery/output controls while making fixture preparation separate from tool installation.
- `plans/provisioning-spike/spec.md`, `plans/provisioning-spike/overview.md`, `plans/provisioning-spike/plan.md`, `plans/provisioning-spike/evidence/changes.md`, and `plans/provisioning-spike/evidence/step-2.6.md` — record the accepted R12 contract and source-only status.
- No test file is changed; existing test seams remain untouched.

Tasks:

- [x] Replace the single footer action with mutually exclusive per-tool row actions for Apple developer tools, Homebrew, fnm, Node, and pnpm; preserve compact header/group/info/status presentation and remove the footer divider.
- [x] Enforce the prerequisite chain and targeted one-tool consent. Reinspect before machine-changing work, reuse a tool that became ready externally, refuse attention/conflict states, preserve external handoff latches, and retain the active target through allowed installation checks.
- [x] Separate dedicated runtime installation from fixture materialization. Each runtime action invokes only its existing command; Advanced preparation only materializes the owned fixture after all runtime tools are ready.
- [x] Keep optional shell configuration as a non-blocking row after the Node group; retain fresh-shell, Restore, output, and fixture handoff controls in Advanced.
- [ ] Complete the source-only verification note. User Debug build, manual clean-VM walkthrough, individual-only install, external waiting, all-ready, ordinary-project, shell/fixture regression, Release, existing tests, and final integration gates remain pending.

Verification:

- Source-only authoring: inspect the three views/model and `git diff --check`; do not build, test, parse, launch, install, download, or run the app.
- User-owned pending gate: manually exercise missing prerequisites, one-tool installs, external waiting/recheck, active-operation disabling, attention refusal, all-ready fixture preparation, optional shell controls, and existing regression/final criteria. No result is inferred here.

Completion gate: the implementation tasks above are recorded as completed by source inspection; Step 2.6, AC12, and the final integration gate remain unchecked until the user reports the required checks.
Evidence location: [evidence/step-2.6.md](evidence/step-2.6.md).

### Step 2.7 — Persistent bounded installation diagnostics and quiet shell row

Requirements / acceptance: R13, AC13; preserves R1–R12 and AC1–AC12.
Depends on: Step 2.6 source architecture and the user's approved final cleanup request. This dependency does not imply that any build, test, VM, Release, ordinary-project, or final integration gate passed.
Review boundary: one concrete installation-log helper plus the coordinating model and existing provisioning views/documentation. Remove only the inline runtime installation transcript and optional shell second-line label; preserve all manual UI spacing values, centered shared row, loading/recheck ownership, pins, backend commands, timeout policies, and safety boundaries.

Expected files:

- `dev-manager/Provisioning/ProvisioningInstallationLog.swift` — app-owned App Support log path, fixed installation record formatting, bounded append/rotation, regular-file/symlink safety, and private permissions.
- `dev-manager/Provisioning/ProvisioningModel.swift` — record installation results through the concrete helper, expose validated log/failure URLs and non-fatal write warnings, and preserve original installation outcome/errors.
- `dev-manager/Provisioning/Views/ProvisioningStatusView.swift` — remove inline installation output and the optional shell row's redundant second-line state label while retaining title/info/status/action behavior and all layout variables.
- `dev-manager/Provisioning/Views/ProvisioningAdvancedView.swift` — provide discreet Reveal installation log/failure-log controls and keep fresh-shell verification output.
- `plans/provisioning-spike/spec.md`, `plans/provisioning-spike/overview.md`, `plans/provisioning-spike/plan.md`, `plans/provisioning-spike/evidence/changes.md`, and `plans/provisioning-spike/evidence/step-2.7.md` — record stable R13/AC13, approved cleanup, source-only status, and pending gates.

Tasks:

- [x] Add one concrete DEBUG-only `ProvisioningInstallationLog` that writes only fixed labels, timestamps, exit/timeout status, and bounded returned stdout/stderr to `Application Support/Dev Manager/Logs/provisioning.log`, with one rotated previous file, safe app-owned path checks, and private file/directory modes. Do not add a logger framework, dependency, subprocess, or environment/credential capture.
- [x] Remove `installationOutput` and all inline installation transcript views. Keep fresh-shell verification output in Advanced. Remove only the optional shell row's second-line Configured/Not configured/Needs attention text; retain its title, info icon, status icon, colors, Configure action, and error notices.
- [x] Surface a validated existing log after relaunch, reveal the log from Advanced, and link the actual log written for the latest runtime install failure when available. A log-write failure is a visible diagnostic warning and never changes a successful installation into a failed result or hides the original failure.
- [ ] Complete source-only review and record pending user verification; do not claim successful-install, failure-reference, relaunch, or rotation checks without the user's build/manual report.

Verification:

- Source-only authoring: inspect the helper, model, and views for fixed labels, no environment/credential logging, bounded output, 256 KiB cap plus one rotation, symlink/directory safety, 0600 files/0700 new Logs directory, no inline transcript, quiet shell row, preserved spacing/centered-row/loading/timeout/pin/backend contracts, and `git diff --check`. Do not build, test, parse, launch, install, download, or run the app.
- User-owned pending verification: build the Debug artifact and manually complete one successful runtime installation, one runtime failure with its context link, one relaunch with a prior log discoverable in Advanced, and rotation/permission/path-safety checks. Verify log-write failure leaves the original install outcome/error intact. Existing Release, regression, VM, ordinary-project, and final integration gates remain pending.

Completion gate: implementation tasks are recorded by source inspection only; Step 2.7, AC13, and the final integration gate remain unchecked until the user reports the named checks.
Evidence location: [evidence/step-2.7.md](evidence/step-2.7.md).

Phase exit gate: after the final Step 2.7 verification, run the existing regression suite and review the final acceptance mapping for AC1–AC13 against the recorded VM observations. Expected result: builds/tests pass without new regressions, all required manual outcomes are demonstrated, and findings identify actual limits. Classify any pre-existing failure separately; do not call a failed or skipped gate passing. Record this integration/final gate after the final Step 2.7 verification (all prior Step 2.2, Step 2.3, Step 2.4, Step 2.5, and Step 2.6 gates remain required), then seek the user's review rather than proceeding to rollout.

## Final acceptance

| Spec acceptance ID | Owning step / gate | Verification and expected result | Evidence location |
| --- | --- | --- | --- |
| AC1 | Phase 1 gate; 1.1 and 1.2 | CLT and Homebrew complete via system GUI; console user can execute brew. | `evidence/step-1.1.md`, `evidence/step-1.2.md` |
| AC2 | 2.1 | Exact runtime, HTTP-ready fixture, Stop/restart, unchanged shell files. | `evidence/step-2.1.md` |
| AC3 | 1.1 | Real CLT cancellation, recheck, and successful retry. | `evidence/step-1.1.md` |
| AC4 | 1.2 | App relaunch after prerequisites reconstructs state without duplicate requests. | `evidence/step-1.2.md` |
| AC5 | 2.1 | Repeat setup after relaunch preserves tools and runs the fixture again. | `evidence/step-2.1.md` |
| AC6 | 2.2 | Opt-in configuration works in a fresh Zsh; repeat/restore preserve unrelated content. | `evidence/step-2.2.md` |
| AC7 | 1.1 guards; Phase 2 gate | Release compilation/source gating plus ordinary-project manual launch prove isolation. | `evidence/step-2.2.md` |
| AC8 | 2.2; Phase 2 gate | Concise findings reflect observations and explicitly identify unrun cases. | `findings.md`, `evidence/step-2.2.md` |
| AC9 | 2.3; historical; superseded by 2.6/AC12 | The earlier compact presentation's one-footer-action rationale, explicit external waiting, grouped runtime status, accessible close, title-context-menu Advanced tools, and optional shell boundary. | R12/AC12 is the current accepted UI contract; `evidence/step-2.3.md` remains historical and the prior verification/final gate is not fabricated. |
| AC10 | 2.4; final Phase 2 gate | Focused `Provisioning/` source tree and `Views/` subfolder, thin coordinating model, concrete helpers, one coherent configuration namespace, preserved DEBUG/public handoff and safety boundaries, and no unrelated runner/store/environment changes. | `evidence/step-2.4.md` and final acceptance review |
| AC11 | 2.5; final Phase 2 gate | Shared `ProvisioningProcessResult` and bounded POSIX-spawn collection for checks/installers; concurrent large-output drain, deadline-enforced same-group descendant cleanup, leader reap, partial timeout diagnostics, explicit check/install policies, and focused regression cases. Detached process trees remain outside this scoped guarantee. | `evidence/step-2.5.md` and final acceptance review |
| AC12 | 2.6; final Phase 2 gate | Per-tool current-state actions for the five in-scope tools, targeted consent, prerequisite guards, external handoff recheck, active-operation exclusion, separate fixture preparation, visible diagnostics, and non-blocking optional shell row. | `evidence/step-2.6.md` and final acceptance review |
| AC13 | 2.7; final Phase 2 gate | Persistent bounded runtime-install diagnostics, Advanced reveal/failure reference, safe private App Support storage, non-fatal log-write failure handling, no inline transcript, and the quiet optional shell row. | `evidence/step-2.7.md` and final acceptance review |

No live workflow, build, test, installation, or VM acceptance has been run merely by authoring this plan.

## Rollback and recovery

- Revert step 2.2 before its prerequisites, then 2.1, 1.2, and 1.1 as needed; do not leave a UI call to a removed helper. Code reversion does not uninstall tools or undo shell changes.
- Shell restoration is limited to the owned block. Preserve the backup for human inspection; never overwrite unrelated edits.
- macOS installation and Homebrew/runtime downloads can leave successful partial changes. Recover by rechecking, not blind reinstall or automatic cleanup. Restore the user's clean VM snapshot for a truly fresh baseline.
- No system-tool uninstall, administrator-password handling, privileged helper cleanup, or rollback of other users' files is authorized.

## Planned deferred checks

- Standard accounts, Intel, MDM/pre-login deployment, full-Xcode variations, and arbitrary pre-existing toolchains: outside this VM/admin spike.
- Every download/network/installer failure and every shell customization: no exhaustive matrix; stop and record material unexpected cases instead of silently expanding scope.
- Production signing/notarization/distribution, new automated provisioning tests, and broad compatibility coverage: reconsider only after findings justify a production feature.

Execution-time blockers, skipped/waived checks, and actual approved deviations belong in the evidence notes, not mutable plan status.
