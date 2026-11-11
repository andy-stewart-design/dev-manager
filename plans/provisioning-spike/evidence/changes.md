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
