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

## Approved inspection loading simplification

- **Actual user request:** during initial or manual inspection, replace the global notice plus five checking rows with one centered progress indicator and “Inspecting installed tools…” while preserving the normal header, intro, Advanced title menu, and close/Escape behavior.
- **Bounded source change:** the existing main content boundary now swaps in one accessible loading view when `checks` is empty or `isChecking && activeToolID == nil`; the checklist `ScrollView` is not rendered behind it. Active-tool rechecks remain on the checklist so target-row installation progress is preserved, and the existing checks/errors/business logic is unchanged.
- **Verification status:** source-only inspection and `git diff --check`; no build, test, parse, launch, install, download, VM, or host-shell action. User Debug build and manual review remain pending.
