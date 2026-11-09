# Dev Manager MVP Specification

## Status

- Readiness: Ready for planning
- Blocking decisions: None for the MVP contract. The owner supplies the Xcode scaffold before application implementation.
- Overview: [overview.md](overview.md)
- Source: The preceding grill-me conversation, supplied Vite/Next.js screenshots, and the owner's explicit setup/testing preferences.
- Implementation plan: [plan.md](plan.md)
- This is specification readiness, not an implementation, release, or deployment approval.

## Problem and intended outcome

Developers currently use terminals to start and stop development commands for local projects. Dev Manager provides a native SwiftUI macOS interface to manage those commands, inspect their output, and open the actual local website after startup—even when a dev server automatically chooses a different port.

The app manages the real development process, not a substitute HTTP server. A command such as `pnpm dev` retains its ordinary project-specific behavior and may launch several subprocesses.

## Scope

Included:

- Directly distributed SwiftUI application targeting macOS 15.0 (Sequoia) and later for the owner and a small group of known users, outside the Mac App Store.
- Add local project folders, configure one development command per project, and start/stop projects independently.
- View command output and distinguish process lifecycle from website availability.
- Automatically discover current-run local HTTP/HTTPS websites, including dynamically selected ports, and open them in the default browser.
- Window-close and app-quit behavior that preserves clear ownership of managed processes.
- Best-effort, warning-only recovery of verified stale managed process groups on the next launch, under an explicit single-app-instance assumption.
- Owner-created Xcode scaffold and primarily owner-driven manual validation.

Non-goals:

- Mac App Store sandboxing, a full terminal emulator, or interactive command input.
- Git operations, dependency installation, editing project files, or one app-managed command per service within a project.
- Launch-at-login, automatic project startup, automatic crash restart, an in-app Restart action, cross-run log history, or reconnecting to processes from a previous app instance.
- Guaranteed stale-process recovery, adoption/reconnection, crash-instant cleanup, watchdog supervision, or concurrent-instance coordination.
- LAN/public URL presentation, remote development, containers' internal port discovery, tunnels, or guaranteed discovery for arbitrary non-web commands.
- Deep application health checks, continuous uptime monitoring, persistent log archives, or guaranteed cleanup after Force Quit/crash.
- A sophisticated testing harness, exhaustive automated coverage, or broad UI automation for the initial MVP.

## Current behavior and evidence

- Static inspection found `/Users/andy/Documents/Development/dev-manager/` empty: no application scaffold, source, tests, build configuration, Git metadata, existing planning documents, or applicable project instructions were available. No runtime behavior was inspected and no builds/tests were run.
- The owner will create the application scaffold using Xcode. The owner subsequently selected macOS 15.0 as the minimum deployment target. Xcode project layout and test framework remain tied to the owner's scaffold.
- Supplied Vite screenshot: `Local: http://localhost:3000/`, with a separate informational Network line. Expected website choice: one local URL.
- Supplied Next.js screenshot: `Local: http://localhost:3000` and `Network: http://172.16.48.137:3000`. Expected website choice: only `http://localhost:3000`.
- These screenshots are reference output, not evidence that Dev Manager already launches either server. Runtime parity and port rollover remain to be validated.

## Requirements and invariants

