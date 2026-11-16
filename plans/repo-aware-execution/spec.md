# Repo-aware Execution Specification

## Status

- Readiness: Ready for planning
- Blocking decisions: None at the product-contract level, under the production-provisioning prerequisite below. Planning must validate the provider's project-specific version and coexistence capabilities before committing to an implementation approach.
- Overview: [overview.md](overview.md)
- Source: The repo-aware workflow interview in this conversation and the user's subsequent approval of its wrap-up. The user explicitly directed that machine provisioning be assumed to be in production before this scope begins.
- Prerequisite: Production machine provisioning is available on its supported platforms before this work starts. Promoting the current provisioning spike to production is not part of this scope. This prerequisite does not imply that arbitrary project-specific tool versions are already supported.

## Problem and intended outcome

A developer can currently add any folder, receive a default `pnpm dev` command, and discover only on launch that the folder, command, package manager, or Node version is unsuitable. Having tools installed on the machine does not ensure that a particular repository uses the right tools.

The intended outcome is a guided Node-project experience: understand the selected folder, explain its requirements, obtain approval for setup, and run a chosen script with the resolved tools. Other folders and arbitrary shell commands remain usable through an explicit custom-command path.

## Scope

Included:

- Read-only project recognition and Node/npm/pnpm requirement discovery.
- A top-of-project requirements banner and explicitly approved setup of missing tools.
- Guided script selection and execution with the resolved toolchain.
- A separately approved dependency-install action.
- Selected-folder execution, including package folders that inherit requirements from a containing workspace.
- Preservation of existing projects, custom commands, logs, and process lifecycle controls.

Non-goals:

- Implementing or releasing foundational machine provisioning.
- Requiring Git, rejecting all unrecognized folders, or supporting only Node projects.
- First-class Yarn, Bun, Python, Ruby, containers, or other ecosystems.
- A workspace picker, recursive package discovery, or multi-service orchestration.
- An app-level Node/package-manager version switcher, editing repository version declarations, or dependency upgrades.
- Automatic installs on add or Run, interactive terminal sessions, or sandboxing repository scripts.
- Expanding the platform or account support matrix of production provisioning.

## Current behavior and evidence

These are static source observations, not runtime verification. The production prerequisite above deliberately supersedes the checkout's current DEBUG-only provisioning availability.

- [Project.swift](../../dev-manager/Projects/Project.swift), lines 3–48: projects store an ID, standardized folder path, and nonempty command; the default command is `pnpm dev`. Validation does not establish that the folder contains a development project.
- [ProjectStore.swift](../../dev-manager/Projects/ProjectStore.swift), lines 5–120: schema-1 JSON persistence uses atomic writes; unreadable or unsupported settings produce a read-only state rather than replacement data.
- [ContentView.swift](../../dev-manager/App/ContentView.swift): the folder picker registers a project without repository metadata discovery.
- [ProjectSettingsSheet.swift](../../dev-manager/Projects/Views/ProjectSettingsSheet.swift), lines 78–109: arbitrary command editing is supported, with changes taking effect on the next start.
- [ProcessLauncher.swift](../../dev-manager/Runs/ProcessLauncher.swift), lines 58–62 and 169–190, and [ShellEnvironment.swift](../../dev-manager/Runs/ShellEnvironment.swift), lines 7–30: launch uses the selected folder as cwd, a login/interactive zsh invocation, noninteractive stdin, and a baseline PATH that shell startup files can modify.
- [ProcessSupervisor.swift](../../dev-manager/Runs/ProcessSupervisor.swift), lines 83–280: the runner owns process-group cleanup, rejects overlapping runs, and applies a 10-second shell-readiness timeout. Setup and dependency installation are not dev-server startup.
- [ProvisioningRuntimeInstaller.swift](../../dev-manager/Provisioning/ProvisioningRuntimeInstaller.swift) currently installs one configured Node/pnpm pair through fnm and npm-global installation. [The spike spec](../_completed/provisioning-spike/spec.md) excludes multiple runtime versions and project dependencies. Neither static source nor production availability alone establishes version coexistence.
- Existing [project tests](../../dev-managerTests/Projects/ProjectStoreTests.swift) and [runner tests](../../dev-managerTests/Runs/ProjectRunnerTests.swift) supply compatibility seams; they do not establish the new discovery or tool-selection behavior.

