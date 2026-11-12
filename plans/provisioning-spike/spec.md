# Machine Provisioning Spike Specification

## Status

- Readiness: Ready for planning
- Blocking decisions: None
- Overview: [overview.md](overview.md)
- Implementation plan: [plan.md](plan.md)
- Source: Provisioning discussion and scope agreement in this conversation, including administrator-only VM testing and the explicit preference for a tight, manually validated spike.

## Problem and intended outcome

Non-developers need development tools before they can run local projects, but should not need to use Terminal, copy commands, or edit shell files.

This spike answers one question: can a logged-in administrator on a clean Apple Silicon Mac go from no development tools to running a small project through the app and standard macOS installation dialogs? It produces a working development-only demonstration and concise findings, not a production provisioning framework.

## Scope

Included:

- Apple Silicon macOS 15 or later, tested in the user's disposable VM with a logged-in administrator account.
- A development-only setup screen with basic status, actions, and diagnostic output.
- Detection and guided installation of Apple Command Line Tools, official Homebrew, fnm, one pinned Node version, and a compatible pinned pnpm version.
- A minimal fixture project started, discovered over HTTP, stopped, and restarted through the existing project runner.
- Manual checks of cancellation/retry, app relaunch, and repeated setup.
- First proving app operation without shell-file changes; then separately exercising opt-in, reversible Zsh configuration.

Non-goals:

- Standard-user or managed-device deployment, Intel support, or pre-login installation.
- GitHub CLI/authentication, arbitrary project dependency installation, or project-specific provisioning.
- Automatic upgrades, tool uninstallation, machine rollback, or repairing arbitrary existing installations.
- A polished onboarding flow, generic installer abstraction, persistent workflow engine, or custom privileged helper.
- A new automated acceptance harness, exhaustive failure matrix, or broad test refactor.

## Current behavior and evidence

These are static code observations, not VM validation:

- [ProcessLauncher.swift](../../dev-manager/Runs/ProcessLauncher.swift) runs commands through a login/interactive Zsh shell but supplies no interactive stdin. Its existing process runner is not a terminal for installer prompts.
- [ShellEnvironment.swift](../../dev-manager/Runs/ShellEnvironment.swift) includes Homebrew locations in its baseline PATH and permits shell initialization files to augment the environment. This does not establish that fnm-managed Node works without shell configuration.
- [ProcessSupervisor.swift](../../dev-manager/Runs/ProcessSupervisor.swift) treats its wrapper handshake as process startup; [SiteDiscovery.swift](../../dev-manager/Discovery/SiteDiscovery.swift) separately probes for responding websites. The spike must distinguish process startup from an HTTP-ready fixture.
- [ContentView.swift](../../dev-manager/App/ContentView.swift) accepts the existing store and runner. There is no provisioning UI or state model.
- [Project configuration](../../dev-manager.xcodeproj/project.xcproj) targets macOS 15+, disables App Sandbox, and retains Hardened Runtime.
- The [MVP specification](../_completed/mvp/spec.md) assumes dependencies are preinstalled and forbids automatic installation or escalation. This spike introduces an explicit, consent-based exception only in its development-only setup flow. Normal project startup retains its existing behavior.
- External reference behavior: [Homebrew Installation](https://docs.brew.sh/Installation), [Apple Command Line Tools installation](https://developer.apple.com/documentation/xcode/installing-the-command-line-tools), and [fnm shell setup](https://github.com/Schniz/fnm#shell-setup). Actual behavior in the VM remains to be verified.

## Requirements and invariants

- **R1 — Restricted entry and consent:** Setup is available only in development builds, for this spike's Apple Silicon, supported-macOS, logged-in-administrator environment. Machine-changing steps require an explicit setup action that explains their effects. Opening a project or pressing Start must not initiate provisioning.
- **R2 — Detect before acting:** Report each required tool as available, missing, or requiring attention based on machine checks. Rechecking and repeating setup must reuse satisfactory installations rather than blindly reinstalling or upgrading them.
- **R3 — System-owned installation:** Request Command Line Tools through Apple's graphical flow and open the official Homebrew package in macOS Installer. Users must not need Terminal, copied commands, or manual file edits. Passwords and system authorization belong exclusively to macOS UI.
- **R4 — Explicit runtime:** Install fnm and fixed, mutually compatible Node/pnpm versions for the fixture. Run those tools as the logged-in user, not through sudo. Project execution must work without adding or changing shell initialization files.
- **R5 — End-to-end proof:** Use the existing project runner for the fixture. Successful setup is demonstrated by the expected Node/pnpm versions, a responding fixture website, and successful Stop/restart—not merely successful installer launch or tool-presence checks.
- **R6 — Bounded recovery:** Cancellation or failure must not be reported as success or trigger subsequent dependent steps. Rechecking, retrying, and reopening the app must recover by inspecting actual machine state. No transactional rollback or automatic background resumption is required.
- **R7 — Separate shell configuration:** Only after the no-shell-edit path has been demonstrated, offer a separate opt-in fnm Zsh configuration experiment. Preserve existing user content, avoid duplicate initialization, and provide a reversible app-owned change.
- **R8 — Manual evidence:** Capture concise VM findings sufficient to decide whether to proceed with a production feature. Manual verification is the acceptance mechanism; no new automated test infrastructure is required.
- **R9 — Compact setup presentation (historical, superseded by R12):** The earlier DEBUG surface used one primary next action derived from current checks and external waiting state. It established the rationale for a compact layout, visible prerequisite details, accessible title-menu Advanced tools, and optional shell configuration without persisted wizard progress. R12 supersedes its single-footer-action contract while retaining that rationale and the preserved safety boundaries.
- **R12 — Per-tool setup presentation (NEW, supersedes R9's single-footer contract):** The DEBUG setup surface presents Apple developer tools, Homebrew, fnm, Node, and pnpm as separate rows with current machine state and a row-local action. Ready rows are green and have no Install action. Missing tools offer a quiet bordered **Install** only when all prerequisites are ready; missing-prerequisite and unverified rows keep Install disabled with an explanation. Attention/conflict states never offer blind installation and instead expose a relevant Check again action. External Apple/Homebrew handoffs expose Check installation rather than claiming completion. Each runtime action targets only its named tool and uses one targeted consent explaining its effect; the dependency chain Apple developer tools → Homebrew → fnm → Node → pnpm is enforced without automatic chaining. A single active operation shows row progress and disables other actions. Tool rows use one shared layout with a 32-point minimum content height, 10 points of vertical padding, and 10 points of horizontal item spacing; wrapped status/error text may grow the row. Row-list stacks use zero spacing, and action controls remain intrinsically sized but trailing-aligned to the same content edge as the full-width separators; separators between fnm, Node, and pnpm begin at the child title column and do not trail the final pnpm row. The main header, introduction, info popovers, grouped Node environment, and tertiary status icons remain compact; the global footer action and divider are removed. The optional shell row appears after the Node group only when all runtime tools are ready, with a separate Configure action and no automatic Restore action. Advanced retains Check again, fixture preparation/showing, output, and shell recovery controls. Fixture preparation only materializes the owned fixture after all runtime checks are ready and never installs tools.
- **R10 — Behavior-preserving architecture constraint (NEW):** The final provisioning refactor may move and extract source files into the focused `Provisioning/` and `Provisioning/Views/` tree, but must preserve the approved DEBUG-only provisioning contracts and runtime behavior: guards, pins, check generation, installer handoffs, bounded command/process ownership, fixture safety, shell receipt/restore safety, and the existing DEBUG view API. It must not change normal project runner/environment behavior, Release exposure, UI layout/button logic, or unrelated source. Verification for this constraint is source inspection and diff hygiene only in this authoring pass; user-owned builds, tests, VM checks, and final integration remain pending.
- **R11 — Bounded shared command collection (NEW):** Read-only checks and runtime installs use one shared, DEBUG-only subprocess result and bounded process engine. It drains stdout and stderr concurrently while the process runs, retains bounded diagnostic tails, keeps the command deadline effective through output collection, cleans the spawned process group and reaps its leader within explicit finite grace periods, and returns partial diagnostics on timeout. Group cleanup is scoped to the owned spawned group; arbitrary detached descendants are not tracked or chased, while output-drain cancellation remains bounded if one retains an inherited pipe. A command whose output cannot be collected by its deadline is never reported as successful, regardless of leader exit status. Check commands retain the eight-second policy; installers retain the fifteen-minute policy.

## Behavior and contracts

### Setup flow

The screen presents the required tools, their detected status, the current action, and concise output/errors. A simple sequence with a manual **Check again** action is sufficient; no elaborate wizard or automatic progress integration is required.

The baseline order is: inspect the machine, satisfy Apple developer-tool prerequisites, satisfy Homebrew, install/configure the runtime, and run the fixture. A usable existing Xcode installation can satisfy developer-tool checks; standalone Command Line Tools need not be installed redundantly.

For Command Line Tools, the app requests Apple's install dialog. The user completes Install, license acceptance, download, and completion in Apple's UI. Request submission is not completion. Afterward, the app verifies the selected developer tools are usable.

For Homebrew, use the official release package from Homebrew's published release location, retaining normal macOS package-signature and security checks. Do not bypass installer warnings or obtain packages from third-party mirrors. Use normal interactive console-user ownership; do not create the alternate-user override plist.

The app must verify Homebrew is executable as the logged-in user before using it. After system installation, tool installation uses ordinary user privileges.

### Runtime and fixture

The spike fixes exact Node and pnpm versions and records them with the fixture and findings; floating "latest" is not a reproducible validation target. Choosing the concrete compatible versions is an implementation detail, not an additional product decision.

The fixture is a tiny local HTTP project with a pnpm development command. It should avoid third-party application dependencies so package dependency management does not become a second experiment.

The app supplies an explicit fnm/runtime execution context for the fixture, rather than relying on a newly edited `.zshrc` or inherited GUI PATH. The implementation may use fnm's execution support or an explicit subprocess environment. It must not replace the existing project runner or change unrelated projects' commands/environments.

### Recovery and interruption

| Situation | Observable behavior |
| --- | --- |
| Installer request returns | Remain awaiting verification; do not claim installation finished. |
| User cancels or declines an installer | Setup remains incomplete; explain the unmet prerequisite and allow recheck/retry. |
| User closes the app during external installation | On reopening, detect current state. The external installer may have continued; do not assume cancellation or relaunch it blindly. |
| A runtime command fails | Show the failed step and useful diagnostic output; do not start the fixture as though setup succeeded. |
| Setup is repeated after success | Recognize working tools and leave their versions/configuration unchanged. |
| A conflicting or unusable installation is found | Report what needs attention rather than deleting or replacing it automatically. |

The spike may rely on the user reporting that an external dialog was canceled and pressing **Check again**. Detecting every external installer event or showing Apple's download percentage inside the app is not required.

### Optional shell experiment

Explain that shell configuration makes fnm-managed tools available in future Zsh sessions; it is not a prerequisite for the app's fixture.

Before editing, detect equivalent fnm initialization. Back up the affected file and make a clearly marked, app-owned addition only when needed. Ensure fnm is discoverable in the new shell context. Repeating the action must not add another loader.

A restore action removes only the app-owned addition while preserving unrelated content. If existing configuration is ambiguous or conflicting, leave it unchanged and report the limitation rather than attempting a general shell-file repair.

## Ownership and boundaries

macOS owns installer dialogs, licensing, authentication, and privileged system installation. Homebrew owns its prefix and package installation behavior. fnm owns the installed Node runtime.

The app owns detection, user-facing setup actions, ordinary-user tool invocation, fixture execution context, and any explicitly accepted shell-file addition. It must not collect passwords, silently elevate, automatically upgrade tools, or treat an arbitrary project command as authorization to provision the machine.

VM reset/snapshot restoration is owned by the human tester. Setup does not promise to undo Homebrew, developer tools, or runtime installations.

## Acceptance criteria

All checks below are manual in the VM. Record observations and relevant diagnostics, not a comprehensive test ledger.

| ID | Requirement(s) | Starting condition / action | Expected outcome | Verification approach |
| --- | --- | --- | --- | --- |
| AC1 | R1, R3 | In a clean supported VM, open development setup and approve the described installation steps. | Apple system dialogs complete developer-tool/Homebrew installation without Terminal, pasted commands, manual edits, or app-owned password prompts. Homebrew runs as the logged-in user. | Manual VM walkthrough. |
| AC2 | R2, R4, R5 | After system prerequisites, provision the pinned runtime with shell files untouched; start the fixture. | Expected Node/pnpm versions are reported; the existing runner discovers a responding fixture site; Stop and restart succeed. Shell files remain unchanged. | Manual version/output, HTTP, and shell-file inspection. |
| AC3 | R3, R6 | On a clean snapshot, cancel one system installation and recheck; then retry. | Setup does not claim completion or advance past the missing prerequisite; retry can complete the path. Merely launching an installer never marks it installed. | Manual cancellation/retry of one representative system dialog. |
| AC4 | R2, R6 | Close/reopen the app partway through setup, then recheck. | Actual installed state is recognized; completed work is reused and remaining work can be continued without blindly repeating installer requests. | Manual interruption/relaunch at one representative boundary. |
| AC5 | R2, R4, R5, R6 | After success, relaunch the app, repeat setup, and run the fixture again. | Working tool versions are retained, setup makes no duplicate changes, and the fixture runs without shell-file modifications. | Manual repeat run. |
| AC6 | R7 | After AC2, opt into shell configuration, repeat it, verify a fresh Zsh context, and restore the app-owned change. | fnm works in that shell context; no duplicate initialization is added; unrelated content survives configuration and restoration. | Manual file comparison and app-launched shell check; no Terminal required. |
| AC7 | R1 | Inspect development-only gating and start an ordinary project without entering setup. | Provisioning is not exposed in Release; ordinary Start does not install tools or request authorization. | Source inspection plus manual ordinary-project launch. |
| AC8 | R8 | Complete the representative VM checks. | A short findings document records environment, pinned versions, observed dialogs/permissions, runtime environment strategy, outcomes, and remaining blockers. Unrun cases are labeled unrun. | Human-authored findings; screenshots/log excerpts only where useful. |
| AC9 | R9 (historical; superseded by R12/AC12) | The earlier compact DEBUG surface was to expose one current-check-derived footer action, explicit external waiting, grouped runtime status, accessible close, title-context-menu Advanced tools, and optional shell configuration. | R12 retains the compact layout rationale and safety boundaries while replacing the single footer action with per-tool rows. The earlier verification remains historical and does not override the current AC12 contract. |
| AC10 | R10 | Review the final provisioning source tree and diff after the approved architecture refactor. | Provisioning sources are focused under `dev-manager/Provisioning/` with UI in `Views/`; the model coordinates concrete helpers; shared pins/environment values have one coherent owner; existing DEBUG guards and behavior-sensitive safety boundaries remain visible; `ContentView` keeps `ProvisioningView(onFixtureReady:)`; no unrelated runner/store/project changes appear. | Source inspection and `git diff --check` only for this authoring pass. User-owned build, manual regression, Release, tests, VM, and final integration gates remain pending. |
| AC11 | R11 | Review the shared runner and focused DEBUG regression cases. | Checks and installs share `ProvisioningProcessResult` and the same POSIX-spawn/process-group engine; large concurrent output completes with bounded tails; leader-only timeout cleanup reaps the leader, and a leader that exits while a same-group descendant holds pipes returns by the injected deadline with partial diagnostics and cleaned group; detached process trees are outside this scoped guarantee; no check/install policy or normal runner behavior is conflated. | Source inspection plus the three focused Swift Testing cases in the user-owned Xcode verification; no agent test run. |
| AC12 | R12 | Inspect the per-tool DEBUG setup surface through missing, blocked-prerequisite, external-waiting, attention, active-install, and all-ready states. | Each in-scope tool has a current-state row action; actions are mutually exclusive, consent is targeted to one tool, dependencies are enforced, external handoffs require recheck, active work shows progress, fixture preparation is separate, optional shell controls remain non-blocking, and the presentation keeps the shared 32-point content minimum with 10-point vertical padding, inset inter-child separators, and flush trailing action edge. | Source inspection and `git diff --check` only in this authoring pass; Debug/manual/VM/regression/final gates remain pending. |

## Assumptions

- The user's VM supports Apple Silicon macOS 15+ with a graphical console, internet access, and a logged-in administrator. Validate the environment before the first walkthrough.
- A fresh snapshot can be restored between destructive installation attempts. Resetting the VM is a human task, not app functionality.
- One pinned, mutually compatible Node/pnpm pair is sufficient to validate the execution approach. Supporting multiple project runtime requirements is deferred.
- Basic diagnostics and manual **Check again** actions are sufficient for this spike. Automatic installer observation and polished error recovery are not necessary to answer the feasibility question.

## Risks and open decisions

- Blocking: None before planning. Real installer and runtime behavior remains unvalidated until VM testing.
- Non-blocking: Administrator credentials do not by themselves prove correct Homebrew ownership. Verify execution as the console user after installation.
- Non-blocking: Apple dialogs, download availability, and full-Xcode prerequisites can vary. Record observed behavior rather than assuming a successful request guarantees a working toolchain.
- Non-blocking: The existing runner starts an interactive login shell. Prove the explicit runtime context survives that launch path without requiring shell edits.
- Non-blocking: Existing custom fnm or shell configuration may not fit the narrow managed-block approach. Report conflicts instead of expanding into migration or repair.
- Non-blocking: Shared writable Homebrew prefixes retain Homebrew's documented trust limitations; this spike does not establish a multi-user security model.

## Deferred work

- Production onboarding and provisioning architecture, informed by the VM findings.
- Standard-user accounts, Intel, managed deployment, and broader installation-state compatibility.
- GitHub authentication, arbitrary project setup, multiple runtime versions, upgrades, uninstall, and repair.
- Automated installer simulation or broader regression coverage, if a production feature justifies it.