- **R1 — Project configuration:** A user can register a local project folder and configure one nonempty development command. `pnpm dev` is the editable default; no package-manager restriction applies. Saved folders and commands survive normal app relaunch. Adding/configuring a project does not execute its command.
- **R2 — Real command execution:** Start executes the configured command in the selected project directory with the user's privileges and a usable development-tool environment. It preserves the command's project-specific behavior, captures stdout/stderr, and does not require changes to project or shell configuration files. Invalid paths, missing tools, and launch failures are visible and recoverable.
- **R3 — Lifecycle and isolation:** Start and Stop manage one active run per project, including its ordinary subprocesses. Stop first requests graceful shutdown and escalates within a finite shutdown interval. A subsequent Start is allowed only after the prior run is no longer active. Operations on one project must not terminate or modify another project's processes, unrelated listeners, or project files.
- **R4 — Window/app lifetime:** Closing the main window leaves managed commands running and the app available to reopen. Normal Quit stops all managed runs before the app exits, subject to finite escalation and visible cleanup errors. Crash/Force Quit cleanup is not guaranteed.
- **R5 — Output:** The selected project's stdout/stderr is visible while running and after Stop or exit until the next Start, within a bounded log buffer. A successful subsequent Start intentionally begins a fresh bounded log buffer; cross-run log history is not required. One busy stream must not prevent the other from being consumed or freeze app controls. Output from different projects/runs remains identifiable.
- **R6 — Automatic current-run discovery:** The app automatically discovers the actual local website address on every run without requiring a configured URL or fixed port. It uses announced output and, when output does not reveal a website, process-associated listening endpoints. Only candidates attributable to the managed run may become website actions. An unrelated service on a project's previously used port must not be mistaken for that project's website.
- **R7 — Local-only website choices:** Only local HTTP/HTTPS website URLs are eligible. LAN/public URLs and non-web endpoints are excluded. Duplicate announcements of the same website do not create duplicate choices. The supplied Vite and Next.js examples each yield exactly one website action.
- **R8 — Availability and browser opening:** Process state and website state are distinct. A discovered website becomes openable when its endpoint responds over the advertised/inferred web protocol; this is startup verification, not a continuous health claim. After an endpoint is verified for the current owned listener, HTTP polling stops until that endpoint disappears, its owner identity changes, or a new URL/port is announced. One ready website produces a single Open action; multiple distinct ready websites produce labeled URL choices. The action opens the selected URL in the default browser. A running command without a detected website remains manageable and is not classified as a failed process.
- **R9 — Run freshness and cancellation:** Stop, exit, and a subsequent Start invalidate website actions from the affected run. Delayed logs, probes, and discovery results from an older run cannot update a subsequent run or resurrect a stale action. Stopping during startup remains possible. The app must not deliberately open a site from an ended run.
- **R10 — Distribution and trust boundary:** The MVP requires macOS 15.0 or later and targets direct distribution outside the Mac App Store, without App Sandbox restrictions on its development-command workflow. Commands run as the current user, never through automatic privilege escalation. Selecting a folder is not authorization to execute it automatically.
- **R11 — App-only project removal:** After explicit confirmation, a registered project can be removed from the app's saved entries by stable ID without deleting, moving, or modifying its folder or files. Cancellation is nonmutating; a failed save retains the entry and selection with a visible recoverable error, and removal is disabled in read-only settings mode.
- **R12 — Best-effort stale-run recovery:** The app may recover a stale managed process group on launch only when one atomic app-support JSON journal entry identifies the project, PID, PGID, and OS process start time, and all identity checks are positive. It rechecks identity before each SIGTERM/SIGKILL, uses a short finite wait between signals, and emits warning diagnostics without requiring a UI warning. Dead, mismatched, or ambiguous metadata is dropped or left alone without signaling. Journal I/O failure never deletes project settings or stops a process that is not positively owned; concurrent app instances are explicitly unsupported.

## Behavior and contracts

### Setup and everyday use

1. The owner creates a native macOS SwiftUI application scaffold in Xcode. Implementation works within that scaffold rather than generating or replacing it without coordination.
2. A user adds a project folder, opens that project's toolbar `Project Settings` gear to review or change the default `pnpm dev` command, and explicitly starts it. The selected-project detail view contains only `Execution` and `Output`; the settings sheet owns Save/Cancel and the bottom app-entry-only removal action. The app need not inspect Git history or enforce Git-specific behavior.
3. Output appears as the command starts. The app separately indicates that the process is running and that website discovery is in progress.
4. Once a local endpoint responds, the user can open it in their default browser. If multiple local websites are identified, the app offers their URLs rather than guessing a primary website.
5. Stop shuts down the managed run. A user can then Start it manually after cleanup; each successful new run begins fresh discovery and fresh logs.
6. Closing the window does not stop work; reopening restores access to it. Quitting normally stops managed runs.

### State model

Process state and website discovery are separate dimensions; a ready process is not necessarily a ready website.