Deliberate changes are guided detection, an informed initial command instead of a blind `pnpm dev` default, and toolchain-controlled execution for guided projects. Custom-command execution remains a distinct compatibility path.

## Requirements and invariants

- **R1 — Safe recognition:** Adding or inspecting a folder must not execute repository code, download tools, install dependencies, or modify the repository. Unrecognized folders remain addable through a custom command.
- **R2 — Explainable resolution:** Guided projects must resolve Node, npm/pnpm, and a package script from declared metadata and visible defaults. Requirements must retain their source. Unsupported or contradictory input must not cause a silent package-manager substitution or incompatible runtime choice.
- **R3 — Explicit machine changes:** Missing tools must be explained in a banner at the top of the project view. Only explicit approval of the displayed setup may initiate tool installation; neither adding a project nor Run supplies that approval.
- **R4 — Stable toolchain isolation:** Guided execution and dependency installation must use the resolved Node/package-manager combination, independently of the shell-selected versions. Preparing or running project A must not change project B's selected tools, global runtime defaults, or shell configuration.
- **R5 — Predictable execution:** A guided dev command must run the selected package script from the registered folder. Custom commands must remain available. Logs, Stop, overlapping-run protection, and quit cleanup must retain their existing behavior.
- **R6 — Separate dependency approval:** Dependency installation must be a separate approved operation that identifies its command, folder, and possible workspace scope. It must never be an implicit part of machine setup or Run.
- **R7 — Honest state and recovery:** Inspection, setup, installation, failure, cancellation, and stale requirements must be distinguishable. Failed or stale work must not produce a false ready state or authorize new work against changed requirements.
- **R8 — Compatibility:** Existing IDs, folders, commands, and settings protections must survive any persistence change. Existing arbitrary commands must not be rewritten or silently switched to guided execution.
- **R9 — Bounded operation ownership:** Metadata inspection must be bounded and non-executing. Mutating operations must own their subprocess lifecycle, expose progress and failure, prevent conflicting operations, and avoid unrelated project or machine changes.

## Behavior and contracts

### Add, recognize, and choose a command

The add flow validates that the selected path is an accessible directory, then inspects metadata. A readable, parseable `package.json` in that folder is the primary Node-project signal; Git is not required. A malformed or absent manifest produces an explanation and the custom-command option, not an assertion that the folder is unusable.

For a recognized package, suggest its `dev` script when available. Otherwise show its available scripts and permit custom-command entry; do not manufacture a missing `dev` script or execute scripts to discover their purpose. Script names and metadata are data, not shell fragments. If the manager is unresolved, defer the runnable suggestion until resolution rather than guessing pnpm.

Guided mode selects a package script and managed tools. Custom mode accepts the existing arbitrary shell-command contract and labels the toolchain as shell-controlled; managed-version guarantees and setup gates do not apply to that command. Editing a guided command into an arbitrary shell command requires a visible switch to custom mode. Existing saved projects begin as custom projects until the user explicitly adopts guided execution. They may show detected requirements as advisory information with an option to adopt guided mode; managed setup and dependency-install actions are not offered until that adoption. Their custom Run remains available independently.

### Workspace and metadata boundaries

The registered folder remains the cwd for dev commands and dependency-install subprocesses. Detection does not silently substitute a Git root, workspace root, or descendant package. It examines the selected folder and ancestors needed to establish the nearest containing declared workspace, not a recursive repository scan.

A containing workspace must declare membership through `package.json` workspaces or `pnpm-workspace.yaml`; an unrelated ancestor manifest is not an inheritance source. Search does not cross an enclosing Git boundary when present. Git absence does not prevent recognition. Relevant root tool declarations and lockfiles may be inherited from the nearest established workspace; selected-package declarations are more specific. Inherited engine constraints still apply, and incompatible package/root requirements require attention rather than an automatic override.

