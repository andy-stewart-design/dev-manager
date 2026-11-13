# Repo-aware Execution Implementation Plan

## Governing source

- Governing spec: [spec.md](spec.md).
- Human-facing orientation: [overview.md](overview.md).

This plan is an execution contract. Scope, steps, IDs, dependencies, expected files, verification definitions, completion gates, and acceptance mappings remain fixed during routine execution. A task checkbox records work performed, not acceptance, approval, publication, deployment, or release. In supervised execution, manual approvals remain in extension state.

## Execution constraints

- Paths are relative to this repository. Commands run from the repository root unless stated otherwise.
- Preserve unrelated work, including the existing provisioning-view edit, archived provisioning-plan move, and GitHub CLI planning documents. Expected files describe scope, not permission to overwrite concurrent work.
- Production machine provisioning is an explicit prerequisite supplied before this scope begins. Releasing the DEBUG spike is not a task here. Its current types are integration clues, not a promise about the future production API.
- Step 0.1 is a hard entry gate. If the production handoff is unavailable, or no safe project-specific integration can be identified, record the blocker and stop dependent work. Downstream phases are conditional on their gates, not authorization to invent a production provider.
- Actual multi-version isolation must pass the approval-required Phase 2 exit gate before guided execution is exposed. A fake-provider pass or production availability alone is insufficient.
- Adding a folder, inspecting requirements, and Run never approve installation. Machine setup and dependency installation have separate approvals. Never replace global package-manager versions, change global fnm defaults, or edit shell profiles to satisfy this feature.
- Do not run real installers, download tools, or execute repository lifecycle scripts without explicit approval for the disclosed machine/repository changes. This plan is not that approval. Use disposable repositories and a supported test account/machine for live gates; no credentials should be necessary.
- Routine plan edits are limited to task checkboxes. Other changes require explicit user agreement, recorded with rationale and actual agreement in [evidence/changes.md](evidence/changes.md). Escalate contract conflicts before affected work proceeds.
- Check a verification task only after its required checks and completion gate pass and concise evidence is recorded. Failed, blocked, skipped, or waived checks stay unchecked; a waiver is not a pass.
- Each completed step receives a short note at its predetermined evidence location. Usually record only the command/check, outcome, and material caveat. Record phase exit gates in the final step's note and final acceptance in Step 5.2's note, referencing prior proof rather than duplicating it. Do not create empty notes during planning or append transcripts/progress ledgers.

### Source grounding and verification vocabulary

Static inspection identified these existing seams:

- `Project.swift` / `ProjectStore.swift`: schema-1 settings, injected settings URL, atomic writes, and read-only protection for unsupported/corrupt data.
- `DevManagerApp.swift`, `ContentView.swift`, `ProjectDetailView.swift`, `ProjectSettingsSheet.swift`, and `ProjectSidebar.swift`: shared composition, synchronous folder registration, execution/output sections, arbitrary command editing, and command summaries.
- `ProcessLauncher.swift`, `ProcessSupervisor.swift`, `ProjectRunner.swift`, and `AppLifecycle.swift`: custom zsh/eval launch, registered cwd, output/process-group ownership, 10-second shell readiness, and quit cleanup.
- `LogBuffer.swift` / `OutputReader.swift`: bounded output and concurrent stream draining.
- Current `Provisioning/`: a fixed Node/pnpm pair and npm-global pnpm installation. This does not prove isolated manager supply or externally cancellable production operations.
- Existing suites: `ProjectStoreTests`, `ProjectRunnerTests`, `ProvisioningCommandRunnerTests`, and `LocalURLCandidateTests`. Existing process tests use real local subprocesses; provider fakes and managed-invocation seams must be added explicitly below.
- `dev-manager.xcodeproj/project.xcproj` uses synchronized app/test folder membership. New Swift files under those folders should not require individual project registration. No UI-test target or fixture framework is assumed.

Historical build/test evidence exists under `plans/_completed/`, including a historical Astro cleanup issue; it is not a current green baseline or proof that the issue persists. No tests/builds or live workflows were run to author this plan.

For future execution, use this shell helper, derived from the existing scheme and historical project commands:

```sh
# Working directory: repository root. Define in the execution shell; no script file required.
xb() {
  DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
  /usr/bin/xcodebuild -project dev-manager.xcodeproj -scheme dev-manager \
    -configuration "${CONFIGURATION:-Debug}" \
    -destination 'platform=macOS,arch=arm64' \
    -derivedDataPath /tmp/dev-manager-repo-aware-tests \
    CODE_SIGNING_ALLOWED=NO "$@"
}
```

Step 0.1 must confirm the installed Xcode/toolchain and destination against the production support matrix. Missing access/tooling is a blocker, not a reason to invent successful results. Focused commands use `xb test -only-testing:dev-managerTests/<Suite>`. New suites named below are **proposed additions in their owning steps**, not currently runnable tests; declare matching named `@Suite` types so their selectors are stable. Current `ProjectStoreTests.swift` contains free test functions: Step 3.1 wraps them in a matching named suite before any focused command uses that selector. Confirm that each inclusion selector selects nonzero intended tests and each exclusion actually excludes its intended suite; a zero-test pass or ineffective live exclusion is not verification. `xb build` proves unsigned compilation, not signed/installed app acceptance. No package installation is part of these deterministic commands.

## Phase overview and delivery boundary

| Phase | Outcome | Dependencies | Exit gate |
| --- | --- | --- | --- |
| 0 | Production handoff, baseline, and safe integration constraints established | Production provisioning prerequisite | G0: Step 0.1 baseline and provider-contract review |
| 1 | Bounded metadata discovery and explainable concrete requirements | G0 | G1: Discovery and resolution compose without execution or writes |
| 2 | Isolated tools, structured invocation, and approved setup coordination | G1 | G2: Deterministic composition plus approved live multi-version proof |
| 3 | Compatible guided/custom projects and the visible add/setup/run workflow | G2 | G3: End-to-end fake-provider workflow and custom regression proof |
| 4 | Separate approved dependency installation with owned lifecycle | G3 | G4: Install approval, workspace conflicts, cancellation, and quit compose |
| 5 | Full regression and supported-machine user acceptance | G4 | G5: All AC ownership gates and live application acceptance accounted for |

Delivery boundary: one feature-complete PR after G5, with these steps as reviewable increments rather than independently promised releases. Every intermediate change must compile and preserve the existing custom workflow. No publish, deploy, or release action is included.

