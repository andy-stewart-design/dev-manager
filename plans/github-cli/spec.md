# Optional GitHub CLI Specification

## Status

- Readiness: Ready for planning
- Blocking decisions: None; the remaining uncertainty is implementation validation, not a material product decision.
- Overview: [overview.md](overview.md)
- Implementation plan: [plan.md](plan.md)
- Source: User-approved GitHub CLI installation, three-increment direction, and hostname modal discussion in this conversation; static repository inspection and the external references linked below.

## Problem and intended outcome

Some projects need GitHub access, but installing or authenticating GitHub CLI must not turn local project readiness into an account setup gate. Dev Manager should offer an optional, understandable GitHub CLI row and a safe device-login path while leaving project inspection and execution usable when `gh` is missing, unauthenticated, offline, or unavailable for a selected host.

## Scope

Included:

- An optional GitHub CLI row at the same top level as Apple developer tools and Homebrew, separate from the Node environment.
- Consent-based Homebrew installation of GitHub CLI, reuse of a working existing `gh`, read-only authentication status, and browser-based device login for GitHub.com and supported GitHub Enterprise hosts.
- Host-scoped account/status presentation, bounded cancellation and expiry behavior, and credential/logging privacy boundaries.

Non-goals:

- GitHub CLI upgrades, repair, removal, logout, token revocation, account switching, broad account management, custom OAuth clients, or password/PAT capture.
- `gh auth setup-git` or any Git configuration change; this requires a separate explicit approval.
- Bun, PTY-based auth, embedded web views, arbitrary OAuth flows, or a fallback from an Enterprise host to GitHub.com.
- Changes to normal project runner behavior, existing tool pins/shells, Release exposure, or installation-log format/retention policy. GitHub CLI installation results may use that log; authentication output may not.

## Current behavior and evidence

These are static observations, not runtime proof:

- [`ProvisioningCheck.swift`](../../dev-manager/Provisioning/ProvisioningCheck.swift) has no GitHub CLI check ID, and [`ProvisioningInspector.swift`](../../dev-manager/Provisioning/ProvisioningInspector.swift) only inspects Apple developer tools, Homebrew, fnm, Node, and pnpm. Its targeted inspection already refreshes the runtime group together.
- [`ProvisioningModel.swift`](../../dev-manager/Provisioning/ProvisioningModel.swift) enforces Apple developer tools → Homebrew → fnm → Node → pnpm and serializes row operations. GitHub CLI must branch after the Apple/Homebrew prerequisites, never depend on Node readiness.
- [`ProvisioningStatusView.swift`](../../dev-manager/Provisioning/Views/ProvisioningStatusView.swift) reuses top-level status rows and groups fnm/Node/pnpm under Node. GitHub CLI is a separate top-level row, not another Node child.
- [`ProvisioningConfiguration.swift`](../../dev-manager/Provisioning/ProvisioningConfiguration.swift) owns the Homebrew location and environment policy; [`ProvisioningRuntimeInstaller.swift`](../../dev-manager/Provisioning/ProvisioningRuntimeInstaller.swift) installs only fnm, Node, and pnpm today.
- [`ProvisioningCommandRunner.swift`](../../dev-manager/Provisioning/ProvisioningCommandRunner.swift) uses `/dev/null` stdin, concurrent bounded in-memory output tails, and separate eight-second inspection/fifteen-minute installation deadlines. It cannot safely deliver a live device code; auth needs a focused operation with its own bounded protocol handling.
- [`ProvisioningInstallationLog.swift`](../../dev-manager/Provisioning/ProvisioningInstallationLog.swift) is private, bounded, and intended for installation results. Authentication output, codes, tokens, and transcripts must not be written there.
- [`ContentView.swift`](../../dev-manager/App/ContentView.swift) exposes the current provisioning surface only under `DEBUG`; the existing platform scope and visibility are preserved by default. The existing [provisioning spike specification](../provisioning-spike/spec.md) explicitly deferred GitHub authentication and contains no GitHub auth implementation.
- External behavior references: [`gh auth login`](https://cli.github.com/manual/gh_auth_login), [`gh auth status`](https://cli.github.com/manual/gh_auth_status), [`gh help environment`](https://cli.github.com/manual/gh_help_environment), the [official auth flow](https://raw.githubusercontent.com/cli/cli/v2.104.0/internal/authflow/flow.go), [host handling](https://raw.githubusercontent.com/cli/cli/v2.104.0/internal/ghinstance/host.go), [status handling](https://raw.githubusercontent.com/cli/cli/v2.104.0/pkg/cmd/auth/status/status.go), [login flow](https://raw.githubusercontent.com/cli/cli/v2.104.0/pkg/cmd/auth/shared/login_flow.go), and [go-gh auth](https://raw.githubusercontent.com/cli/go-gh/trunk/pkg/auth/auth.go). These references inform the contract; they are not runtime observations of this checkout.

## Requirements and invariants

- **R1 — Optional readiness:** GitHub CLI is a separate top-level optional row. Missing, unauthenticated, unreachable, or unsupported GitHub state never blocks local project inspection, fixture readiness, or normal project start. The row reports its own state.
- **R2 — Safe installation:** A working existing `gh` is reused without automatic upgrade or repair. Installing a missing CLI requires explicit consent, honors the same Apple developer-tools/Homebrew prerequisites and per-row busy/loader/progress behavior as other provisioning rows, and never depends on fnm, Node, or pnpm. A ready binary is not treated as authenticated.
- **R3 — Host-scoped status:** Authentication status is separate from binary availability and identifies both the account and the queried host when authenticated. It distinguishes unauthenticated, expired/refresh-expired, unavailable, and indeterminate/error outcomes; invalid network/TLS conditions are never presented as a confirmed signed-out account.
- **R4 — Host input:** Login begins in a small focused modal with `github.com` prefilled and Cancel/Continue actions. Enter activates Continue and Escape activates Cancel. Acceptable input is a bare hostname or an HTTPS root URL, normalized to one hostname. Reject userinfo, query, fragment, repository paths, non-root paths, `http`, ports (including colon forms rejected by current `gh`), malformed hosts, and unsupported schemes before any auth operation.
- **R5 — Device login:** After a valid Continue, the same modal shows the device code, Copy code, Open browser, bounded progress, and Cancel. The app opens the browser once a validated device-flow URL is available and offers manual reopen afterward. It never asks for a GitHub password or PAT. GitHub Enterprise hosts are supported where the CLI reports device flow availability; failures clearly identify the host and do not bypass TLS or silently fall back to GitHub.com.
- **R6 — Credential safety:** The CLI handles credentials through its normal mechanism, normally macOS Keychain. The app must not promise Keychain-only storage: if the CLI persists a plaintext fallback, warn the user only after persistence is confirmed. Host-appropriate environment credentials may be detected by presence/source only (`GH_TOKEN`/`GITHUB_TOKEN` for GitHub.com and `ghe.com` tenancies; `GH_ENTERPRISE_TOKEN`/`GITHUB_ENTERPRISE_TOKEN` for Enterprise); values are never displayed, mutated, or logged.
- **R7 — Actual verification:** Completion requires a host-scoped status reinspection that finds the matching active host/account entry. Browser launch, a successful process exit, or a device-code screen alone is not authentication. JSON status must be interpreted from the matching host entry and its actual state (`success`, `error`, `timeout`, or `refresh_expired`), including account/login and token-source fields; exit code zero alone is insufficient. Token-bearing options such as `--show-token` are never used.
- **R8 — Bounded operations:** Authentication uses a focused operation separate from the existing tail-only runner, retains only bounded in-memory output, permits one active auth flow, and has a bounded deadline, expiry, cancellation cleanup, and stale-generation protection. Cancellation cannot undo a grant or credentials already saved: stop the owned operation, reinspect, and report actual state without silently deleting credentials or logging out.
- **R9 — Preservation:** Other-host accounts remain unchanged. If the selected host already has valid auth, status shows its current account rather than forcing a replacement login. Installation and auth operations preserve existing per-row status/layout, ordinary runner/tool-pin/shell behavior, private installation-log rules, and DEBUG/platform scope. This DEBUG-only scope is an inferred compatibility default, not approval for a production Release surface.
- **R10 — Output and protocol resilience:** Human CLI wording and stderr are version-dependent and are not a machine protocol. The implementation validates a supported CLI version before live auth, interprets structured status responses and recognized device-flow output, and gracefully reports an unsupported or unrecognized response without hanging, exposing raw logs, or guessing signed-in state. A verification URL must be HTTPS, contain no embedded credentials, and belong to the selected host's active device-flow response before browser use; arbitrary URLs copied from stderr are not trusted. The hostname field's root-path-only rule does not apply to the verification URL, which normally includes a device-login path.

## Behavior and contracts

### Provisioning row and readiness

The row appears as an optional top-level GitHub CLI item, not inside the Node group. It may be `missing`, `ready`, `installing`, `checking`, `authenticated`, `not authenticated`, `expired`, or `unavailable/error` in user-facing terms, while binary and auth state remain separate. Local readiness is computed without the row. The GitHub CLI install action is enabled only after the existing Apple developer-tools and Homebrew checks are ready; fnm/Node/pnpm state is irrelevant. One active row operation disables competing actions, and targeted progress identifies only the selected row; the initial inspection keeps the existing initial loader behavior.

Installation rechecks immediately before acting, installs only when `gh` is genuinely absent, and verifies the resulting executable. Existing usable `gh` is left at its current version. Installer failure, cancellation, or Homebrew unavailability leaves the row incomplete and offers recheck/retry; opening or requesting an installer is not completion.

### Host and login flow

The modal starts with `github.com` on every fresh login unless a future product decision adds persistence. Normalization accepts `example.com` and `https://example.com/` as the same root host. Validation rejects credentials, ports, paths other than `/`, query/fragment components, non-HTTPS URLs, malformed hostnames, and hosts the supported CLI cannot address. Validation errors remain in the modal and do not start a process.

After Continue, the device-flow state replaces the host-entry controls in the same modal. It displays the code without placing it in installation logs, lets the user copy it using the macOS pasteboard without reading the pasteboard, opens the validated URL once, and provides Open browser for later manual reopening plus Cancel. In a non-TTY flow the CLI may emit a code and verification URL on stderr and may enable clipboard output; the focused operation must suppress prompts and not depend on a PTY, must not treat that human output as a stable protocol, should prefer disabling CLI clipboard behavior, and owns a write-only pasteboard Copy action. Device-flow polling and expiry have visible progress and bounded failure states. Browser SSO/redirect handling remains in the system browser with normal TLS; the app does not use a password-capturing web view.

### Status, credentials, and recovery

Status queries the selected host, not an arbitrary default host, using the host-scoped structured `gh auth status --hostname HOST --json hosts` shape without ever requesting token fields. A supported response is filtered to the matching host and reports the active account, host, login/token source, and whether authentication is valid. A network error, invalid TLS, timeout, malformed response, unsupported CLI output, or unavailable Enterprise device flow produces a clear error/unknown state with retry—not “Not authenticated.” Environment-variable credentials are reported only as a redacted source indicator. If they control the selected host, explain their precedence rather than silently clearing or bypassing them to store another login.

On Cancel, expiry, process failure, or app dismissal, the owned operation is stopped within its deadline and the current host is reinspected when safe. A grant or credential saved just before cancellation is retained and shown as the actual result. Existing credentials are never silently removed. A second auth flow cannot start until the first is cleaned up; late results from an older flow cannot overwrite newer row or modal state.

## Ownership and boundaries

The app owns optional-row presentation, consent, hostname validation, bounded operation lifecycle, redacted status presentation, and reinspection. Homebrew owns CLI installation, `gh` owns auth/device-flow/credential behavior and host selection, macOS owns browser navigation and Keychain/pasteboard primitives, and GitHub owns the remote authorization service. The existing project runner continues to own project processes and output; the existing installation log remains installation-only. No component collects passwords/PATs, bypasses TLS, changes Git configuration, mutates environment credential values, or manages unrelated accounts.

## Acceptance criteria

| ID   | Requirement(s) | Starting condition / action                                                                                                                            | Expected outcome                                                                                                                                                                                                                              | Verification approach                                                                                                          |
| ---- | -------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------ | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------ |
| AC1  | R1, R2, R9     | Open the DEBUG provisioning surface with GitHub CLI absent, present, and authenticated states while a local project is usable.                         | GitHub CLI is a separate optional top-level row; local readiness and Start remain available regardless of its state; existing ready `gh` is not upgraded.                                                                                     | Manual VM walkthrough plus source inspection.                                                                                  |
| AC2  | R2             | Use a clean supported setup with Apple/Homebrew ready and Node unavailable; consent to the GitHub CLI row.                                             | Homebrew prerequisites and targeted progress are shown; installation does not require or wait for Node/fnm/pnpm; cancellation/failure is not success and retry rechecks state.                                                                | Manual VM walkthrough.                                                                                                         |
| AC3  | R3, R6, R7     | Inspect status for GitHub.com, a supported Enterprise host, missing auth, an expired credential, environment credentials, and a network/TLS failure.   | Account and exact host are shown only for a matching valid entry; credential source is redacted; network/TLS failure is unknown/error rather than signed out; values and tokens never appear.                                                 | Manual VM cases with a human test account; pure status-fixture tests may supplement.                                           |
| AC4  | R4             | Enter bare hostname, HTTPS root, malformed input, userinfo, query, fragment, repository path, non-root path, HTTP, and port forms; use Enter/Escape.   | Valid roots normalize to a hostname and Continue starts only valid input; invalid input is rejected locally; Enter continues and Escape cancels.                                                                                              | Small pure hostname-validation fixture tests plus manual modal check.                                                          |
| AC5  | R5, R10        | Continue with GitHub.com and a supported Enterprise host where device flow is available.                                                               | The same modal displays code, Copy code, Open browser, progress, and Cancel; browser auto-opens once for the validated HTTPS URL; manual reopen works; no password/PAT field, TLS bypass, or GitHub.com fallback appears.                     | Manual VM walkthrough; Enterprise case requires real access and may be recorded unrun if unavailable.                          |
| AC6  | R7, R10        | Complete or interrupt device login, including a successful process with an auth failure response and an unrecognized supported/unsupported CLI output. | Only matching host/account status confirms auth; exit zero/browser exit/device-code display do not; unsupported output reports a bounded actionable error without raw transcript or hang.                                                     | Pure parser fixtures plus manual GitHub login.                                                                                 |
| AC7  | R8             | Cancel during polling, allow expiry, dismiss near completion, and attempt a second flow while one is active.                                           | The owned operation stops and cleans up within its deadline; stale results are ignored; saved credentials are not deleted; post-cancel reinspection reports the actual state; only one flow is active.                                        | Manual timing/cancellation cases and focused operation tests.                                                                  |
| AC8  | R6, R9         | Authenticate one host when another host already has an account; inspect installation logs and app diagnostics.                                         | Other-host accounts remain unchanged; no logout/revocation occurs; auth codes, tokens, environment values, and auth transcripts are absent from private installation logs and UI diagnostics.                                                 | Manual multi-host/log privacy inspection.                                                                                      |
| AC9  | R1, R9         | Run the existing local project flow with GitHub CLI missing, unauthenticated, or unavailable; inspect DEBUG/Release boundaries.                        | Existing runner, shell behavior, pins, layout conventions, and project readiness are unchanged; the optional surface remains within the established DEBUG/platform scope.                                                                     | Source inspection and manual local-project regression.                                                                         |
| AC10 | R2–R10         | Reopen the app after install/login interruption and repeat a valid-host status check.                                                                  | Selected host resets to `github.com` unless future persistence is explicitly added; valid existing auth shows the current account; retry reuses working `gh`, does not alter unrelated hosts, and leaves no credential/log privacy violation. | Manual VM acceptance, with pure parser/hostname fixtures as focused automated support.                                         |
| AC11 | R6, R8         | Process a supported CLI response reporting plaintext credential persistence, including completion near cancellation.                                   | The user sees a storage warning without a Keychain-only claim; the app verifies actual account state and does not automatically log out, revoke, delete credentials, or persist the auth transcript.                                          | Focused captured-output fixtures; live fallback validation only when safe, without deliberately weakening the user's Keychain. |

## Assumptions

- **Inferred validation default:** accepting bare hostnames and HTTPS root URLs, while rejecting ports and other URL components, is a conservative policy based on current CLI restrictions. Validate those restrictions against the supported CLI during implementation; a broader host-management UI is not implied.
- The existing DEBUG-only visibility and platform scope remain the default compatibility boundary; production Release exposure is not approved by this specification.
- A supported `gh` version and structured status/device-flow parsing strategy will be established before live auth work. Human GitHub test-account and Enterprise access may be unavailable; fakes can test parsing but cannot prove live compatibility.
- A valid existing auth entry for the selected host should be shown rather than replaced. Host persistence is not required; resetting to `github.com` is acceptable.
- Enterprise support is conditional on device flow being available through the supported CLI and host; normal browser SSO/TLS behavior is sufficient.

## Risks and open decisions

- Blocking: None before planning. No material product decision prevents plan authoring.
- Non-blocking: CLI human output and auth internals can change by version; constrain supported versions and fail safely on unknown output.
- Non-blocking: Enterprise device flow and a human test account may not be available for manual acceptance; label those cases unrun rather than claiming compatibility.
- Non-blocking: Near-simultaneous grant/cancel races can only report actual state after reinspection; they cannot revoke a grant safely.

## Deferred work

- Explicit `gh auth setup-git` approval and Git configuration ownership.
- Logout, revocation, account switching, multi-account management, custom OAuth clients, and broader credential administration.
- Production Release onboarding, persistent selected-host/account management, arbitrary auth providers, and a general terminal/PTY integration.

[Back to overview](overview.md)