Inspection reads declarative data only: no shell evaluation of version files, package imports, lifecycle hooks, Git hooks, or execution of a discovered binary. Limit an individual parsed metadata file to 1 MiB; lockfile existence can be used without parsing its contents. Unreadable, oversized, or unsupported input produces a diagnostic. Do not automatically read metadata symlinks whose targets escape the selected package and established workspace boundaries. Preserve the registered path as cwd even when canonical paths are used to check containment.

### Tool requirement resolution

| Input | Contract |
| --- | --- |
| `.nvmrc` / `.node-version` | Use the nearest applicable package/workspace declarations as Node selectors. If both apply and conflict, require attention rather than choosing by filename. Never evaluate their contents as shell code. |
| `package.json` `engines.node` | Treat as a compatibility constraint, not an exact installation pin. A selected version must satisfy applicable package and inherited workspace constraints. |
| `package.json` `packageManager` | Authoritative manager/version declaration at the applicable scope. npm and pnpm are supported; another manager is explained as unsupported in guided mode. Tool declarations containing executable expressions or arbitrary download locations are not executed. |
| Lockfiles | Without an applicable `packageManager`, `package-lock.json` / `npm-shrinkwrap.json` indicate npm and `pnpm-lock.yaml` indicates pnpm. Conflicting manager lockfiles require attention. Yarn/Bun evidence must not silently become npm or pnpm. |
| No manager declaration or lockfile | Propose npm, explicitly labeled as a default. |
| No exact Node selection | Reuse an installed compatible supported version when possible; otherwise propose a concrete compatible supported stable version. With no Node constraint, use the production provisioning default. |
| No manager-version pin | Use npm bundled with the selected Node, or the production pnpm default, and show that the version is a default rather than a repository pin. |

A valid explicit manager declaration takes priority over lower-priority lockfile evidence; contradictory lower-priority evidence is surfaced as a warning, not concealed. A conflicting explicit Node selector or impossible engine intersection blocks guided readiness. Exact version pins must not be silently relaxed. If a pinned npm/pnpm version cannot be supplied in isolation, show attention; do not substitute bundled npm or globally replace a manager used by another project. Supported ranges/partial selectors resolve to a concrete version before installation approval; unsupported expressions or unavailable compatible versions produce an actionable attention state. Prefer the highest installed compatible version, otherwise the highest provisionable compatible stable version. An explicit pin may select another version if supported by provisioning.

The project view shows the effective Node version, manager/version, command, and source of inherited or defaulted choices. No app-level version override is introduced. Editing repository declarations is the normal way to change guided requirements; custom mode remains the escape hatch.

Guided invocation uses resolved absolute executable/entry-point paths, an argument vector, the registered cwd, and an environment that selects the resolved Node for the manager and its child scripts. A JavaScript manager entry point must use the selected Node interpreter, not an unrelated shebang interpreter. Do not route the generated guided command through login-shell startup or shell `eval`. Package-script names are individual arguments; the script body itself retains the package manager's normal shell/lifecycle semantics. Validate the actual Node and manager versions in that same managed invocation context before launching work. Disable implicit tool downloading/version switching by manager shims or project-aware manager resolution during inspection and Run; a missing version returns to the requirements banner instead. Arbitrary shell evaluation remains confined to custom mode.

### Requirements banner and approvals

The top-of-project banner summarizes machine-tool readiness separately from dependency-install results.

| State | User-visible behavior |
| --- | --- |
| Inspecting | Show inspection in progress; no machine mutation or guided launch based on incomplete results. |
| Needs setup | List concrete missing/incompatible tools and versions; offer **Set up requirements**. |
| Waiting for setup | Another machine-tool installation is active; show the wait and allow cancellation without starting a second installation. |
| Setting up | Show progress; prevent duplicate setup; expose cancellation while work is active. |
| Ready | Show the effective toolchain and permit guided Run. This does not claim that dependencies are installed or current. |
| Needs attention | Explain malformed, conflicting, unsupported, or unavailable requirements and the correction/custom-command options. No guessed installation. |
| Setup failed/cancelled | Show the result, re-inspect actual machine state, and allow a fresh approved retry where supported. |