Atomic groups: Step 3.1's model/format reader/writer/runner/consumer changes land and revert together. Step 2.2's launcher contract and immediate consumers/tests are one unit. Existing custom launch is retained, not removed after managed-path introduction.

## Phase 0 — Production handoff and baseline

Outcome: execution has a reproducible baseline and an identified, safe production integration boundary.
Depends on: production provisioning available before feature work starts.
Review boundary: read-only source/API/platform review and baseline verification; no application changes, installs, or new harness.

### Step 0.1 — Establish the provider contract and execution baseline

Requirements / acceptance: R4, R8, R9; preconditions for AC8, AC9, AC10, AC15, and AC17, not acceptance of the new behavior.
Depends on: the explicit production-provisioning prerequisite.
Review boundary: record existing facts and blockers without implementing or weakening the contract.

Expected files:

- `dev-manager/Provisioning/`, `dev-manager/Runs/`, `dev-manager/Projects/`, `dev-manager/App/` — inspect production handoff and current consumers; no edits.
- `dev-manager.xcodeproj/project.xcproj`, shared scheme, `README.md`, existing tests/evidence — inspect tooling and compatibility constraints.
- `plans/repo-aware-execution/evidence/step-0.1.md` — create concise baseline/contract evidence.

Tasks:

- [ ] Confirm production provisioning support matrix, inspection/available-version/install/cancel/reconcile APIs, absolute tool-location access, trusted installation context, and external-installer completion semantics. Record source references and any capability this feature must extend.
- [ ] Identify the isolated manager-supply strategy: distinct immutable manager locations per concrete Node/manager/version combination, no npm-global replacement shared by projects, no repository-local configuration during tool setup. Identify how implicit shim downloads will be disabled. If no safe strategy exists, stop for a decision rather than advancing.
- [ ] Confirm actual test selectors/folder inclusion and settings format; run the baseline checks below, separating pre-existing failures from regressions. Preserve all unrelated working-tree changes.
- [ ] Satisfy the verification and completion gate below, and record concise evidence.

Verification:

- Automated: run `xb build` and `xb test` against the existing checkout, before the proposed live suite exists. Record selected test counts and any baseline failures; no runtime installations or project scripts are authorized by this check.
- Manual/source: review the actual production provider against each capability above. Record the supported-machine approval/access owner for G2; source/API inspection is not live isolation proof.

Completion gate: production handoff and safe integration strategy are identified; baseline results and constraints are reproducible. An unresolved failure affecting persistence, process ownership, or the provider blocks affected work; any proposed prerequisite fix requires an agreed plan change rather than an unlisted repair.
Evidence location: [evidence/step-0.1.md](evidence/step-0.1.md).

Phase exit gate **G0**: after Step 0.1 verification, confirm the production prerequisite, viable isolation boundary, and usable verification setup. Record the outcome in Step 0.1's note before any dependent work or supervised approval to advance. Missing live approval is explicitly reserved for G2; missing production APIs/strategy is not.

## Phase 1 — Declarative project understanding

Outcome: selected folders yield bounded metadata, workspace provenance, script choices, and deterministic requirement diagnostics without invoking processes.
Depends on: G0.
Review boundary: pure filesystem/data/resolution code and tests; no add-flow activation, machine mutation, or process changes.

### Step 1.1 — Read package and workspace metadata safely

Requirements / acceptance: R1, R2, R9; AC1 and AC2 (discovery portions), AC6 (inheritance portion), AC16 (filesystem portion). UI/runnable coverage belongs to Steps 3.2/5.2; machine-install isolation belongs to Step 2.1.
Depends on: Step 0.1 and G0.
Review boundary: declarative metadata and containment only.

Expected files:

- `dev-manager/Projects/Discovery/ProjectMetadata.swift`, `ProjectMetadataReader.swift`, `WorkspaceDiscovery.swift` — add read-only metadata/provenance, bounded reads, and workspace membership.
- `dev-managerTests/Projects/ProjectMetadataDiscoveryTests.swift` — add temporary-folder fixtures and read/write/execution spies; create fixtures in tests rather than introducing an executable fixture dependency.

Tasks:

- [ ] Represent recognized/unrecognized/diagnostic results, scripts, version declarations, lockfile evidence, registered cwd, and canonical workspace identity separately; preserve provenance rather than persisting a duplicate source of truth.
- [ ] Implement selected-folder/ancestor-only inspection, declared npm/pnpm workspace membership, Git-boundary stopping, 1 MiB parsed-file bounds, and symlink containment. Unsupported workspace syntax must be diagnosed, not treated as evidence of membership.
- [ ] Add fixtures for no/malformed manifest, root and package folders, unrelated/nested ancestors, Git boundaries, missing Git, oversized/unreadable input, escaping symlinks, and scripts/version content that would create a marker if executed.
- [ ] Satisfy the verification and completion gate below, and record concise evidence.

Verification:

- Automated: `xb test -only-testing:dev-managerTests/ProjectMetadataDiscoveryTests`. Assert expected metadata/provenance and unchanged registered cwd; no subprocess invocation, marker creation, repository write, or recursive descendant scan. Oversized/symlink/unreadable cases produce diagnostics without unbounded reads.
- Manual: not required for this data-only increment; user-visible fallback is verified in Phase 3.

Completion gate: bounded discovery handles both workspace inheritance and safe failure with no side effects; the app still builds and retains its existing workflow.
Evidence location: [evidence/step-1.1.md](evidence/step-1.1.md).

### Step 1.2 — Resolve concrete requirements and script suggestions

Requirements / acceptance: R2; AC3, AC4, AC5 (resolution portions). Argument safety belongs to Step 2.2; displayed warnings/suggestions to Step 3.2.
Depends on: Step 1.1.
Review boundary: pure requirement selection against injected installed/available versions, not network lookup or installation.

Expected files:

- `dev-manager/Projects/Discovery/ProjectRequirementResolver.swift`, `NodeVersionRequirement.swift` — add supported literal/range parsing, compatibility, precedence, defaults, and diagnostics.
- `dev-managerTests/Projects/ProjectRequirementResolverTests.swift` — add table-driven resolution and script-suggestion coverage.

Tasks:

- [ ] Implement the spec's Node selector/engine intersection, packageManager authority, conflicting-lockfile handling, npm fallback, concrete-version policy, and declaration/default provenance. Unsupported aliases/expressions/locations remain data with attention diagnostics.
- [ ] Select `dev` only when declared, otherwise expose actual scripts/custom choice. Retain package-script names verbatim as data; do not construct executable shell fragments.
- [ ] Cover exact/partial/range inputs, package/root incompatibility, installed-versus-available selection, absent constraints/defaults, npm/pnpm pins, unsupported managers, lower-priority lockfile warnings, and unavailable exact pins without fallback.
- [ ] Satisfy the verification and completion gate below, and record concise evidence.

Verification:

- Automated: `xb test -only-testing:dev-managerTests/ProjectRequirementResolverTests -only-testing:dev-managerTests/ProjectMetadataDiscoveryTests`. Feed fake version inventories and compare concrete requirements, sources, warnings, and blocked cases. Assert no provider/process/write calls from resolution.
- Manual: not needed; no network service or UI behavior is claimed by these fixtures.

Completion gate: deterministic requirements and honest diagnostics satisfy the resolution contract, including every accepted default, without consulting an executable from the repository.
Evidence location: [evidence/step-1.2.md](evidence/step-1.2.md).

Phase exit gate **G1**: rerun both suites above and `xb build` after Step 1.2. Compose temporary workspace discovery with fake inventories and assert the resolved cwd/provenance/script/tool tuple and unchanged marker/files. Record in Step 1.2's note before Phase 2 or approval to advance.

## Phase 2 — Isolated tools and approved setup operations

Outcome: concrete toolchains can be prepared safely, invoked without shell-selected runtimes, and coordinated through explicit, stale-safe approvals.
Depends on: G1 and the production provider contract established at G0.
Review boundary: production adapter, managed execution primitives, and operation state; no user-facing guided-mode activation yet.

### Step 2.1 — Adapt provisioning for isolated concrete toolchains

Requirements / acceptance: R3, R4, R9; AC4 (provider-backed inventory portion), AC8 (provider/isolation portion), AC16 (machine-install context portion). Live invocation proof belongs to G2; visible approval belongs to Phase 3.
Depends on: Step 1.2 and G1.
Review boundary: exact-version inventory/locations/install adapter; do not productionize or duplicate foundational machine setup.

Expected files:

- `dev-manager/Toolchains/ProjectToolchainProvider.swift`, `ManagedToolchain.swift` — add injectable production-provider boundary and concrete immutable tool locations.
- `dev-manager/Provisioning/` — narrowly extend the production service identified at G0 for project-specific version supply/cancellation where missing; do not assume the old fixed-pair installer is sufficient.
- `dev-managerTests/Toolchains/ProjectToolchainProviderTests.swift` — add fake-provider/command-location assertions.

Tasks:

- [ ] Adapt installed/available version inspection and exact tool lookup without triggering an install. Return absolute Node and manager entry points plus explicit unsupported/missing results.
- [ ] Supply approved concrete managers in isolated locations, including pinned npm and two pnpm versions on one Node. Preserve all existing versions/global defaults/profiles; use a trusted non-repository setup context and no repo-local npm/pnpm configuration or hooks.
- [ ] Expose cancellable install/reconcile results, including incomplete or externally unresolved work. Keep mutation inaccessible to discovery/Run; exercise the installer only through explicit test approval tokens in deterministic fakes.
- [ ] Satisfy the verification and completion gate below, and record concise evidence.

Verification:

- Automated: `xb test -only-testing:dev-managerTests/ProjectToolchainProviderTests`. Assert separate locations for distinct manager pins, unavailable-pin attention/no fallback, no installs on inspection, no global replacement/profile/default change, clean setup cwd/config, and partial/cancellation result fidelity.
- Manual/source: review the production adapter against G0's strategy; fake paths do not establish live package-manager compatibility. No real download is required for this step's focused gate.

Completion gate: exact tool requests and unsupported results are represented truthfully and deterministic tests prove the adapter's invocation boundaries. No code outside approved operations can call its mutation path.
Evidence location: [evidence/step-2.1.md](evidence/step-2.1.md).

### Step 2.2 — Add structured managed process invocation

Requirements / acceptance: R4, R5, R9; AC3 (argument safety), AC6 (cwd portion), AC8 (controlled/live invocation portion), AC10 (launcher regressions). Full runner wiring belongs to Step 3.1; live isolation is required at G2.
Depends on: Step 2.1.
Review boundary: typed invocation and owned process launch alongside, not replacing, the custom shell path.

Expected files:

- `dev-manager/Runs/ProcessInvocation.swift`, `ProcessLauncher.swift`, `ShellEnvironment.swift` — add absolute executable/argv/environment/cwd launch and reuse pipe/process-group cleanup safely.
- `dev-manager/Toolchains/ManagedToolchain.swift` — add managed preflight/invocation construction and no-self-download policy.
- `dev-managerTests/Runs/ManagedProcessInvocationTests.swift`, `dev-managerTests/Toolchains/ManagedToolchainLiveTests.swift` — add local executable fixtures and an explicitly opt-in live suite.
- `dev-manager.xcodeproj/project.xcproj`, `dev-manager.xcodeproj/xcshareddata/xcschemes/dev-manager.xcscheme` — add a default-off test opt-in build setting and explicit TestAction environment forwarding, not a permanently enabled live flag.

Tasks:

- [ ] Add a structured launch path with the selected Node interpreter for JavaScript manager entry points and selected-Node environment for child scripts. Never send generated commands through login startup/eval or depend on a manager shebang selecting Node.
- [ ] Validate actual Node/manager versions in the same managed context and disable shim/manager implicit downloads or version switching. Missing/mismatched tools return a requirement result, not a corrective install.
- [ ] Add local process tests for argv metacharacters, cwd, stderr/stdout, noninteractive stdin, descendants/cleanup, and hostile shell-startup/shim choices; keep the existing custom launcher tests intact.
- [ ] Add opt-in live tests using disposable packages and approved production tool supply. Add build setting `REPO_AWARE_LIVE_TEST_OPT_IN=0` by default and explicitly forward `$(REPO_AWARE_LIVE_TEST_OPT_IN)` as TestAction environment variable `DEV_MANAGER_ALLOW_LIVE_TOOLCHAIN_TESTS`. The live suite reads `ProcessInfo.processInfo.environment` and performs no mutation unless the observed value is exactly `1`; absent/other values safely skip live work. Test the guard with absent/0/1/other inputs. For an approved G2 run, record the value actually observed in the test process and require nonzero executed live cases, not skipped tests. Record actual Node/manager entry-point paths, child `process.execPath`/version, and unchanged defaults/profiles. Never commit the shared setting or scheme with live work permanently enabled.
- [ ] Satisfy the verification and completion gate below, and record concise evidence.

