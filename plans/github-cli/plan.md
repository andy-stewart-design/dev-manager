# Optional GitHub CLI Implementation Plan

## Governing source

- Governing spec: [spec.md](spec.md)
- Orientation: [overview.md](overview.md)

This is an execution contract. Keep step IDs, scope, dependencies, expected files, checks, and acceptance mappings stable during execution. Routine plan edits are task-checkbox updates only; record actual user-approved changes in `evidence/changes.md`. A checkbox is not acceptance, approval, publication, or release. Supervised approvals remain in workflow state.

## Execution constraints

- Paths are repository-relative. Preserve unrelated work, particularly the user's edits to `dev-manager/Provisioning/Views/ProvisioningStatusView.swift`.
- Implementation starts only after the user confirms the current provisioning PR is closed and a new branch is ready. Do not create branches, close PRs, commit, push, or start implementation as part of authoring this plan.
- The user owns Xcode builds/tests, VM transfers, installation approvals, and live authentication. The agent performs source review and `git diff --check`, not builds, tests, parsing, app launches, installation, or authentication unless separately authorized.
- Use the existing `dev-manager` scheme and `dev-managerTests` Swift Testing target. The user builds Debug with Product → Build, transfers the zipped Derived Data app through the Tart share, and copies it to the guest's local disk. Do not install Xcode in the clean VM.
- Preserve DEBUG-only visibility, existing platform scope, per-row progress, layout settings, tool pins, shell configuration, and the normal project runner. Keep UI state MainActor-isolated and background value/process helpers appropriately nonisolated and Sendable.
- Installation requires the existing Apple/Homebrew prerequisites, not Node. Authentication is optional and never enters local-project or fixture readiness calculations.
- Authentication must not use the installation logger, request token-bearing status output, collect passwords/PATs, bypass TLS, or directly edit credential files. CLI-owned login persistence is allowed only in Phase 3 after consent. Never run logout, revoke credentials, configure Git helpers, or automatically upgrade/repair `gh`.
- No current green baseline is established. Existing build, runner-test, and provisioning evidence is not verification of this feature. The current shared scheme's Archive configuration is Debug; do not mistake that for Release verification or add distribution/signing work.
- Every completed step needs concise evidence at its named location. Do not create empty evidence notes while planning. Record checks, outcomes, material caveats, and actual approval—not transcripts, device codes, tokens, or chronological diaries.
- Check a verification task only after its checks and completion gate pass. Failed, blocked, skipped, or waived checks remain unchecked; record the reason, approval owner, and next action. A waiver is not a pass.

## Phase overview and delivery boundary

| Phase | Outcome | Dependency | Exit gate |
| --- | --- | --- | --- |
| 1 | Optional GitHub CLI installation, independent of Node. | User-confirmed new-branch readiness. | User-built binary row installs/reuses `gh` without changing local readiness. |
| 2 | Read-only, host-aware authentication status. | Phase 1 gate. | Focused status fixtures and GitHub.com manual checks distinguish accounts, sources, and failures. |
| 3 | Hostname/device-login modal and bounded browser authentication. | Phase 2 gate. | Live login/recovery, privacy, regression, and Release-isolation checks; Enterprise live coverage requires access. |

Delivery boundary: one future GitHub CLI feature PR on the new branch, separate from the current provisioning PR. Each phase is a reviewable vertical slice, not automatically a separate PR. Within each step, shared types and their consumers land/revert together; no broken intermediate contract is independently mergeable.

Read-only baseline inspection belongs to Step 1.1; no separate Phase 0 is needed.

## Phase 1 — Optional CLI installation

Outcome: a separate top-level GitHub CLI row can detect and install `gh` without implying authentication.
Depends on: the user-confirmed branch precondition above.
Review boundary: binary inspection, consent, installation, and row integration only; no login/status placeholder.

### Step 1.1 — Install and reuse GitHub CLI

Requirements / acceptance: R1, R2, R9; AC1 (binary portion), AC2, AC9 (source/readiness portion), AC10 (installation reuse portion). Authentication and final regression portions remain with later gates.
Depends on: no implementation steps.
Review boundary: an installable optional row composed with the existing provisioning flow.

Expected files:

- Existing core files under `dev-manager/Provisioning/`: `ProvisioningCheck.swift`, `ProvisioningConfiguration.swift`, `ProvisioningInspector.swift`, and `ProvisioningModel.swift` — add the binary check, targeted inspection, executable context, and independent prerequisite branch.
- `dev-manager/Provisioning/ProvisioningGitHubCLIInstaller.swift` — proposed focused `brew install gh` helper using the existing bounded runner.
- `dev-manager/Provisioning/Views/ProvisioningStatusView.swift` and `dev-manager/Provisioning/Views/ProvisioningView.swift` — top-level row and tool-specific consent.