The setup button approves the concrete displayed tool changes; an additional confirmation dialog is not required when those changes are already visible. Foundational machine prerequisites, if still missing on this computer, remain owned by production provisioning and must be disclosed before approval. A changed setup summary requires new approval. Setup never invokes a project dependency install or lifecycle script, changes version declarations, changes shell profiles, or changes global fnm defaults.

Run revalidates the relevant requirements and available tools. It cannot install missing tools. For guided mode, unresolved or missing tools direct the user to the banner. Custom mode retains its existing launch behavior even when guided requirements cannot be resolved. Requirements changes do not silently restart or replace an already running process; display that they apply to the next run.

### Dependency installation

For a recognized guided project with ready tools, offer **Install dependencies** as a separate operation. Before approval, disclose the selected package manager, exact command, cwd, possible shared-workspace effects, and that repository/dependency lifecycle scripts may run. The action button itself can grant approval when that information is visible.

Default command policy:

- npm with an applicable npm lockfile: `npm ci`; without one: `npm install`.
- pnpm with an applicable pnpm lockfile: `pnpm install --frozen-lockfile`; without one: `pnpm install`.
- Never silently retry a failed locked install with a lockfile-changing command.

Commands start in the registered folder. A package manager may operate on its containing workspace; disclose that scope rather than promising package-only changes. Installation uses the same resolved toolchain as guided Run and remains noninteractive. Prompts that cannot be satisfied without stdin must fail with a useful diagnostic rather than hang indefinitely.

Installation exposes progress/output, completion, cancellation, and nonzero exit status. Dependency operations have their own finite lifecycle budget, not the dev-server's 10-second shell-readiness timeout. Presence of `node_modules`, or an earlier successful install, is not proof that dependencies are current. Do not block Run solely because the app has not performed an install, and do not automatically retry or install after a dev-command failure.

### Changes, cancellation, and recovery

Refresh metadata after relevant app actions and before Run, setup, or dependency installation; a continuously running file watcher is not required. Bind approvals to the displayed requirements, target folder, and operation. If these change before work begins, refresh the summary and require new approval. If they change during work, let cleanup complete and re-inspect; completion of the older operation cannot mark the new requirements ready.

Serialize machine-tool installation transactions across all projects, including unrelated workspaces. A second approved setup waits visibly; cancelling it while waiting starts no installation. This does not prevent unrelated ready projects from running. Prevent overlapping mutations for the same project or shared workspace and dependency installation while an app-managed dev process in that workspace is active; explain that the user must stop it first. A shared tool installation must not remove or replace a version another project uses.

Cancellation stops app-owned subprocess groups using the existing cleanup discipline. Provider-owned installation is cancelled through the provider's supported lifecycle; external installer handoffs must not be reported as stopped while their result is still unknown. Keep the installation transaction unresolved until completion or safe reconciliation, rather than starting another potentially conflicting installer. Report cleanup failures and do not claim rollback: partial tool installations, changed dependencies, and lifecycle-script side effects may remain. Re-inspection determines what is actually available before retry. No new guarantee is made for deliberately detached descendants or arbitrary external changes.

## Ownership and boundaries

- Discovery owns declarative metadata, provenance, and resolution diagnostics. It does not invoke commands, install tools, or rewrite repository files.
- The project model owns explicit guided/custom choice, selected script or existing custom command, and compatibility-preserving persistence. Detected metadata is refreshable, not a new authoritative copy of repository configuration.
- Production provisioning owns machine capability checks and approved tool installation. Repo-aware resolution must extend/integrate with it for project-specific versions without assuming that a single production default supports all repositories. Tool installation must not execute repository-local configuration or scripts; project dependency configuration belongs only to the separately approved dependency operation.
- The runner owns controlled tool invocation, cwd, output, and dev-process lifecycle. Guided runtime selection must remain effective even when shell startup selects another Node or manager; custom mode intentionally retains shell behavior.
- Dependency operations own their separately approved subprocess and output, not a hidden dev-server pre-start hook. No new public API or fixed persistence representation is prescribed.

## Acceptance criteria

The approaches below are proposed verification, not checks performed while authoring this document.