| Process condition       | Website condition                  | Observable behavior                                                                                        |
| ----------------------- | ---------------------------------- | ---------------------------------------------------------------------------------------------------------- |
| Not started/stopped     | None                               | Start available; no active Open action.                                                                    |
| Launching/running       | Discovering or checking candidates | Logs and Stop available; no unverified Open action.                                                        |
| Running                 | One responding local website       | Single Open action with the actual URL.                                                                    |
| Running                 | Multiple responding local websites | URL-labeled choices; no arbitrary primary selection.                                                       |
| Running                 | No local site detected             | Keep process controls/logs available; this is not a process failure. Later output may still reveal a site. |
| Stopping                | Invalidated                        | No active Open action; shutdown in progress; no overlapping Start.                                         |
| Exited/failed to launch | Invalidated                        | Explain exit/error and retain available logs; explicit Start can recover.                                   |

Exact labels, icons, and visual layout are implementation choices. Discovery cannot block process controls or continue presenting old actions after the run ends.

### Commands, environment, and shutdown

- A command is a user-editable shell command, not an enumerated package-manager choice. It runs from the registered folder; shell syntax may be used without the app interpreting project-specific scripts.
- The app must account for GUI-launched environment differences. It must not assume Finder provides the same PATH as Terminal. The first implementation is validated against the owner's actual shell/version-manager setup; unsupported setups get actionable errors, not silent execution of an unrelated command.
- Interactive prompts/terminal keybindings are not supported. Logs are output, not terminal input. A waiting command remains stoppable.
- Graceful shutdown and escalation must cover ordinary child processes spawned by package managers. Implementation may choose process groups, a helper, or another suitable mechanism; terminating only the initial launcher is insufficient.
- Shutdown/probe timings are finite implementation settings rather than user-facing configuration in v1. Their values must be documented in the later plan and exercised manually; no indefinite quit wait is acceptable.
- Failure to launch or stop does not delete project configuration. If cleanup cannot be completed, do not claim success; surface the condition and preserve whatever ownership information remains usable.
- Stale-run recovery is deliberately bounded and warning-only: write one atomic JSON entry per run after spawn as soon as practical, remove it only after confirmed stop, and accept the spawn-to-write window. On launch, require a live PID, matching OS process start time, and the PID still leading the recorded positive PGID before signaling; recheck identity before each signal. A dead leader with live children is dropped rather than recovered. Recovery never adopts/reconnects, calls a child-only `waitpid` routine for a non-child orphan, installs a watchdog, or adds locking/owner metadata, PTY support, environment markers, or log archives. Failed journal I/O is logged and does not alter project settings or non-owned processes.

### URL discovery and readiness

- Discovery observes both output streams from the current run, tolerates terminal color/control formatting and chunk-split lines, and extracts candidate web URLs rather than arbitrary text links.
- Default local host policy is `localhost`, IPv4 loopback `127.0.0.1`, and IPv6 loopback `::1`. Hostnames are parsed as URLs, not accepted by substring matching. `localhost.example.com` and a URL with `localhost` only in its path are not local.
- A `Network` URL such as `http://172.16.48.137:3000` is not shown alongside the local URL. HTTP documentation links, WebSocket-only endpoints, inspector ports, and other non-web listeners are not website choices.
- Listening-endpoint fallback is restricted to the managed run's processes. A wildcard bind can yield a loopback probe candidate, but `0.0.0.0`/`::` must not be presented as the browser destination. Do not turn arbitrary LAN output URLs into additional website choices.
- Prefer an announced local scheme/base path when available. Socket fallback must not add a duplicate root choice for that same website. At minimum, identical URLs differing only by an omitted root slash collapse into one choice; meaningful paths are not discarded.
- Candidate discovery alone does not imply availability. A completed HTTP response indicates a responding endpoint even if its status is 401, 404, or 500; it does not certify successful page rendering or dependency health. A raw TCP listener alone is insufficient. Once this startup response is verified, discovery may continue scanning for new announcements/listeners and ownership changes without repeatedly health-probing the unchanged endpoint.
- Probes must remain local: do not follow redirects into LAN/public hosts. Opening a local URL in the user's browser does not control what the site subsequently redirects to.
- Do not disable TLS certificate validation globally to make a site appear ready. Untrusted local HTTPS is a visible limitation until a deliberate trust policy is designed.
- No user-entered fixed URL is required as a workaround. When supported discovery finds no website, retain process management and communicate that result rather than fabricating an address. Discovery continues to consider later current-run evidence.

### Defaults versus explicit decisions