Tasks:

- [ ] Inspect the actual starting checkout and record relevant existing failures; add `gh` binary/version detection and targeted inspection, reusing a working existing executable without upgrade or repair.
- [ ] Add the explicit Apple developer tools → Homebrew → GitHub CLI branch. Do not append `gh` to the fnm/Node/pnpm dependency chain or include it in runtime/fixture readiness.
- [ ] Add consented installation with preflight reinspection, per-row busy/progress, post-install verification, and installation-only logging. Preserve existing statuses, layout, and local project behavior.
- [ ] Satisfy the verification/completion gate below with the user and record concise evidence.

Verification:

- Source: inspect every new check-ID/inspection consumer, DEBUG guard, prerequisite and readiness calculation; `git diff --check` passes. No auth command or dead login button is introduced.
- Manual: user builds Debug and uses the VM with Apple/Homebrew ready but Node unavailable. Install missing `gh`, recheck, reopen, and repeat: only `gh` installs and an existing working version is retained. Decline consent and exercise a safe failed-install/retry case; neither reports success. A prepared local project remains runnable without `gh`.

Completion gate: user-built detection/install/reuse and meaningful failure/readiness outcomes are demonstrated; source checks alone do not prove Homebrew compatibility.
Evidence location: [evidence/step-1.1.md](evidence/step-1.1.md).

Phase exit gate: after Step 1.1 verification, assess the composed optional row, tool-only install, and unchanged Node/local readiness before Phase 2 approval. Record the gate in the same note.

## Phase 2 — Read-only host authentication status

Outcome: installed CLI availability and host-specific authentication are separate, accurate states.
Depends on: Phase 1 exit gate.
Review boundary: status service, typed results, presentation, and focused fixtures. No credential-changing command or temporary Enterprise-host UI.

### Step 2.1 — Inspect authentication without changing it

Requirements / acceptance: R3, R6, R7, R9, R10 (read-only portions); AC1 (status portion), AC3 (fixtures/GitHub.com portion), AC6 (JSON portion), AC8 (environment/privacy portion), AC10 (read-only reopen portion). Live Enterprise and device-flow coverage belong to Step 3.1.
Depends on: Step 1.1 and its phase gate.
Review boundary: bounded host-aware status queries with a default `github.com` UI.

Expected files:

- `dev-manager/Provisioning/GitHubAuthService.swift` — proposed typed host/status/source values and structured status decoder, with a small injectable command function for fixtures rather than a service framework.
- `dev-manager/Provisioning/ProvisioningModel.swift` and, only where needed for binary/auth separation, `ProvisioningCheck.swift`/`ProvisioningInspector.swift` in that directory.
- `dev-manager/Provisioning/Views/ProvisioningStatusView.swift` — read-only host/account/source/error presentation, preserving the existing layout.
- `dev-managerTests/Provisioning/GitHubAuthServiceTests.swift` — proposed token-free captured/synthetic JSON and command-argument tests.

Tasks:

- [ ] Add `status(hostname:)` using `gh auth status --hostname HOST --json hosts` with the existing short inspection timeout. Interpret the matching active entry, actual state, login, and safe token-source label; never request `--show-token` or infer authentication from exit zero alone.
- [ ] Distinguish no stored authentication, invalid/expired authentication, unavailable network/TLS, timeout, malformed output, and unsupported CLI. Report host-appropriate environment credential presence/source without displaying values or clearing/bypassing that environment to force stored login.
- [ ] Present default-host status separately after binary inspection, without making optional network status part of local-tool readiness. Keep the service host-aware; do not add a temporary host selector before the real modal.
- [ ] Add focused fixtures for matching/other hosts, active/inactive entries, empty hosts, expiry, environment source, zero-exit errors, malformed JSON, and network/TLS/timeout results. Assert the requested hostname is passed as an argument, not shell interpolation.
- [ ] Satisfy the verification/completion gate below with the user and record concise evidence.

Verification:

- Source: the only auth command is read-only status; it never enters the installation logger, invokes login/logout/setup-git, or changes config. Pure values/services honor the project's actor-isolation settings.
- Focused tests: user runs the proposed `GitHubAuthServiceTests` through Xcode's Test navigator. Fixtures prove decoding and argument/privacy rules, not live Enterprise compatibility.
- Manual: on the user-built VM app, inspect GitHub.com in signed-out and already-signed-in test contexts. Account and host appear only for valid matching status; unavailable/invalid conditions do not look like confirmed sign-out. Reopen and confirm detection does not alter credentials. Do not sign out or revoke a real account just to construct a test; use disposable contexts or fixtures.