| ID | Requirement(s) | Starting condition / action | Expected outcome | Verification approach |
| --- | --- | --- | --- | --- |
| AC1 | R1, R9 | Add a package whose scripts create a marker when executed. | Metadata and script suggestions appear; no marker, download, install, or repository write occurs. | Discovery tests with command/write spies; manual flow. |
| AC2 | R1, R5 | Add folders with no manifest, malformed JSON, or a valid non-Node custom command. | Explanation and custom entry remain available; no Git requirement or forced rejection; custom command can run. | Fixture tests and UI/manual check. |
| AC3 | R2, R5 | Add packages with a `dev` script and, separately, only other scripts. | First suggests the declared `dev` script; second offers actual scripts/custom entry without a fabricated command. Unusual script names are passed as data. | Resolver and launch-contract tests. |
| AC4 | R2 | Resolve exact Node/manager declarations, engine ranges, and an unpinned package. | Concrete compatible versions and their sources/defaults are displayed; no exact pin is relaxed; installed/default/candidate selection follows the stated policy. | Table-driven resolution tests with a fake available-version source. |
| AC5 | R2, R3 | Inspect conflicting Node selectors, incompatible engines, ambiguous lockfiles, an unsupported manager, or an unsupported version expression. | Guided mode shows actionable attention and does not guess or install. An authoritative supported `packageManager` wins over lower-priority lockfiles with a visible warning. | Negative resolution fixtures and UI check. |
| AC6 | R2, R5, R9 | Add a package folder in a declared workspace, then a folder under an unrelated ancestor package. | The workspace member inherits applicable requirements and provenance; the unrelated folder does not. All launched commands retain the registered cwd; no recursive package scan occurs. | Workspace-boundary fixtures and cwd launch tests. |
| AC7 | R3, R7 | Missing tools are detected; add the project or click Run without setup approval, then click Set up requirements. | First actions perform no install. Banner names the missing versions; only the approved setup invokes provisioning, and success is re-inspected before readiness. | Fake provisioning integration and manual banner flow. |
| AC8 | R4 | Two projects require different Node/pnpm versions, including two pnpm versions on the same Node; shell startup selects a third toolchain. | Observe the actual executable paths and reported versions in each guided process and its Node child script: they match that project's selection. Setting up/running either leaves the other's versions, global defaults, and profiles unchanged. Include pinned npm behavior and an unavailable exact manager pin, which must not fall back. | Controlled toolchain integration and supported-machine acceptance. |
| AC9 | R5, R8 | Load schema-1 projects with arbitrary commands and opt one into guided mode. | IDs, paths, and original commands survive; existing projects remain custom until opted in. Custom mode retains Run and advisory detection but offers no managed setup/dependency action until adoption. Guided/custom choice is visible, and no unrelated settings are rewritten or lost. | Persistence/migration tests and settings flow. |
| AC10 | R5, R8 | Run and stop guided and custom projects; edit a command while running; load unsupported settings. | Logs and owned-process cleanup remain available; overlapping starts are rejected; command edits apply next start; unsupported settings retain read-only protection. | Existing regression seams plus targeted runner/store checks. |
| AC11 | R3, R6 | Tools become ready on a fresh clone; click Run without having used Install dependencies. | Setup has not installed dependencies. Run does not install or automatically retry; dependency installation remains a separate action and lack of app install history is not a launch gate. | Operation-spy tests and manual fresh-clone flow. |
| AC12 | R4, R6 | Approve dependency installation for npm/pnpm fixtures with and without their applicable lockfiles. | Disclosed command/cwd/scope match execution and use the resolved tools; locked failure does not trigger an unlocked fallback. Script-execution risk is visible before approval. | Command-contract tests and manual approval check. |
| AC13 | R7, R9 | A dependency install runs longer than shell readiness, exits nonzero, requires input, or is cancelled. | It has its own finite operation budget, displays output/result, does not hang indefinitely, cleans up owned processes, and does not falsely report success or rollback. | Controlled subprocess fixtures and UI recovery check. |
| AC14 | R3, R7 | Change requirements after the banner is shown, before execution, and during setup. | Stale approval starts no changed work; completed old work cannot mark new requirements ready; refresh/reapproval is available. A running dev process is not silently restarted. | State-transition and stale-result tests. |
| AC15 | R4, R7, R9 | Attempt duplicate setup or install while a conflicting workspace operation/dev process is active; request setup from two unrelated projects and cancel the waiting request. | Workspace conflicts are blocked with an explanation; only one machine-tool installation executes at a time; the waiting cancelled request starts nothing. Unrelated ready projects remain runnable and no in-use version is replaced. External provider work is not declared cancelled before its result is known. | Coordinator/concurrency tests with provider handoff fixtures. |
| AC16 | R1, R2, R9 | Inspect oversized metadata, shell-like version-file content, an escaping metadata symlink, and repo-local install configuration. | Inspection remains bounded and executes nothing; unusable metadata is diagnosed; machine-tool installation never executes repository-local scripts/configuration. | Filesystem fixtures and provisioning invocation tests. |
| AC17 | R7, R9 | Cancel or fail setup after a tool has partly installed; retry after inspection. | UI reports the actual result and residual state, performs owned-process cleanup, and bases the next approved operation on refreshed requirements rather than assuming rollback. | Fake-provider state tests and supported-machine recovery check. |