Verification:

- Automated/local: `xb test -only-testing:dev-managerTests/ManagedProcessInvocationTests -only-testing:dev-managerTests/ProjectRunnerTests`. Local fixtures prove launch mechanics, safe argument boundaries, selected interpreter use, cleanup, and unchanged custom behavior without real managers.
- Approval-required live: the G2 command below exercises the newly added opt-in suite. A skipped or unapproved live suite is not isolation proof.

Completion gate: structured invocation works with local processes and preserves custom launch behavior. The live suite exists without running by default; Phase 2 cannot exit until its separate live gate passes.
Evidence location: [evidence/step-2.2.md](evidence/step-2.2.md).

### Step 2.3 — Coordinate approvals, stale results, and operation ownership

Requirements / acceptance: R3, R4, R7, R9; AC7, AC14, AC15, AC17 (operation-state portions). Actual runner/UI composition belongs to Phase 3 and final live recovery to Step 5.2.
Depends on: Steps 1.2, 2.1, and 2.2.
Review boundary: shared coordinator/state machine and workspace leases, tested independently from SwiftUI.

Expected files:

- `dev-manager/Toolchains/ProjectSetupCoordinator.swift`, `ProjectReadiness.swift`, `WorkspaceOperationRegistry.swift` — add shared machine-install queue, requirement snapshots, and workspace ownership.
- `dev-managerTests/Toolchains/ProjectSetupCoordinatorTests.swift`, `WorkspaceOperationRegistryTests.swift` — add controllable async provider and cancellation/completion fixtures.

Tasks:

- [ ] Model inspection/attention/setup-needed/waiting/setting-up/ready/failure/cancellation separately. Bind approval to the concrete snapshot, registered folder, and operation; revalidate before dequeuing work and ignore stale completion as proof of new readiness.
- [ ] Serialize machine installations across all projects; cancel queued work without invoking the provider. Hold active ownership until completion or safe provider reconciliation, including external handoffs with unknown results.
- [ ] Add canonical workspace leases for mutation/dev-run conflicts and release only after owned work is reconciled. Unrelated ready projects remain runnable; no dependency operation is implicitly started.
- [ ] Test changed metadata/version inventories, partial install and retry, cancelled queue/active work, duplicate approvals, cleanup failure, and foreign workspace identities with controllable completions.
- [ ] Satisfy the verification and completion gate below, and record concise evidence.

Verification:

- Automated: `xb test -only-testing:dev-managerTests/ProjectSetupCoordinatorTests -only-testing:dev-managerTests/WorkspaceOperationRegistryTests -only-testing:dev-managerTests/ProjectToolchainProviderTests`. Assert at most one provider mutation globally, zero calls from unapproved/queued-cancelled/stale requests, no premature readiness or ownership release, and correct reconciliation/retry.
- Manual: no live mutation required for the state-machine increment; test leases stand in for runner activity until Step 3.1.

Completion gate: every transition and approval boundary has a deterministic positive and negative assertion; incomplete cleanup is visible rather than treated as success.
Evidence location: [evidence/step-2.3.md](evidence/step-2.3.md).

Phase exit gate **G2**: after Step 2.3, run all Phase 2 deterministic suites together and `xb build`. With explicit machine/download approval and supported-machine access, run `xb test REPO_AWARE_LIVE_TEST_OPT_IN=1 -only-testing:dev-managerTests/ManagedToolchainLiveTests`. Require the forwarded opt-in value observed by the test process to be exactly `1` and the intended live cases to execute; skipped/zero-test output cannot pass G2. Exercise two supported Node versions, two pnpm versions sharing one Node, a shell selecting a third toolchain, and a missing/unavailable exact pin. A request for pinned npm distinct from bundled npm must either run the isolated exact version or demonstrate an explicit provider-unavailable attention result with no bundled/global fallback; this case cannot be silently skipped. Observe actual executable/child versions and unchanged other-project tools, profiles, and global defaults; no hidden shim installation is permitted. Record the composed gate and link Step 2.2's live proof in Step 2.3's note. If approval/access is missing or any isolation case fails, stop before Phase 3; never substitute mocked proof or a globally replaced manager. Assess G2 before supervised approval to advance.

## Phase 3 — Compatible guided projects and the visible workflow

Outcome: users can add/adopt a guided project, understand its readiness, approve setup, and run the selected script while old projects retain custom semantics.
Depends on: G2.
Review boundary: atomic persistence/runner integration followed by UI activation; no dependency-install action yet.

### Step 3.1 — Wire the compatible model and guided runner atomically

Requirements / acceptance: R4, R5, R7, R8, R9; AC8 (runner portion), AC9 (format portion), AC10, AC11 (no implicit install), AC14 (next-run portion), AC15 (dev-run lease portion). UI adoption belongs to Step 3.2.
Depends on: Step 2.3 and G2.
Review boundary: one atomic model/reader/writer/runner/consumer change; no intermediate format or guided state may launch through the old shell path.

Expected files:

- `dev-manager/Projects/Project.swift`, `ProjectStore.swift` — add explicit guided/custom intent and compatibility-preserving versioned persistence.
- `dev-manager/Runs/ProjectRunner.swift`, `ProcessSupervisor.swift` — dispatch typed managed/custom execution, preserve lifecycle/output, and acquire/release workspace run leases.
- `dev-manager/App/DevManagerApp.swift`, `AppLifecycle.swift` — compose shared services and include owned setup work in cleanup.
- `dev-manager/Projects/Views/ProjectSettingsSheet.swift`, `ProjectSidebar.swift`, `ProjectDetailView.swift` — update immediate consumers to represent the new model safely without activating the add/adoption flow yet.
- `dev-managerTests/Projects/ProjectStoreTests.swift`, `dev-managerTests/Runs/ProjectRunnerTests.swift`, `GuidedProjectRunnerTests.swift` — update fixtures and add migration/managed-run checks together.

Tasks:

- [ ] Preserve UUID, registered path, and original custom command; decode schema-1 projects as custom. Add explicit guided script intent without treating detected metadata as authoritative persisted settings. Evolve readers/writers together against the format present after the production handoff.
- [ ] Back up the prior readable settings before the first upgraded-format write, preserve atomic writes/read-only failure handling, and test interrupted/missing/corrupt/future-version input and round trips. Wrap the existing free store tests in a named `ProjectStoreTests` suite without dropping cases so the focused selectors below become valid. Do not overwrite unreadable settings or silently discard concurrent/unrelated records.
- [ ] Dispatch guided starts through fresh resolution/preflight/structured invocation and custom starts through the retained zsh path. Missing tools block guided Run without installation; dependency history is not a launch gate.
- [ ] Preserve logs, Stop, overlap rejection, next-start settings semantics, and quit cleanup. Acquire workspace run leases before launch and release after failed start/exit/cleanup; changing requirements must not restart a live process.
- [ ] Update all consumers/tests atomically and check remaining command/shell-spawn call sites so no guided case can fall through to eval or a stale raw command.
- [ ] Satisfy the verification and completion gate below, and record concise evidence.

Verification:

- Automated: `xb test -only-testing:dev-managerTests/ProjectStoreTests -only-testing:dev-managerTests/ProjectRunnerTests -only-testing:dev-managerTests/GuidedProjectRunnerTests -only-testing:dev-managerTests/WorkspaceOperationRegistryTests`. Assert schema-1 preservation/adoption round trips, safe unsupported data, no install on Run or failure, managed/custom dispatch, stream/cwd/cleanup behavior, leases, and no implicit restart.
- Source/build: `xb build`; inspect `command`, shell/eval, and `ProcessLauncher` consumers to confirm the managed/custom separation. This supplements, not replaces, behavioral launch tests.

Completion gate: all persisted representations and consumers agree, the old custom path remains usable, and a model-created guided project runs only through the verified managed path. Treat this entire step as the migration/revert unit.
Evidence location: [evidence/step-3.1.md](evidence/step-3.1.md).

### Step 3.2 — Expose recognition, script adoption, and requirements banner

Requirements / acceptance: R1, R2, R3, R5, R7, R8; AC1–AC7 (user-facing portions), AC9 (adoption portion), AC11 (setup separation), AC14/AC15/AC17 (visible setup states). Live app acceptance belongs to Step 5.2.
Depends on: Step 3.1.
Review boundary: guided add/settings/top-banner interaction composed with completed discovery/setup/runner services.

Expected files:

- `dev-manager/App/ContentView.swift`, `DevManagerApp.swift` — add asynchronous folder inspection/confirmation and pass shared feature services.
- `dev-manager/Projects/Views/ProjectAddSheet.swift`, `ProjectRequirementsBanner.swift`, `ProjectDetailView.swift`, `ProjectSettingsSheet.swift`, `ProjectSidebar.swift` — add recognition/script/custom choice and honest readiness/adoption presentation.
- `dev-manager/Projects/ProjectWorkflowModel.swift` — add testable action presentation/state orchestration if needed, without duplicating coordinator ownership.
- `dev-managerTests/Projects/ProjectWorkflowTests.swift` — add fake-provider/discovery/store/runner composition tests.

Tasks:

- [ ] Replace blind default registration with bounded inspection and explicit script/custom selection. Keep cancellation from adding an unwanted project, and retain custom fallback for absent/malformed/unsupported metadata without requiring Git.
- [ ] Render the requirements banner before execution/output, including sources/concrete versions, attention diagnostics, waiting/progress/cancel/retry, and Set up requirements approval for the displayed snapshot.
- [ ] Expose explicit guided adoption/script selection and visible custom switching. Existing custom projects show advisory detection/adoption only: no managed setup or dependency action before adoption, and custom Run stays usable.
- [ ] Refresh on relevant app actions and before operations. Disable only conflicting actions, keep unrelated projects usable, and show that changed requirements apply next run. Tool-ready presentation must not claim dependency freshness or trigger installation.
- [ ] Add action-level composition tests for no mutation on add/Run, stale-banner approval, cancelled/failed setup, current readiness after reinspection, no-script choice, and existing-project adoption without command loss. For no-manifest, malformed-manifest, and non-Node fallback folders, actually run a benign custom marker/cwd command through the custom runner and assert its output with zero managed setup/dependency calls.
- [ ] Satisfy the verification and completion gate below, and record concise evidence.

Verification:

- Automated: `xb test -only-testing:dev-managerTests/ProjectWorkflowTests -only-testing:dev-managerTests/ProjectSetupCoordinatorTests -only-testing:dev-managerTests/GuidedProjectRunnerTests -only-testing:dev-managerTests/ProjectStoreTests`. Use fake providers to prove actual UI actions route to the correct operations without hidden installs or silent custom migration.
- Manual/local: launch the Debug app against disposable project folders with no/invalid manifest, scripts with/without `dev`, and a supported Node package. Check top-of-view placement, script/custom entry, effective versions/provenance, custom adoption controls, and keyboard/action availability. In each unrecognized/malformed/non-Node fallback, run `printf 'custom-fallback-ok\n'; pwd` and observe the marker and selected cwd without Git, managed setup, or dependency installation. Do not approve real installation for this local check; full banner progress/recovery is an approved Step 5.2 check.

Completion gate: the visible add → inspect → adopt → setup/run path composes with fake services, and local rendering preserves custom usability and the approval boundary.
Evidence location: [evidence/step-3.2.md](evidence/step-3.2.md).

Phase exit gate **G3**: after Step 3.2, run Phase 3 suites with Phase 1/2 resolver/coordinator suites and `xb build`. Through the workflow model, compose add → detected missing requirements → unapproved Run → approved fake setup → reinspection → guided script launch; assert zero dependency installs and correct workspace/cwd. Also load schema-1 custom projects and run one without guided adoption, and execute benign custom fallback commands from absent/malformed/non-Node manifests with observed marker/cwd output and zero install calls. Record in Step 3.2's note before Phase 4 or supervised approval to advance.

## Phase 4 — Separately approved project dependencies

Outcome: dependency installation is a disclosed, separately owned operation with correct commands, tools, conflicts, output, and recovery.
Depends on: G3.
Review boundary: dependency operations and their UI/lifecycle integration; no automatic pre-start hooks or dependency upgrades.

### Step 4.1 — Implement managed dependency-operation lifecycle