Completion gate: focused tests and user-owned GitHub.com status checks agree, with no auth mutation or logging. Real Enterprise status remains a named partial acceptance case for Phase 3, not a reason to add temporary UI.
Evidence location: [evidence/step-2.1.md](evidence/step-2.1.md).

Phase exit gate: after Step 2.1 verification, assess binary/auth separation, host filtering, failure classification, and privacy before Phase 3 approval. Record the gate and any unavailable live Enterprise coverage in the same note.

## Phase 3 — Hostname modal and browser sign-in

Outcome: one modal guides a chosen host's device authorization, with safe cancellation and actual account verification.
Depends on: Phase 2 exit gate; live acceptance additionally needs human GitHub.com credentials and supported Enterprise access.
Review boundary: hostname validation, live device output, owned-process lifecycle, modal/browser/pasteboard behavior, and final integration. No Git credential setup or account manager.

### Step 3.1 — Complete the host-aware login flow

Requirements / acceptance: R4–R10 and remaining R1–R3 integration; AC4–AC8, AC10–AC11, plus remaining AC1/AC3/AC9 portions. This step does not retroactively satisfy missing prior gates.
Depends on: Step 2.1 and its phase gate.
Review boundary: one usable end-to-end auth slice; process, modal, and state consumers remain an atomic change.

Expected files:

- Proposed files under `dev-manager/Provisioning/`: `GitHubHostname.swift`, `GitHubDeviceFlowParser.swift`, and `GitHubAuthOperation.swift` — focused pure validation/parsing and bounded auth coordination.
- `dev-manager/Provisioning/Views/GitHubLoginView.swift` — proposed same-modal host-entry/device-flow interface.
- `dev-manager/Provisioning/ProvisioningModel.swift`, `GitHubAuthService.swift` in that directory, and the existing provisioning views — selected-host state, presentation, single-operation locking, and post-flow reinspection.
- `dev-manager/Provisioning/ProvisioningCommandRunner.swift` and, if needed, proposed `ProvisioningOwnedProcess.swift` in that directory — minimal extraction/reuse of existing spawn/group-cleanup primitives for streaming. Preserve public check/install APIs, timeouts, and existing runner tests; do not duplicate the entire process engine or route auth through the installation logger.
- `dev-managerTests/Provisioning/GitHubLoginTests.swift` — proposed hostname/parser/state fixtures and a small isolated fake-child streaming/cancellation case; no network credentials or new test framework.

Tasks:

- [ ] Validate/normalize hostname entry under R4. Establish compatible CLI capabilities and recognized output against the official sources linked in the spec; record tested versions rather than claiming support for arbitrary future wording. Report unsupported existing versions without automatically upgrading them.
- [ ] Add a focused non-TTY streaming operation with prompts disabled, bounded in-memory data (approximately 64 KiB), an approximately fifteen-minute deadline, and finite owned-group cleanup. Use the selected hostname and HTTPS protocol; prefer explicit `--clipboard=false` so app Copy is the only clipboard writer. Unknown output fails clearly rather than hanging or exposing a raw transcript.
- [ ] Add the modal: focused `github.com` field, Enter/Continue and Escape/Cancel; valid submission preflights that host, then shows code, Copy, Open browser, progress, and Cancel in the same modal. Already-valid or environment-controlled credentials are explained without replacement; another hostname remains selectable. Open the validated flow's HTTPS URL once, allow manual reopen, and use write-only pasteboard copying. The verification URL may contain its normal device-login path.
- [ ] Complete single-flow locking, generation protection, expiry/error recovery, and cancel/dismiss cleanup. Verify actual matching-host account status after completion or safe cancellation reinspection; retain credentials saved before cancellation. Surface a reported plaintext-storage fallback without claiming Keychain-only storage or automatically logging out/revoking. Never run `gh auth setup-git` or change Git credential helpers.
- [ ] Add focused tests alongside the feature: hostname forms; supported/unknown device output and URL validation; success-via-reinspection rather than exit code; plaintext warning; environment precedence; late events after cancellation; and bounded cleanup of an isolated fake child. Retain the three existing command-runner regression cases if primitives move.
- [ ] Satisfy the verification/completion gate below with the user and record concise evidence.

Verification:

- Source: no auth data goes to installation logs, console logging, credential fields, or raw UI diagnostics. Only the designated modal displays the one-time code. No pasteboard reads, password/PAT input, TLS bypass, credential deletion, or unrelated-host mutation exists.
- Focused tests: user runs `GitHubLoginTests` during this step. Fixtures cover errors/races/storage warnings without weakening Keychain or requiring real Enterprise credentials. Synthetic subprocess tests isolate temporary data and clean up their owned children.
- Live: user builds/transfers Debug, completes GitHub.com browser login, uses Copy/manual browser reopen, cancels and retries, checks expiry/reopen and a near-completion cancel, and verifies account plus hostname. A previously authenticated second host remains unchanged. Inspect logs for absence of auth data. Invalid TLS/unsupported Enterprise flow remains an explicit error, never a fallback to GitHub.com.
- Final integration: user runs Product → Test (Cmd-U) for existing and new tests once, checks a normal local project's Start/Open/Stop, and verifies Release has no provisioning/login UI. For Release verification, temporarily select Release in the scheme's Run build configuration, then restore Debug; no Archive or distribution change is required.

Completion gate: focused and final integration tests, GitHub.com live recovery/privacy, and unchanged local/Release behavior are verified. Real Enterprise status/device-flow cases require a real server/account/SSO path. If unavailable, their acceptance and this final verification gate remain blocked and unchecked; recording that limitation is not a pass or an invented waiver.
Evidence location: [evidence/step-3.1.md](evidence/step-3.1.md).

Phase exit gate: after Step 3.1 verification, review composition and every final acceptance entry before user approval. Record the outcome and any blocker in the same note; do not begin rollout.

## Final acceptance

| Spec ID | Owning step / gate | Observable proof | Evidence location |
| --- | --- | --- | --- |
| AC1 | 1.1 binary, 2.1 status, 3.1 final | Optional install/status/login never alters local readiness; working CLI reused. | [1.1](evidence/step-1.1.md), [2.1](evidence/step-2.1.md), [3.1](evidence/step-3.1.md) |
| AC2 | 1.1 gate | Consent/retry/install work with Node absent and Apple/Homebrew ready. | [1.1](evidence/step-1.1.md) |
| AC3 | 2.1 fixtures/GitHub.com; 3.1 live Enterprise | Correct host/account/source and errors; fixtures are not live compatibility proof. | [2.1](evidence/step-2.1.md), [3.1](evidence/step-3.1.md) |
| AC4 | 3.1 | Valid roots normalize; invalid inputs rejected; Enter/Escape work. | [3.1](evidence/step-3.1.md) |
| AC5 | 3.1 | Same-modal device flow, browser, Copy, and manual reopen on supported hosts. | [3.1](evidence/step-3.1.md) |
| AC6 | 2.1 JSON; 3.1 device flow | Actual status confirms success; unknown/failed output is bounded and safe. | [2.1](evidence/step-2.1.md), [3.1](evidence/step-3.1.md) |
| AC7 | 3.1 | Cancel/expiry/dismissal clean up; late results ignored; saved auth retained. | [3.1](evidence/step-3.1.md) |
| AC8 | 2.1 environment; 3.1 multi-host/privacy | No token exposure, auth logging, or mutation of other-host accounts. | [2.1](evidence/step-2.1.md), [3.1](evidence/step-3.1.md) |
| AC9 | 1.1 source; 3.1 final integration | Normal project behavior and DEBUG/Release isolation preserved. | [1.1](evidence/step-1.1.md), [3.1](evidence/step-3.1.md) |
| AC10 | All steps; 3.1 final | Reopen/retry reuse installation and real host status without credential loss. | [1.1](evidence/step-1.1.md), [2.1](evidence/step-2.1.md), [3.1](evidence/step-3.1.md) |
| AC11 | 3.1 fixtures | Reported plaintext persistence warns without logout/revocation or transcript storage. | [3.1](evidence/step-3.1.md) |

Final acceptance requires all phase gates plus the user-owned final suite, Release check, ordinary-project smoke check, and named live outcomes. A blocked Enterprise case remains explicit; changing that scope requires actual user agreement recorded in `evidence/changes.md`.

## Rollback and recovery

Revert steps in reverse order with their consumers/types together. Code rollback does not uninstall `gh`, erase its configuration, revoke a GitHub grant, or remove Keychain credentials. Cancel only the owned process and discard ephemeral app data. Reinspect actual host state afterward or on next opening; do not silently log out to simulate rollback.

## Planned deferred checks

- Git credential setup, logout/revocation, account switching, broad account management, persistent host selection, ports/arbitrary providers, PTYs, Bun, and production Release exposure remain outside scope.
- Future CLI versions require capability/output validation; no blanket compatibility claim is made. Enterprise acceptance is not deferred by default: missing human/server access is an execution-time blocker, not successful verification.

This plan authors no implementation, evidence results, build, test, installation, authentication, branch, or PR action. Execution-time discoveries and approved deviations belong in the predetermined evidence notes, not mutable plan status.