The one-command model, package-manager freedom, lifecycle behavior, automatic dynamic-port discovery, multi-site choices, localhost-only presentation, SwiftUI/macOS target, narrow direct distribution, owner-provided scaffold, and lightweight/manual-first validation were explicit user decisions. Persistence, editable `pnpm dev` default, bounded session logs, noninteractive execution, loopback aliases, and readiness semantics are inferred MVP defaults, recorded under Assumptions rather than represented as separately approved interview answers.

## Ownership and boundaries

- The owner owns Xcode scaffolding, local signing/account setup, representative project access, and hands-on validation. Implementation should request owner action for these boundaries rather than silently replacing the scaffold or inventing test results.
- The app owns registered project settings, processes it launches, their captured output, and per-run discovery state. It does not own repository contents, dependencies, shell profiles, or unrelated processes/listeners.
- The configured development command owns the project's build/start behavior. The browser owns navigation after opening the selected URL. Git metadata is not a source of process or website readiness.
- Runtime candidates and async work belong to a specific project/run identity. No stale candidate or broad port-based shutdown may cross that boundary.
- The app owns only its journal metadata and may signal a stale process group after positive identity checks; it does not adopt the process as a new run or reap a non-child orphan.
- Signed/notarized distribution is the recommended release path, not permission to publish. The initial locally working MVP does not depend on a sophisticated installer, update service, or release pipeline.

## Acceptance criteria

All checks below are proposed, not executed. Manual validation is the primary acceptance mechanism. A few small automated checks are appropriate for pure URL filtering/normalization and stale-run logic where inexpensive; no custom integration harness or UI test suite is required.