Requirements / acceptance: R4, R6, R7, R9; AC6 (install cwd), AC12 (command/tool portion), AC13, AC15 (dependency conflict portion). Approval presentation belongs to Step 4.2.
Depends on: Step 3.2 and G3.
Review boundary: install command policy and owned subprocess service using completed toolchain/lease primitives.

Expected files:

- `dev-manager/Dependencies/DependencyInstallPlan.swift`, `DependencyInstallCoordinator.swift` — add immutable approved operation description, command policy, finite budget, result/output/cancellation.
- `dev-manager/Runs/ProcessLauncher.swift`, `OutputReader.swift`, `LogBuffer.swift` — reuse/extract bounded process mechanics only as needed without changing custom-run semantics.
- `dev-managerTests/Dependencies/DependencyInstallCoordinatorTests.swift` — add managed local-process fixtures and fake invocation assertions.

Tasks:

- [ ] Build disclosed npm ci/install and pnpm frozen/install plans from current applicable lockfile evidence, resolved tools, registered cwd, and workspace identity. Never retry locked failure as an unlocked install.
- [ ] Require operation-specific approval/current snapshot, ready tool preflight, and workspace mutation ownership; reject conflicts with app-managed runs, and never invoke the machine installer to repair tools implicitly.
- [ ] Stream bounded operation-specific output and exit status with stdin closed. Use a finite dependency budget independent of shell readiness, with a 15-minute default and injectable shorter test deadlines; preserve process-group cleanup and honest partial-state reporting.
- [ ] Test success, nonzero/locked failure, a command longer than the configured startup budget, EOF/prompt-like behavior, timeout, cancellation/descendants, cleanup failure, stale approval, and workspace conflicts.
- [ ] Satisfy the verification and completion gate below, and record concise evidence.

Verification:

- Automated: `xb test -only-testing:dev-managerTests/DependencyInstallCoordinatorTests -only-testing:dev-managerTests/WorkspaceOperationRegistryTests -only-testing:dev-managerTests/ManagedProcessInvocationTests`. Assert exact argv/tools/cwd, no unlocked retries or hidden tool install, bounded drains, independent deadlines, owned-process cleanup, and visible uncertainty/failure. Use local helper commands, not network dependency installation.
- Manual: no live dependency scripts required for this service gate; no approval/UI claim until Step 4.2.

Completion gate: approved dependency plans run through managed tools with separate finite lifecycle/output and no interference with unrelated projects or dev-run state.
Evidence location: [evidence/step-4.1.md](evidence/step-4.1.md).

### Step 4.2 — Add install disclosure, output, and application cleanup

Requirements / acceptance: R3, R5, R6, R7, R9; AC11, AC12 (approval portion), AC13 (visible recovery), AC14/AC15 (install composition). Approved live behavior belongs to Step 5.2.
Depends on: Step 4.1.
Review boundary: visible approval/action and shared lifecycle, not a second execution engine.

Expected files:

- `dev-manager/Projects/Views/ProjectDetailView.swift`, `ProjectRequirementsBanner.swift`, `DependencyInstallView.swift` — disclose command/cwd/workspace/script risk and show separate output/result/cancel/retry.
- `dev-manager/Projects/ProjectWorkflowModel.swift`, `dev-manager/App/DevManagerApp.swift`, `AppLifecycle.swift`, `ContentView.swift` — compose dependency services and safe removal/quit handling.
- `dev-managerTests/Projects/ProjectWorkflowTests.swift`, `dev-managerTests/Dependencies/DependencyInstallCoordinatorTests.swift`, `dev-managerTests/App/ProjectOperationLifecycleTests.swift` — add approval/action and cleanup composition tests.

Tasks:

- [ ] Offer Install dependencies only for guided projects with ready tools. Display the exact plan and lifecycle-script/shared-workspace warning before the approving action; tools Ready remains distinct from dependency result/freshness.
- [ ] Bind visible approval to the current plan, render output/nonzero/cancelled/incomplete states, and provide fresh-plan retry rather than hidden retries or rollback claims. Absence of app install history must not disable Run.
- [ ] Coordinate Stop/cancel, project removal, and quit with owned setup/dependency/dev work. Do not remove ownership or report external provider cancellation complete while its result is unknown; unrelated projects remain usable.
- [ ] Prove from actual workflow actions that add, machine setup, Run, and dev-command failure never start dependency installation, and custom mode never exposes the managed install action.
- [ ] Satisfy the verification and completion gate below, and record concise evidence.

Verification:

- Automated: `xb test -only-testing:dev-managerTests/ProjectWorkflowTests -only-testing:dev-managerTests/DependencyInstallCoordinatorTests -only-testing:dev-managerTests/ProjectOperationLifecycleTests -only-testing:dev-managerTests/ProjectRunnerTests`. Assert approval ordering, stale-plan refusal, separate logs/results, same-workspace denial, unrelated operation continuity, and quit/removal cleanup without fabricated rollback.
- Manual/local: view the disclosure in a disposable project without approving installation; check command/cwd/workspace/script warning and distinct tool/dependency status. Live install/cancellation is reserved for Step 5.2 with explicit approval.

Completion gate: user actions and app lifecycle compose with the separate dependency service; no hidden dependency installation path exists.
Evidence location: [evidence/step-4.2.md](evidence/step-4.2.md).

Phase exit gate **G4**: after Step 4.2, compose add → setup-ready → separate dependency approval → fake/local install output → Run with no implicit install. Include stale approval, active-workspace conflict, queued setup cancellation, and quit during owned work. Run the Phase 4/3 workflow and lifecycle suites and `xb build`; record in Step 4.2's note before Phase 5 or supervised approval to advance.

## Phase 5 — Regression and supported-machine acceptance

Outcome: deterministic behavior, production-build availability, and actual user-facing isolation/approval/recovery are evidenced without claiming mocks prove live compatibility.
Depends on: G4.
Review boundary: composition verification, representative fixture coverage, and approved live acceptance; no new feature scope or speculative cleanup.

### Step 5.1 — Close deterministic composition and build gates

Requirements / acceptance: R1–R9; deterministic portions of AC1–AC17. This does not replace G2's real-tool proof or Step 5.2's visible application acceptance.
Depends on: Step 4.2 and G4.
Review boundary: missing cross-component assertions and regression/build proof, not the first tests for earlier implementations.

Expected files:

- `dev-managerTests/Projects/ProjectWorkflowTests.swift`, `dev-managerTests/App/ProjectOperationLifecycleTests.swift` — add only missing cross-component negative cases and fixtures.
- `plans/repo-aware-execution/evidence/step-5.1.md` — deterministic regression/build evidence with references to owning step notes.

Tasks:

- [ ] Audit actual consumers and AC coverage; close deterministic gaps for safe add, workspace inheritance, exact pins, guided/custom dispatch, migration, stale approvals, global serialization, dependency separation, and cleanup.
- [ ] Run the broader deterministic test suite explicitly excluding the opt-in live suite; compare results with G0 rather than assuming an always-green baseline.
- [ ] Build Debug and Release unsigned app artifacts, confirming new runtime/setup/UI code does not depend on DEBUG-only spike types or disappear in Release. Do not delete the custom launcher or historical evidence.
- [ ] Satisfy the verification and completion gate below, and record concise evidence.

Verification:

- Automated: `xb test -skip-testing:dev-managerTests/ManagedToolchainLiveTests`, `xb build`, and `CONFIGURATION=Release xb build`. Expected: intended deterministic tests run, no new failures, both app configurations compile, and production feature sources are included. Explicit live exclusion is not acceptance of G2/Step 5.2.
- Source review: inspect remaining shell/eval/global-install and settings-format consumers; confirm guided mode cannot reach custom eval, hidden mutation, or debug-only services. Explain any remaining uses by their custom/provisioning ownership.

Completion gate: deterministic AC portions and unchanged regressions have evidence, Debug/Release compile, and no unresolved safety failure is hidden behind a baseline issue or skip.
Evidence location: [evidence/step-5.1.md](evidence/step-5.1.md).

### Step 5.2 — Exercise the application and reconcile final acceptance

Requirements / acceptance: R1–R9; live/UI closure for AC1–AC17 with owning deterministic proofs linked below.
Depends on: Step 5.1, G2's live proof, supported-machine access, and explicit tool/download/dependency-script approval.
Review boundary: real user workflow and observed artifacts; no automatic release or new implementation scope.

Expected files:

- `plans/repo-aware-execution/evidence/step-5.2.md` — concise live setup/actions/outcomes and final gate references; raw logs only if necessary to explain a blocker.
- Disposable project/settings/tool directories on the approved supported machine — acceptance artifacts only, outside tracked source; preserve pre-existing user tools and repositories.

Tasks:

- [ ] Obtain actual approval identifying the test machine/account, concrete tool downloads, disposable package/workspace locations, and allowed lifecycle scripts. Prepare marker scripts and version-reporting dev scripts with no secrets or external project dependencies.
- [ ] In the app, add recognized/unrecognized/malformed folders and a workspace package, choose/adopt scripts, and verify selected cwd/provenance. In each no-manifest/malformed/non-Node fallback, execute the benign custom marker/cwd command and observe output without Git or managed/dependency setup. Before guided setup approval, inspect marker/files/tool inventory: inspection changed nothing and guided Run did not install. Approve the disclosed banner setup and observe progress/reinspection.
- [ ] Run two projects with differing toolchains, including same-Node/different-pnpm and pinned npm cases. Observe executable/child versions despite a third shell-selected toolchain; verify other-project versions, global defaults, and profiles remain unchanged. Exercise custom-mode compatibility and next-run changes.
- [ ] Separately approve dependency installation and verify the disclosed command/scope/script warning and operation output. Exercise locked failure, cancellation/partial state, retry, stale requirements, queued setup cancellation, workspace conflict, and Stop/quit cleanup using controlled disposable fixtures and provider-supported recovery.
- [ ] Reconcile every AC with the owning evidence below, distinguishing deterministic, live, manual, and build proof. Leave any blocked/failed/skipped required gate unchecked with its owner and follow-up; do not call a waiver acceptance.
- [ ] Satisfy the verification and completion gate below, and record concise evidence.

Verification:

- Manual/live: on an approved production-supported machine, use the app build whose revision is recorded, real production provisioning, and the disposable fixtures above. Expected: displayed requirements/commands match observed processes, only approved actions mutate state, custom projects remain usable, workspace cwd never silently changes, and failure/cancellation is honest and recoverable. Reuse G2 evidence only when provider/launcher code and tool artifacts are unchanged; otherwise rerun the opt-in live suite with renewed approval as needed.
- Artifact/boundary: launch a locally runnable Release configuration and confirm guided recognition/banner/setup/run/dependency controls are present and backed by production services. Signing or local execution restrictions are explicit blockers owned by the approving user, not inferred success from an unsigned build. No publication is required.

Completion gate: all ACs have their specified owning proof, G0–G4 and Step 5.1 are satisfied, supported-machine live/application checks pass, and no approval-required or recovery check is silently deferred.
Evidence location: [evidence/step-5.2.md](evidence/step-5.2.md).

Phase exit gate **G5**: after Step 5.2 verification, reconcile the final acceptance table with its evidence and record the conclusion in Step 5.2's note. Assess before requesting final supervised acceptance. This gate does not authorize merge, publication, or release.

## Final acceptance