## Assumptions

- **A1 — Explicit prerequisite:** Production provisioning is available before this work starts. Validation of its actual APIs, platform matrix, exact-version supply, and coexistence behavior is a planning entry gate; productionizing it is not an added work item here. Project-specific version resolution and isolated manager supply remain this feature's responsibilities where the provider does not already supply them. Do not commit to the current single-pair installation mechanism without establishing these properties.
- **A2 — Derived defaults:** npm fallback without manager evidence, deterministic compatible-version selection, locked-install commands, and the 1 MiB metadata limit are specification defaults chosen to make the agreed experience actionable, not separately interviewed preferences. Review these against representative repositories during planning; changes must preserve the approval and compatibility invariants.
- **A3 — Existing-project adoption:** Opt-in guided execution is a compatibility default because current commands may depend on shell setup. Validate migration ergonomics without silently changing saved command semantics.
- **A4 — Conservative operation concurrency:** Blocking dependency mutation while an app-managed process uses the same workspace avoids mid-run dependency replacement in this first version. External tools/processes are outside the app's complete visibility and cannot be guaranteed conflict-free.

## Risks and open decisions

- Blocking product decisions: None under A1. Technical planning gate: establish how the production provider can supply and retain exact per-project versions, extending it within this feature's scope if needed. If safe isolation cannot be achieved on a target platform, surface that limitation instead of relaxing pins or globally replacing a manager.
- Required technical validation: Coexistence of multiple npm/pnpm versions, especially on the same Node version, needs direct supported-machine evidence before treating the selected approach as viable. The current single-pair installer is not evidence of isolation.
- Non-blocking technical risk: Shell startup files and manager shims can override PATH or trigger their own version selection. Managed invocation must be verified against these cases; PATH ordering alone is not proof.
- Non-blocking compatibility risk: Repositories use version aliases, workspace patterns, and unusual metadata. Unsupported forms must fail transparently into attention/custom behavior rather than execute code or invent compatibility.
- Non-blocking trust risk: Approved dependency installs execute untrusted repository/dependency scripts and may mutate a shared workspace. Disclosure and process cleanup are not a sandbox or rollback facility.
- Non-blocking integrity risk: Files can change outside the app during inspection/operation. Revalidation prevents known stale approvals but does not promise an atomic snapshot of an externally mutable repository.
- Verification gap: No app build, test run, install, or live multi-version acceptance was performed for this documentation task. All acceptance approaches above remain future verification.

## Deferred work

- First-class Yarn/Bun and non-Node runtime management; revisit with a separate installation and version-isolation contract.
- App-local version overrides; revisit if repository-led selection and custom mode prove insufficient.
- Workspace selection, recursive discovery, and orchestration of several services.
- Automatic dependency freshness checking, upgrades, repair, and rollback.
- Interactive terminal input and stronger isolation of repository scripts.
