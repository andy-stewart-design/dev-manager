# Approved changes

## DEBUG provisioning presentation follow-up (Step 2.3)

- **User agreement:** “cool. Let's do it” — the user's approval of the prior explicit discussion for this bounded presentation change.
- **Approved presentation change:** replace the several setup footer buttons with one current-check-derived primary next action; show Apple developer tools, Homebrew, and a grouped Node environment with actionable status; make external installer waiting and busy states explicit; move existing check, fixture, output, and optional shell controls into Advanced; provide an accessible xmark/Escape close and a scroll-safe sheet.
- **Rationale:** make the next safe action obvious without turning the spike into a persisted wizard or weakening its existing `can*` guards, installer handoffs, conflict refusal, fixture path, or optional-shell boundary.
- **Bounded dependency/gate adjustment:** add Step 2.3 after the Step 2.2 implementation and the user's reported shell walkthrough. The Phase 2 integration exit gate moves after final Step 2.3 verification, while all prior Step 2.2 gates remain required and unchecked until actually verified. AC9 is added without renumbering existing requirements or acceptance IDs.
- **Verification status:** no build waiver or approval is fabricated here. User-owned Xcode build, Release/setup-absence, regression, ordinary-project, and VM/manual checks remain pending.

## DEBUG provisioning tightening refinement (Step 2.3)

- **User request:** “Better, but I want to go even simpler, like this ... info icons ... not ... tooltip”
- **Approved refinement:** remove the visible Advanced disclosure and routine status paragraphs; keep the compact Apple developer tools/Homebrew/Node environment rows, one blue footer action, and real progress/errors only. Make each info affordance an actual small Button with a selectable-details popover, then move Advanced / spike tools to a clearly closeable secondary sheet opened from the sheet title's contextual menu.
- **Rationale:** match the simpler reference layout while keeping technical paths/details available on demand, making info controls reliably clickable, and preserving all existing guards, consent dialogs, fixture handoff, shell recovery controls, IDs, tasks, history, and pending final gates.
- **Verification status:** source-only authoring pass; user-owned Xcode build and manual VM checks remain pending. No final acceptance checkmark is recorded here.

## Final behavior-preserving architecture refactor (Step 2.4)

- **User request / approval:** the task requests the approved final behavior-preserving FILE-LEVEL ARCHITECTURE refactor, with provisioning moved out of `App` into `dev-manager/Provisioning/` and `Views/`, while preserving the existing DEBUG API and behavior.
- **Bounded change:** extract concrete shared check/value, read-only inspector, official Homebrew package handoff, runtime installer, fixture, command-runner, and view responsibilities; keep `ProvisioningShellConfiguration.swift` cohesive and move it without rewriting its tested parser/receipt/atomic-I/O safety boundary.
- **Preserved boundaries:** no `ContentView` handoff change, normal `Runs`/`Projects`/`Discovery` behavior change, global environment change, `ProjectStore` change, `ProcessIdentity` change, protocol/DI layer, workflow persistence, or new test harness.
- **Verification status:** implementation tasks are recorded as completed by source inspection; only source inspection and `git diff --check` are performed for this pass. Debug build, manual UI/VM regression, Release/setup absence, existing tests, ordinary-project isolation, shell/fixture smoke, and final integration remain pending and unchecked.

## Approved bounded command-runner cleanup (Step 2.5)

- **User approval:** the task explicitly approves both focused cleanup items: shared bounded check/install subprocess machinery and deduplication of the identical check/install result into `ProvisioningProcessResult`.
- **Approved behavior:** replace the check completion-claim race and installer exit-before-drain gap with one existing-style POSIX-spawn/process-group engine; drain stdout and stderr concurrently while running; retain bounded tails while continuing to drain; enforce each caller's deadline through collection; return partial diagnostics on timeout; clean and reap within explicit finite grace periods; and never report success when output collection misses the deadline.
- **Preserved policies and boundaries:** read-only checks remain read-only with an eight-second timeout; installs retain fifteen minutes; timeout descriptions receive the caller's explicit limit; the existing `Runs/ProcessIdentity` bridge and normal runner are untouched; no global Runs changes or new dependencies/framework are introduced.
- **Approved focused tests:** add deterministic Swift Testing cases for large concurrent stdout/stderr and a leader exiting while a child holds both pipes open, using temporary scripts and a dedicated process group. Tests are added but not executed by the agent; user-owned Xcode verification remains pending.
- **Bounded plan/evidence adjustment:** add stable R11/AC11 and Step 2.5 after Step 2.4 without renumbering or checking prior IDs. Final integration remains after the last step, and all user Debug build/test/VM/final gates remain unchecked.

## Approved per-tool provisioning UI (Step 2.6 / R12)