| Spec acceptance ID | Owning step / gate | Verification and expected result | Evidence location |
| --- | --- | --- | --- |
| AC1 | 1.1, 3.2; G3 and 5.2 | Discovery/action spies plus live add show suggestions without scripts, downloads, or writes. | [1.1](evidence/step-1.1.md), [3.2](evidence/step-3.2.md), [5.2](evidence/step-5.2.md) |
| AC2 | 1.1, 3.2; G3 and 5.2 | Missing/malformed/non-Node folders actually run the custom marker/cwd command without Git, managed setup, or dependency installation. | [1.1](evidence/step-1.1.md), [3.2](evidence/step-3.2.md), [5.2](evidence/step-5.2.md) |
| AC3 | 1.2, 2.2, 3.2 | Declared script suggestions only; metacharacter names remain one structured argument; visible choice works. | [1.2](evidence/step-1.2.md), [2.2](evidence/step-2.2.md), [3.2](evidence/step-3.2.md) |
| AC4 | 1.2, 2.1, 3.2 | Fake inventories and provider adapter resolve concrete compatible tools; UI shows sources/defaults. | [1.2](evidence/step-1.2.md), [2.1](evidence/step-2.1.md), [3.2](evidence/step-3.2.md) |
| AC5 | 1.2, 3.2 | Conflict/unsupported fixtures block guessing; authoritative manager warnings and correction/custom choices are visible. | [1.2](evidence/step-1.2.md), [3.2](evidence/step-3.2.md) |
| AC6 | 1.1, 2.2, 4.1; 5.2 | Workspace fixtures prove bounded inheritance; run/install probes and live app retain registered cwd. | [1.1](evidence/step-1.1.md), [2.2](evidence/step-2.2.md), [4.1](evidence/step-4.1.md), [5.2](evidence/step-5.2.md) |
| AC7 | 2.3, 3.2; 5.2 | Coordinator/workflow and real banner prove install starts only after displayed approval and readiness follows reinspection. | [2.3](evidence/step-2.3.md), [3.2](evidence/step-3.2.md), [5.2](evidence/step-5.2.md) |
| AC8 | 2.1, 2.2, 3.1; G2 and 5.2 | Actual tool/child paths and versions prove cross-project/same-Node manager isolation, pinned npm, shell independence, and no fallback/global changes. | [2.1](evidence/step-2.1.md), [2.2](evidence/step-2.2.md), [2.3 / G2](evidence/step-2.3.md), [3.1](evidence/step-3.1.md), [5.2](evidence/step-5.2.md) |
| AC9 | 3.1, 3.2; 5.2 | Format/mode tests preserve schema-1 identities/commands; app adoption is explicit and custom actions stay independent. | [3.1](evidence/step-3.1.md), [3.2](evidence/step-3.2.md), [5.2](evidence/step-5.2.md) |
| AC10 | 2.2, 3.1; 5.1 and 5.2 | Existing/custom and managed process tests plus app Stop/quit preserve lifecycle, settings, and read-only protections. | [2.2](evidence/step-2.2.md), [3.1](evidence/step-3.1.md), [5.1](evidence/step-5.1.md), [5.2](evidence/step-5.2.md) |
| AC11 | 3.1, 3.2, 4.2; G4 and 5.2 | Workflow spies and fresh disposable app project show no implicit dependency install or install-history Run gate. | [3.1](evidence/step-3.1.md), [3.2](evidence/step-3.2.md), [4.2](evidence/step-4.2.md), [5.2](evidence/step-5.2.md) |
| AC12 | 4.1, 4.2; 5.2 | npm/pnpm locked/unlocked matrix matches disclosed tools/argv/cwd/scope; no unlocked fallback after failure. | [4.1](evidence/step-4.1.md), [4.2](evidence/step-4.2.md), [5.2](evidence/step-5.2.md) |
| AC13 | 4.1, 4.2; G4 and 5.2 | Local timeout/EOF/descendant fixtures and visible operation results prove independent bounded lifecycle and honest cancellation. | [4.1](evidence/step-4.1.md), [4.2](evidence/step-4.2.md), [5.2](evidence/step-5.2.md) |
| AC14 | 2.3, 3.1, 3.2, 4.2; 5.2 | Controlled completions and app metadata edits prove stale approvals/results cannot authorize new work or restart live runs. | [2.3](evidence/step-2.3.md), [3.1](evidence/step-3.1.md), [3.2](evidence/step-3.2.md), [4.2](evidence/step-4.2.md), [5.2](evidence/step-5.2.md) |
| AC15 | 2.3, 3.1, 4.1, 4.2; G4 and 5.2 | Queue/lease/handoff tests and app conflicts serialize tool setup globally, cancel queued work without starting it, and preserve unrelated runs. | [2.3](evidence/step-2.3.md), [3.1](evidence/step-3.1.md), [4.1](evidence/step-4.1.md), [4.2](evidence/step-4.2.md), [5.2](evidence/step-5.2.md) |
| AC16 | 1.1, 1.2, 2.1; 5.1 | Unsafe metadata fixtures execute nothing; adapter commands avoid repository-local install configuration/hooks. | [1.1](evidence/step-1.1.md), [1.2](evidence/step-1.2.md), [2.1](evidence/step-2.1.md), [5.1](evidence/step-5.1.md) |
| AC17 | 2.3, 3.2; 5.2 | Fake partial/provider-unknown results and approved app recovery show actual state, owned cleanup, and reapproved retry without rollback claims. | [2.3](evidence/step-2.3.md), [3.2](evidence/step-3.2.md), [5.2](evidence/step-5.2.md) |

G5 additionally requires Step 5.1's deterministic regression/Debug/Release build proof and Step 5.2's locally running production-path app acceptance. Do not collapse these into a single claim that tests passed. Required live gates remain required when automation is green.

## Rollback and recovery

- Keep new discovery/provider/coordinator code inactive until its consumers are integrated; retain the custom launcher throughout. Revert typed launcher changes with their consumers/tests, not only one side of a call contract.
- Revert Step 3.1's persisted model, reader/writer, runner dispatch, and consumers as one unit. Before downgrading an app that cannot read the new format, stop owned operations and preserve both current settings and the pre-migration backup. Restore only an explicitly chosen compatible backup; warn that post-backup project edits would otherwise be lost. Never coerce future/corrupt data into an empty store.
- Tool downloads and dependency/lifecycle-script mutations are not undone by a source revert. Never uninstall shared or pre-existing runtimes as rollback. Inspect residual state, reconcile provider completion, and request fresh approval for any repair/removal.
- For cancellation/failure, stop owned process groups, preserve cleanup errors, hold conflicting ownership while provider work remains unresolved, and refresh actual requirements/tool state before retry. Do not promise rollback of node_modules, lockfiles, generated artifacts, or scripts' arbitrary side effects.
- Acceptance fixtures are disposable, but removing them or test-installed tools still requires confirming they are not used by another project. Preserve concise evidence and original user settings/profile snapshots; do not clean up unrelated work.

## Planned deferred checks

- First-class Yarn/Bun/non-Node provisioning, app-level version overrides, recursive workspace discovery/orchestration, interactive PTY behavior, dependency upgrades/repair, and sandbox/rollback guarantees are outside the governing scope and have no acceptance claim here.
- Signing/notarization/distribution/publication and any platform/account expansion are outside this plan. A locally runnable production-supported app is still required for Step 5.2; distribution is not.
- No required AC, live isolation, approval, migration, cancellation, or Release-availability check is intentionally deferred beyond this plan. Missing access/approval blocks its owning gate and is recorded in evidence, not converted into a future follow-up or silent waiver.

Execution-time discoveries, blockers, skipped/waived checks, and accepted deviations belong in the predetermined evidence notes rather than mutable plan status.
