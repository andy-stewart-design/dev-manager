# Step 2.3 — Simplified DEBUG provisioning presentation

Status: Source-only implementation pass. User-owned Xcode build and VM/manual verification are pending. No build, test, parse, app launch, installation, download, or VM action was performed for this follow-up.

The notes below retain the prior bounded presentation pass. The latest approved refinement is recorded at the end of this file.

## Implemented 2.3 tasks

- [x] Add a small computed next-action model derived from current checks, busy state, and external installer waiting flags; do not persist wizard progress.
- [x] Replace multiple footer actions with one primary action; retain existing confirmations and `can*` guards.
- [x] Group fnm, pinned Node, and pinned pnpm under Node environment; keep actionable missing/attention details visible and ready diagnostics in accessible help.
- [x] Move Check again, fixture handoff/preparation, output, and optional shell actions into Advanced; add accessible xmark/Escape close and a scrollable sheet layout.
- [x] Record the approved bounded scope, R9/AC9 contract, dependency/gate adjustment, and this evidence note.
- [x] Review fix: completed checks clear the Homebrew handoff flag unconditionally, so a verified ready Homebrew state advances past Check installation.
- [x] Review fix: a ready runtime derives the optional shell action from `ProvisioningShellConfiguration.inspect()`; only `.notConfigured` with `canConfigureShell` offers **Configure shell — optional**. Configured and conflict states remain Done, with details still available under Advanced.
- [x] Review fix: the optional primary action opens the existing consent, while install controls retain busy guards against concurrent shell work.

## Source-only checks

- The model's next action is recomputed from the current checks and explicit installer/busy flags; no prior wizard step is saved or used to advance setup.
- Completed checks clear the Homebrew handoff wait unconditionally, allowing initial and post-installer verification to advance when Homebrew is ready.
- Existing installer request, runtime installation, fixture, shell configuration, conflict refusal, and `can*` safety paths remain the action backends. Optional shell configuration does not participate in machine readiness.
- The view exposes a single footer primary action. External handoff resolves to **Check installation** after the handoff returns; checking, download, and runtime installation show disabled working labels. A ready runtime with unconfigured optional shell presents **Configure shell — optional**, and the X remains a skip path.
- Existing spike tools remain available under Advanced, and the top close action can skip optional shell configuration.

## Verification status

- [ ] Step 2.3 verification and completion gate — pending user Xcode build and manual VM walkthrough.
- [ ] Release/setup-absence check — pending.
- [ ] Existing regression suite — pending.
- [ ] Ordinary-project isolation check — pending.
- [ ] Phase 2 final integration gate and final AC9 mapping — pending.

## User-owned checks to perform

1. In the already-ready VM, reopen setup and confirm all rows are ready; an unconfigured shell shows **Configure shell — optional**, while configured/conflicting shell state shows Done. Advanced still exposes fixture and shell tools, and Escape/xmark closes without requiring shell configuration.
2. In a fresh clone or clean supported VM missing prerequisites, confirm the sequence is Install Apple developer tools → Check installation after Apple's dialog → Install Homebrew → Check installation after Installer → Set up Node and pnpm.
3. During each check/download/install operation, confirm the working label and disabled duplicate actions; cancel an external installer and use Check installation before retrying.
4. Confirm conflicting/unusable tools remain attention states rather than being blindly repaired, and the fixture path remains available without shell setup.

## Latest approved refinement — source-only

- **User direction:** “Better, but I want to go even simpler, like this ... info icons ... not ... tooltip”
- [x] Tighten the normal surface to the header/intro, compact grouped status rows, actual progress/error notice only when needed, and one primary footer action; remove routine completion/missing/waiting paragraphs and the visible Advanced disclosure.
- [x] Replace inert image-only help affordances with clickable small Buttons whose popovers expose selectable technical paths/details.
- [x] Move Advanced / spike tools to a separate clearly closeable sheet opened from the sheet-title contextual menu; retain Check again, fixture preparation/showing, shell configure/fresh/Restore, diagnostics, and consent handoff behavior.
- [x] Follow-up source review: routine status subtitles are removed, individual dependency info buttons sit beside their titles, the aggregate Node environment has no info button, and Advanced consent/fixture handoff waits for child-sheet dismissal.
- **Latest verification status:** source-only `git diff --check`; user-owned Xcode build, VM/manual walkthrough, Release isolation, regression, ordinary-project, and final integration gates remain pending. No final acceptance checkmark is recorded for this refinement.
