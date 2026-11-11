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
| 2 | A pinned runtime runs the fixture without shell edits; optional shell configuration is reversible. | Phase 1 exit gate. | Fixture, repeat/relaunch, shell experiment, Release isolation, and existing regressions verified. |

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
- [ ] Satisfy the verification and completion gate below and record concise evidence.

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

- [ ] Reuse a working fnm or install it through Homebrew. Install the chosen Node version and exact pnpm version within that fnm runtime, using noninteractive ordinary-user processes. Detect incompatible existing state rather than automatically upgrading or deleting it.
- [ ] Materialize a tiny `package.json` and Node built-in HTTP server, recording the exact versions. Register/reuse its folder with `ProjectStore.addProject(folderURL:command:)` and use the existing `ProjectRunner`/project UI. Avoid duplicate fixture entries on repeat.
- [ ] Give only the fixture an absolute-path fnm execution command selecting the pinned runtime and running pnpm. Do not modify `ProcessLauncher`, global shell environment, or shell initialization files. Surface tool failures and block fixture launch when prerequisites fail.
- [ ] Satisfy the verification and completion gate below and record concise evidence.

Verification:

- Build: run the Debug build. Inspect the runtime invocation for explicit version selection and ordinary-user execution; confirm no shared runner changes.
- Manual, approved VM action: capture whether shell files exist and their contents before installing tools. Install runtime, inspect reported Node/pnpm versions, run the fixture through the usual project UI, open its discovered HTTP site, Stop, and restart. Confirm shell files are unchanged. Quit/reopen, repeat setup, and start again: working versions remain unchanged and no duplicate fixture/configuration appears.
- Failure/invariant check: before runtime prerequisites are ready, the fixture action must not start a successful-looking run. If an actual tool command fails during the walkthrough, retain the useful error and show the unmet prerequisite rather than continuing.

Completion gate: AC2 and AC5 are demonstrated in the VM with unchanged shell files, including HTTP readiness and successful Stop/restart. Process-start handshake alone is not acceptance.
Evidence location: [evidence/step-2.1.md](evidence/step-2.1.md).

### Step 2.2 — Opt-in shell addition and final findings

Requirements / acceptance: R1, R7, R8; AC6, AC7 (remaining coverage), AC8. Phase exit integrates AC1–AC8.
Depends on: Step 2.1, including its no-shell-edit proof.
Review boundary: one clearly owned shell block plus final integration evidence; no general shell migration/repair.

Expected files:

- `dev-manager/App/ProvisioningShellConfiguration.swift` — new DEBUG-only narrow backup/add/remove helper.
- `dev-manager/App/ProvisioningModel.swift` and `dev-manager/App/ProvisioningView.swift` — separate consent, configure, fresh-shell check, and restore actions.
- `plans/provisioning-spike/findings.md` — concise human-facing VM findings, created from actual observations.

Tasks:

- [ ] Explain the separate shell benefit and offer opt-in configuration. Detect existing equivalent fnm initialization, back up before writing, and append only a marked app-owned block that makes fnm discoverable. Leave ambiguous/conflicting, symlinked, or unexpectedly changed configurations untouched rather than attempting repair.
- [ ] Add restoration that removes only the app-owned block, preserving unrelated contents. Recheck the file before changing it; do not overwrite later user edits with a wholesale backup restore.
- [ ] Write brief findings from the VM walkthrough: environment/version pins, actual dialogs/permissions and Homebrew execution user, explicit runtime strategy, observed outcomes, limitations, and the production go/no-go recommendation. Label unrun checks as unrun; do not duplicate the evidence notes as a chronological log.
- [ ] Satisfy the verification and completion gate below and record concise evidence.

Verification:

- Build: run Debug and Release builds; inspect DEBUG guards to confirm setup is absent from Release. Run the existing regression suite once at the Phase 2 gate, not after each edit.
- Manual, approved VM action: after 2.1 passes, opt in, inspect the file/backup, repeat configuration, and invoke a fresh interactive Zsh from the app to verify fnm and Node/pnpm resolution. No Terminal is needed. Restore and compare: unrelated contents survive, no duplicate loader is added, and an originally absent file is not populated with an unwanted loader.
- Small safety check in the disposable VM: include one unrelated line before the opt-in/restore cycle and verify it survives; a clearly conflicting existing fnm block must be reported without rewriting it. Use disposable fixture data/app diagnostics or a graphical editor for tester setup, not a required end-user manual edit.
- Manual ordinary-project check: on the prepared VM or existing development machine, launch a known-working project through normal Start without entering setup. It still uses its own command and produces no provisioning/authorization prompt.

Completion gate: shell apply/repeat/fresh-shell/restore behavior and conflict refusal are observed, ordinary project behavior is unchanged, Release builds without setup, and findings accurately distinguish proven behavior from limitations.
Evidence location: [evidence/step-2.2.md](evidence/step-2.2.md).

Phase exit gate: after 2.2 verification, run the existing regression suite and review the final acceptance mapping against the recorded VM observations. Expected result: builds/tests pass without new regressions, all required manual outcomes are demonstrated, and findings identify actual limits. Classify any pre-existing failure separately; do not call a failed or skipped gate passing. Record this integration/final gate in `evidence/step-2.2.md`, then seek the user's review rather than proceeding to rollout.

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