- **Actual user approval:** “Yeah, I’m good with this. Let’s do it” — approval of the per-tool row proposal and bounded implementation described in the task.
- **Approved current UI:** replace the superseded single footer action with individual Apple developer tools, Homebrew, fnm, Node, and pnpm rows. Ready rows are green with no Install; missing rows offer a quiet bordered Install only when prerequisites are ready; blocked or unverified rows explain why Install is disabled; attention states offer recheck rather than blind replacement; external handoffs require Check installation; active work shows row progress and disables other actions.
- **Approved boundaries:** one targeted tool consent with tool name/effect; dependency chain Apple developer tools → Homebrew → fnm → Node → pnpm; no automatic chain installation; dedicated single-tool runtime commands; reinspection before writes; separate fixture preparation only after all runtime checks are ready; optional shell remains non-blocking after the Node group; GitHub CLI and Bun remain out of scope.
- **Approved documentation adjustment:** add stable R12/AC12 and bounded Step 2.6; explicitly supersede R9's single-footer contract while retaining its compact-layout rationale and historical record. Earlier plan steps 1–2.5 remain historical requirements; this entry clarifies the current accepted UI and does not claim those earlier gates were newly executed.
- **Verification status:** only the implementation tasks are recorded as completed by source inspection. Step 2.6, all Debug/manual/VM/Release/test/regression/final gates, and unchecked prior gates remain pending.

## Approved Step 2.6 layout follow-up

- **Actual user request:** use one shared row layout with `rowMinimumHeight = 32`, `rowVerticalPadding = 10`, and horizontal `itemSpacing = 10`; apply it to Apple tools, Homebrew, the Node header/children, and optional shell while keeping row-list stacks at spacing `0`. Preserve centered row content, wrapped errors, inset Node separators, and flush-right actions.
- **Bounded change:** refine only `ProvisioningStatusView` presentation and clarify the existing R12/AC12 wording; no new ID, phase, feature, provisioning state, workflow, or test harness.
- **Verification status:** source inspection and `git diff --check` only; the user Debug build and manual layout review remain pending.

## Approved final cleanup: persistent installation diagnostics and quiet shell row (Step 2.7 / R13)

- **User-approved request:** “remove inline INSTALLATION OUTPUT from provisioning UI” and “remove optionalShellrowsecondline.” The request also references the current screenshot showing the npm transcript and the Optional Shell Configuration subtitle; this source-only pass records the requested cleanup without claiming a new screenshot or manual result.
- **Approved behavior:** write runtime installation diagnostics best-effort to the app-owned `Application Support/Dev Manager/Logs/provisioning.log` path using one concrete helper. Records contain only the fixed command label, timestamp, exit/timeout status, and bounded returned stdout/stderr. Cap the current log at 256 KiB with one rotated previous file; refuse unsafe app-owned symlink/dangling/nondirectory paths and use private permissions. Advanced may reveal only a validated existing log and may expose the log actually written for the latest runtime installation failure.
- **Preserved boundaries:** no logger framework, dependency, subprocess, environment dump, credential/password handling, host log writes, global process-runner changes, installation outcome changes, UI spacing-variable changes, centered shared row changes, loading/recheck ownership changes, timeout/pin/backend-command changes, fresh-shell Advanced output, or shell safety changes.
- **Presentation cleanup:** remove the Published `installationOutput` state and all inline installation transcript scroll views. Keep fresh-shell verification output in Advanced. Remove only the optional shell row's second-line Configured/Not configured/Needs attention label while retaining title, info icon/detail, status icon/color, Configure action, and error notices.
- **Verification status:** source inspection only. User Debug build, successful-install log existence, runtime-failure log reference, relaunch discovery, permissions/path safety, and rotation checks remain pending; all prior gates and the final Phase 2 gate remain unchecked.

## Approved inspection loading and targeted recheck flow

- **Actual user approval:** after the detailed flow, “cool.let'sdoit”.
- **Approved behavior:** only the first whole-machine inspection uses the centered full-sheet loader. Once its states arrive, the checklist remains visible forever for that sheet session. Advanced Check again retains the last statuses and may show one global progress notice; a row Check installation/Check again or an install pre/postflight owns progress only in its requested row. Errors remain visible.
- **Bounded source change:** add independent `hasLoadedInitialInspection` and operation ownership IDs; add `ProvisioningInspector.inspect(target:)` for Apple-only, Homebrew-only, and fresh fnm-context runtime checks; patch only returned check IDs. Runtime targeted checks refresh related Node/pnpm state and clear unusable fnm context rather than reusing it blindly. No new stable IDs or phase are introduced.
- **Verification status:** source-only inspection and `git diff --check`; targeted manual/debug walkthroughs remain pending. No build, test, parse, launch, install, download, VM, or host-shell action is claimed.
