# Provisioning spike findings

## Human-facing result

The user previously reported successful Phase 1 and Step 2.1 walkthroughs, including the pinned runtime fixture, HTTP readiness, Stop/restart, relaunch, and unchanged shell files. Those results remain user-reported; the agent did not inspect the VM or the user's files.

For Step 2.2, the user reports that the shell walkthrough is working after the trailing-newline parser fix: “Nice. I have thoroughly tested this now and it all seems to be working.” This is a broad user-reported result, not agent-observed evidence, and does not establish separate granular case outcomes beyond that report. The previously reported preservation failure is no longer reported; the final retest was reported successful by the user.

Historical note: unrelated content after the managed block previously exposed an extractor bug because it included the newline after the end marker. The source correction now extracts only the exact marker range, preserves following content, and rejects malformed boundaries. Earlier user-reported clean-file and legacy-cycle results are retained as history rather than repeated as a diary.

The Release build/setup-absence check, existing regression suite, and ordinary-project isolation smoke have not been separately reported. The Step 2.2 verification checkbox and Phase 2 final gate therefore remain unchecked. No result is inferred from source authoring. The existing fresh-shell timeout limitation also remains: it times out the launched leader, not descendant process groups.

## Recommendation

The shell walkthrough is provisionally reported working, but do not treat the spike as fully accepted or production-ready until the remaining Release/setup-absence, regression-suite, and ordinary-project isolation checks are reported and the final Phase 2 gate is reviewed.

The final source-only architecture pass preserves the behavior and UI contracts above while moving provisioning into `dev-manager/Provisioning/` with `Views/` for the DEBUG surface. No build, test, VM, Release, ordinary-project, or final integration result is inferred from that refactor.