| ID   | Requirement(s) | Starting condition / action                                                                                                                                     | Expected outcome                                                                                                                                                                                                                                            | Verification approach                                                                                 |
| ---- | -------------- | --------------------------------------------------------------------------------------------------------------------------------------------------------------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | ----------------------------------------------------------------------------------------------------- |
| AC1  | R1, R10        | Add a project, edit its command, then quit/relaunch without pressing Start.                                                                                     | Folder/command persist; no development command runs merely from adding, editing, or restoring the project.                                                                                                                                                  | Owner manual validation.                                                                              |
| AC2  | R2, R5         | Start a real `pnpm dev` project from the app launched through Finder, using the owner's version-manager setup.                                                  | Correct project behavior runs in the selected folder; stdout/stderr are visible; no shell/project files are rewritten.                                                                                                                                      | Owner manual validation with real project.                                                            |
| AC3  | R1, R2         | Configure another available package manager or ordinary shell command and start it; separately try a missing executable or invalid folder.                      | App imposes no pnpm-only restriction; invalid inputs produce actionable errors and leave saved configuration recoverable. A missing registered folder is recovered by removing that saved entry and re-adding the correct folder; no in-place folder switch is required. | Manual.                                                                                               |
| AC4  | R3             | Run two projects and an unrelated local server. Stop one project, then Start it again after cleanup.                                                           | Its ordinary child servers stop and ports are released before the subsequent Start; the other project and unrelated server remain running.                                                                                                               | Manual process/port observation.                                                                      |
| AC5  | R3, R4         | Run commands, close/reopen the window, then Quit normally; include a command that does not exit on the initial graceful request.                                | Window close preserves runs; normal Quit performs bounded escalation for owned processes. Cleanup failure is visibly reported and usable ownership information is retained while the app is running; no indefinite wait or silent claim of cleanup success. | Manual.                                                                                               |
| AC6  | R5             | A command writes substantial output to both streams and then exits.                                                                                             | UI remains usable; both streams are consumed; bounded output remains inspectable after exit and identifiable by project/run.                                                                                                                                | Manual; simple fixture only if useful.                                                                |
| AC7  | R6, R7, R8     | Observe the supplied Vite output shape with a responding server on port 3000.                                                                                   | Exactly one Open action targets `http://localhost:3000/`; readiness is not inferred from text alone.                                                                                                                                                        | Manual real Vite project; small parser check optional.                                                |
| AC8  | R6, R7, R8     | Observe the supplied Next.js output shape with local and `172.16.48.137` Network addresses.                                                                     | Exactly one Open action targets `http://localhost:3000`; the Network address is excluded.                                                                                                                                                                   | Manual real Next.js project; small parser check optional.                                             |
| AC9  | R6, R8, R9     | Occupy a project's default port with an unrelated server, then start a dev tool that increments ports. Repeat after Stop then Start with different port availability. | Open targets the actual current-run responding website on its selected port, not the unrelated default-port server or the previous run.                                                                                                                 | Owner manual validation for Vite and Next.js.                                                         |
| AC10 | R6, R7, R8     | A simple managed HTTP server does not print its URL but listens on a discoverable owned TCP port. Also run an unrelated HTTP server.                            | App discovers and verifies the owned local web endpoint automatically; it does not offer the unrelated server.                                                                                                                                              | Manual lightweight fixture, no custom harness.                                                        |
| AC11 | R7             | Output includes repeated root URLs, ANSI formatting, chunk-split text, a LAN URL, a public docs link, and a deceptive hostname such as `localhost.example.com`. | Legitimate local URL is recovered once; nonlocal/deceptive URLs are excluded. IPv4/IPv6 loopback candidates follow the same policy.                                                                                                                         | Focused automated parser checks preferred; manual samples acceptable.                                 |
| AC12 | R7, R8         | A managed command exposes two distinct responding local websites plus a non-HTTP listener.                                                                      | Both websites appear as labeled choices; non-HTTP listener does not; selecting a choice opens that exact URL in the default browser.                                                                                                                        | Manual.                                                                                               |
| AC13 | R8             | Run a command with no website; separately observe a printed URL whose endpoint is not listening, then begins responding.                                        | Non-web command remains manageable; unresponsive candidate is not yet openable; responding endpoint enables Open without claiming application health.                                                                                                       | Manual.                                                                                               |
| AC14 | R3, R9         | Stop during startup, or Stop then Start after cleanup while old probes/log processing are outstanding.                                                         | Controls remain usable; no overlapping project runs; old results cannot enable a stale Open action or affect another project.                                                                                                                           | Manual; focused state test if inexpensive.                                                            |
| AC15 | R8, R9         | A ready command exits; separately probe a local endpoint returning 404 and one redirecting to a nonlocal URL.                                                   | Exit invalidates its actions; 404 counts as responding, not healthy; discovery does not follow the nonlocal redirect. TLS errors are not silently bypassed.                                                                                                 | Manual targeted checks.                                                                               |
| AC16 | R10            | Review development/distribution configuration and perform a normal user launch.                                                                                 | Workflow is outside App Sandbox restrictions, runs at current-user privileges, and does not request automatic elevation.                                                                                                                                    | Static configuration review and owner manual validation; signing/notarization checked before sharing. |
| AC17 | R6, R7, R8     | Start a managed local HTTPS server with a certificate already trusted by the system and a discoverable URL or owned listener.                                   | The responding HTTPS endpoint becomes one openable local choice using HTTPS, without silently downgrading it or disabling certificate validation.                                                                                                           | Manual targeted check; owner supplies a trusted local HTTPS setup when available.                     |
| AC18 | R1, R11        | Select a saved project, inspect its read-only name/folder and command field, reveal the folder, cancel the removal confirmation, then confirm removal; separately make the settings save fail during removal. | Name and folder values share a leading column; the folder action reveals the selected folder in its parent without switching or mutating it, and is disabled with an explanation when unavailable. The command field is explicitly leading-aligned. Cancel leaves the selected entry and disk folder/files unchanged. Confirmed removal deletes only the app's saved entry by stable ID, clears the selection or selects another registered project, and leaves folder/file bytes untouched. A failed save leaves the entry and selection intact with a visible recoverable error; read-only mode disables removal. | Native store tests plus owner UI walkthrough. |
| AC19 | R12            | Start a managed server, stop the app without confirmed cleanup, then relaunch under the single-app-instance assumption; separately present dead, start-time-mismatched, and ambiguous journal metadata. | A journal entry is written after spawn as soon as practical and removed only after confirmed stop. Relaunch signals only a live PID whose OS start time matches and which still leads the recorded positive PGID, using SIGTERM then short-wait SIGKILL with identity rechecks. Dead or mismatched metadata is dropped without signals; ambiguous permission/group/identity is left alone with a diagnostic warning; normal cleanup removes the entry. A dead leader with live children is deliberately not recovered, and journal I/O failure does not delete project settings or stop non-owned processes. | Owner-approved manual recovery walkthrough with isolated metadata fixtures only if needed; focused journal/state checks are optional and do not require a harness. |

