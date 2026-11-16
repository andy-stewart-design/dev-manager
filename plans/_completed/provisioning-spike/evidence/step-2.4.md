# Step 2.4 — Focused provisioning source architecture

Status: Source-only concurrency-warning correction pass. The user reported Xcode warnings in `ProvisioningCommandRunner` and `ProvisioningInspector`; the source corrections below are applied, but user-owned rebuild and manual verification remain pending. No build, test, parse, app launch, installation, download, or VM action was performed.

## Implemented source map

- `dev-manager/Provisioning/ProvisioningModel.swift` — DEBUG-only observable state, guards, check-generation invalidation, next-action derivation, consent/action coordination, and progress/error publication.
- `dev-manager/Provisioning/ProvisioningCheck.swift` — shared check IDs/states and inspection result values.
- `dev-manager/Provisioning/ProvisioningConfiguration.swift` — pinned Node/pnpm versions, environment constants, timeout/official Homebrew constants, and fixture contents/paths.
- `dev-manager/Provisioning/ProvisioningInspector.swift` — read-only developer-tools, Homebrew, fnm, Node, and pnpm checks.
- `dev-manager/Provisioning/HomebrewPackageInstaller.swift` — official GitHub release metadata, HTTPS/asset validation, bounded package download, and installer-handoff support.
- `dev-manager/Provisioning/ProvisioningRuntimeInstaller.swift` — missing fnm, pinned Node, and pinned pnpm installation calls.
- `dev-manager/Provisioning/ProvisioningFixture.swift` — owned fixture validation, staging, conflict refusal, and atomic directory handoff.
- `dev-manager/Provisioning/ProvisioningCommandRunner.swift` — read-only 8-second command helper plus bounded installer process-group, POSIX-spawn, FD, output, termination, and reap primitives.
- `dev-manager/Provisioning/ProvisioningShellConfiguration.swift` — existing cohesive shell safety boundary moved unchanged in responsibility.
- `dev-manager/Provisioning/Views/ProvisioningView.swift` — existing main layout, consent flow, next-action button, close behavior, and fixture handoff.
- `dev-manager/Provisioning/Views/ProvisioningStatusView.swift` — status rows, icons, info popovers, and aggregate runtime presentation.
- `dev-manager/Provisioning/Views/ProvisioningAdvancedView.swift` — existing advanced/debug recovery controls.

## Actual Swift file line counts

| File | Lines |
| --- | ---: |
| `Provisioning/ProvisioningModel.swift` | 474 |
| `Provisioning/ProvisioningCheck.swift` | 79 |
| `Provisioning/ProvisioningConfiguration.swift` | 97 |
| `Provisioning/ProvisioningInspector.swift` | 161 |
| `Provisioning/HomebrewPackageInstaller.swift` | 121 |
| `Provisioning/ProvisioningRuntimeInstaller.swift` | 35 |
| `Provisioning/ProvisioningFixture.swift` | 161 |
| `Provisioning/ProvisioningCommandRunner.swift` | 422 |
| `Provisioning/ProvisioningShellConfiguration.swift` | 683 |
| `Provisioning/Views/ProvisioningView.swift` | 232 |
| `Provisioning/Views/ProvisioningStatusView.swift` | 220 |
| `Provisioning/Views/ProvisioningAdvancedView.swift` | 98 |
| **Total** | **2,783** |

`dev-manager/App/ContentView.swift` is unchanged and continues to use the `ProvisioningView` initializer's `onFixtureReady` callback. The existing `Runs/ProcessIdentity` bridge, normal runner, project store, shell environment, and unrelated feature trees were not changed.

## Source-only checks

- All provisioning implementation and view files are DEBUG-guarded.
- Pins and environment constants have one `ProvisioningConfiguration` owner; the model remains the state/guard/action coordinator.
- Existing waiting flags, generation invalidation, typed check/progress/error states, fixture conflict rules, installer process-group primitives, and shell configuration boundary remain represented.
- `git diff --check` and the source-only whitespace review passed; compiler/build confirmation remains pending.
- User-reported Xcode warnings recorded for this pass: `ProvisioningCommandRunner` reported `Instance method 'wait' is unavailable from asynchronous contexts; Use a TaskGroup instead; this is an error in Swift 6 language mode`; `ProvisioningInspector` reported calls to Main actor-isolated `String.firstNonEmptyLine`, `ProvisioningCommandResult.failureDescription(for:)`, and `String.containsToken` outside the actor.
- Source correction: pure provisioning value/string utilities and shared helper members now carry explicit `nonisolated` boundaries; the installer’s blocking process-group workload, including bounded `DispatchGroup.wait` calls, now runs in a synchronous nonisolated helper on a utility GCD queue and resumes its async continuation once. The user subsequently confirmed those warnings were gone, but Xcode reported three errors from invalid `nonisolated` annotations on mutable stored properties. Removed only those property annotations; their enclosing classes remain nonisolated and all mutable storage remains lock-protected. This correction awaits the user's next build; no agent build, test, or parse was run.
- SHA-256 comparison against the pre-refactor Git version confirmed `ProvisioningShellConfiguration.swift` is byte-identical after the move (`b83d269b207823cbef80dd097f975b000cac45cbb3f6968a9f818996e1acc1af`). Protected app/runner/store/discovery paths have no diff.

## Pending user-owned gates

- [ ] Debug Xcode build and user manual UI/VM regression.
- [ ] Release/setup absence and ordinary-project isolation.
- [ ] Existing regression suite.
- [ ] Fresh next-action, external installer waiting, shell restore, and fixture smoke checks.
- [ ] Final Phase 2 integration gate and AC1–AC10 review.

No result is inferred for those pending checks, and no claim is made that the user ran a CLI workflow.