## Assumptions

- **Noninteractive commands:** A pipe/log experience is sufficient; terminal input, TUIs, and PTY behavior are not MVP requirements. Validate with representative real projects before broadening scope.
- **Persistence and logs:** Project settings persist; logs use a bounded per-run buffer, remain available after Stop or exit until the next Start, and may be truncated with clear indication. Each successful Start begins a fresh buffer; cross-run history is not required. Exact buffer size/storage is an implementation choice, not a reason to add a persistence framework.
- **Manual startup:** Registered projects do not auto-start on launch. `pnpm dev` is a convenience default, not required tooling.
- **Recovery instance model:** Stale-run recovery assumes one app instance; concurrent instances are unsupported rather than coordinated with a lock or owner metadata.
- **Local aliases:** `127.0.0.1` and `::1` count as localhost for this feature. Other custom domains, including custom loopback-resolving names, are excluded initially.
- **Git/folder handling:** Typical inputs are Git project folders, but Git integration or Git-only eligibility checks are unnecessary for running a command. Missing/non-directory paths must be rejected; no automatic Git initialization is implied.
- **Readiness definition:** Any actual HTTP response establishes site responsiveness, not successful rendering. A finite no-site indication is informational and must not prevent later discovery.
- **Environment coverage:** Initial compatibility is proven against the owner's setup and available testers, not every shell/version-manager combination. The later plan should name those environments after scaffold/project inspection.
- **Release packaging:** Signing/notarization are recommended before personal distribution; no update mechanism or installer is assumed for the initial working build.
- **Implementation independence:** Lower-level launch APIs, process attribution, socket inspection, storage format, exact shutdown timeouts, and UI composition remain open implementation choices subject to this contract.

## Risks and open decisions

- **Blocking:** None at the behavioral-spec level. Application implementation depends on the owner's Xcode scaffold being available. This is an explicit handoff dependency, not a request for the agent to generate it.
- **Non-blocking — discovery limits:** An arbitrary command can detach children, delegate to existing external services, use non-TCP transports, or expose ambiguous endpoints. The MVP guarantees automatic behavior for the supported local process-owned HTTP/HTTPS cases, not omniscient discovery. Validate the socket fallback early; report unsupported/no-site cases truthfully.
- **Non-blocking — ownership and shutdown:** Descendants that deliberately detach can escape ordinary tracking. Avoid unsafe global port-based termination; visibly report known cleanup failures. Force Quit/crashes can leave servers running, and a later app instance must not adopt/kill them by port alone.
- **Non-blocking — stale-run recovery:** The journal narrows a best-effort relaunch cleanup decision to positive PID/start-time/PGID identity; permission or group ambiguity, a dead leader with live children, journal I/O failure, and the spawn-to-write window remain deliberately unresolved without signals.
- **Non-blocking — shell initialization:** Startup files may be slow, emit output, prompt, or select different Node versions. Environment loading needs diagnostics and manual validation without modifying user configuration.
- **Non-blocking — HTTPS:** Self-signed development certificates may prevent verified readiness. Trusted local HTTPS is eligible; custom certificate trust and browser warnings require a later deliberate policy.
- **Non-blocking — scaffold details:** The minimum deployment target is settled at macOS 15.0. Xcode project structure, signing identity, and app name are set with the owner when the scaffold is supplied; none changes the agreed MVP behavior.
- **Non-blocking — test discipline:** Manual-first validation still needs concrete observations of port rollover, process isolation, shutdown, and stale results. Proposed acceptance checks must not be reported as passed until observed.

## Deferred work

- External supervision/guaranteed crash cleanup and reconnecting to prior runs, if actual orphan-process incidents justify the complexity.
- Interactive terminal support, automatic restart policies, multi-command orchestration, dependency installers, and Git-specific features.
- LAN/public/custom-domain sites, containers/tunnels, stronger framework integrations, and self-signed HTTPS trust policy when demanded by real projects.
- Persistent/searchable log archives, advanced health checks, uptime monitoring, auto-updates, and a polished release pipeline.
- Broader automated integration/UI coverage after a useful working MVP and real failure patterns justify it. Small high-value tests may be added without turning this into a testing-infrastructure project.
