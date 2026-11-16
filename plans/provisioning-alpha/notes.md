# Provisioning alpha notes

## User-approved alpha #1 — PART A

This pass relaxes DEBUG provisioning readiness for Node and pnpm from one exact pair to the small app support snapshot: stable Node majors 22, 24, and 26, with pnpm majors 10, 11, and 12 after a successful probe in the selected Node context. Node 24.21.0 with pnpm 12.6.0 is accepted. These are supported major families, not exact patch requirements, pnpm LTS claims, or automatic security-upgrade promises.

The policy is centralized in `ProvisioningRuntimePolicy`. Its snapshot is grounded in the official Node release schedule ([previous releases](https://nodejs.org/en/about/previous-releases), [release schedule](https://github.com/nodejs/Release#release-schedule)) and pnpm's installation compatibility table ([pnpm installation](https://pnpm.io/installation)). The policy keeps Node 24.22.2 and pnpm 12.18.0 as recommended installation targets only when the corresponding tool is actually missing.

## Runtime boundary

The read-only inspector checks only fnm's local inventory and concrete managed Node paths without sourcing profiles, enabling Corepack networking, or installing anything. fnm is authoritative and required: an absent fnm leaves Node missing and pnpm unverified without warning or standalone probes, and standalone Node paths are not adopted for readiness. Inventory candidates are stable/local and bounded to eight before direct probes, with an aggregate runtime inspection budget of about 20 seconds and an eight-second maximum per probe. The model applies the concrete managed context atomically and clears stale context on a failed refresh. The context records actual Node/pnpm versions and paths plus fnm selector/root.

Existing unsupported, prerelease, or unusable tools remain attention states; no automatic replacement, upgrade, default switch, project metadata parsing, runner fallback, or project execution change is introduced. The fixture remains DEBUG-only but records its selected concrete versions, absolute paths, fnm selector, and command in owned fixture metadata; existing fixture conflicts still refuse changes. Optional shell configuration receives the detected managed selector and is exposed with the core setup in PART B. Fresh-shell verification accepts any supported working pair and reports actual values.

## Focused source-review fixes

Stable fnm selectors are support-checked before prerelease normalization, and inventory RCs are not selected. Runtime inspection now has a local aggregate deadline of about 20 seconds, passes each probe a remaining timeout capped at eight seconds, stops with attention when exhausted, and caps inherited PATH scanning before filesystem checks. Unmanaged fixture handoff uses `/usr/bin/env` with safely quoted selected Node/pnpm parent directories plus a fixed system PATH; the managed fnm command is unchanged. Fixture package and runtime JSON are encoder-generated so quoted or backslash-containing paths and selectors remain valid.

This pass does not implement repo-aware provider metadata/version selection. The repo-aware execution plan's provider boundary, exact-version coexistence, and npm-global isolation remain future work. Known limitations are that the current shell setup helper still owns only its existing marked `~/.zshrc` block, while existing custom commands remain shell-controlled and are not rewritten or given a runner fallback here. The earlier alpha policy that accepted an unmanaged Node/pnpm pair and treated fnm as optional is historical and superseded by the user-approved current policy: Node readiness requires a concrete fnm-managed runtime, and no standalone Node fallback is probed. A fresh machine with missing Node still requires fnm as the installation backend.

## User-approved alpha #1 — PART B

Core provisioning is now available to Release, including read-only inspection, supported runtime installation, optional shell setup/restore, fresh-shell verification, Homebrew/Apple GUI handoffs, installation diagnostics, and the existing safe production setup views. The owned fixture project, fixture metadata and handoff controls remain DEBUG-only. The shared scheme Archive action is Release; Run and Test remain Debug.

Source implementation is complete pending the user’s Debug and Release builds/tests plus manual #2 verification. No builds, tests, Swift parsing, app runs, probes, installs, downloads, network/auth actions, VM/host-shell actions, or log writes were performed for this pass.

## fnm-authoritative data-root follow-up

Diagnosis: the GUI inspector invoked fnm without the user’s selected data root, so an empty/auto-created macOS root could hide the configured legacy inventory and let Homebrew Node 26.10.0 win. The user reports fnm 22.22.2 with default Node 24.21.0; actual Homebrew Node 26.10.0 exists, but no runtime proof was claimed here. Expected behavior is to prefer the fnm 24.21.0 root/default and never change fnm’s default or the machine merely because pnpm is missing.

Source changes: added bounded read-only fnm root discovery with explicit FNM_DIR/XDG precedence plus macOS/legacy auto-discovery, per-process FNM_DIR scoping, authoritative-default retention, root state retention for missing Node, root-aware installs/shell verification/optional shell block, and DEBUG fixture root metadata/commands. Explicit FNM_DIR selects only that root; XDG_DATA_HOME selects only XDG_DATA_HOME/fnm; only unset explicit roots are compared by macOS/legacy evidence. Added focused pure root-precedence and authoritative-context tests; old shell records remain canonical/restorable and are never rewritten automatically.

This was a source-only follow-up: no build, test, parse, probe, app run, install, network action, or runtime proof was performed.

## pnpm discovery review correction

Managed fixture handoff now uses the captured absolute pnpm path after the selected fnm Node/root, with shell-safe quoting. Shared pnpm discovery keeps the selected Node `bin/pnpm` candidate (after any fnm-resolved candidate), then bounded Homebrew/PATH fallbacks, and probes them with the selected runtime and no Corepack network. Fresh-shell verification composes the same selected-Node/system PATH without changing shell configuration ownership. fnm inventory/default/probe failures retain attention evidence; an empty, successfully inspected root may still report Node missing. This source-only pass has no build, test, VM, or runtime proof claim.

## User-approved external shell setup follow-up

The optional shell row now eagerly performs bounded, read-only classification of the existing `~/.zshrc` without sourcing startup files. An unchanged app-owned block is green and restorable; a conservative, standalone external `fnm env --shell zsh` initializer is green as externally configured, with Configure and Restore unavailable. Missing setup still offers Configure. Ambiguous/custom fnm references, unsafe targets, and unreadable content remain neutral/unverified rather than being overwritten; active or changed app receipts remain attention states requiring the existing Restore acknowledgement flow. Fresh interactive Zsh verification remains an explicit Advanced action and is not implied by recognition. Pending user Debug/Release builds, tests, and manual verification are still required; the reported machine is expected to show the external green/no-Configure state, while a clean VM should still offer Configure and managed setup should retain Restore.

## Narrow shell-classification correction

Confirmed root cause: `isAmbiguousFNMSetupLine` latched on the broad `${fnm` substring, so an ordinary `${FNM_DIR:-...}` reference in a `local` path assignment was mistaken for a possible fnm executable. The source-only correction treats an FNM-looking variable as ambiguous only in command/executable position; genuine eval/source and variable-invoked setup remain unknown, while path-only references and comments remain ignorable. The source also tracks function/conditional scope conservatively and recognizes only a standalone top-level `fnm env` initializer. Focused pure tests cover the reported profile-shaped zshrc fixture, assignment regression, wrapper ordering and spacing, wrapped/false-conditional initializers, indirect eval/source setup, and commented paths. The correction is pending the user's Debug/Release build and test execution; no claim is made that the full profile has been runtime-verified here.

## Current user-approved managed-runtime policy

The user explicitly requires Node to be managed by a supported version manager; fnm is the only supported backend in this scope. A reported standalone Node (including `/usr/local/bin/node`) is not evidence of readiness, is never version-probed by the GUI fallback, and leaves the setup surface neutral until fnm is installed and verified. The reported standalone probe timing out after about eight seconds and a later managed Node 26.13.1 result are diagnosis context only; the timeout does not establish its underlying cause. Existing managed Node roots remain authoritative, including the detected legacy root, and supported majors remain Node 22/24/26 and pnpm 10/11/12 without exact patch pins.

The previous accepted unmanaged-runtime policy is historical and superseded, not a current alternative. Repo-aware provider planning remains separate future work and is not changed here.

## Fresh-VM pnpm discovery regression follow-up — pending manual retest

The user reported a fresh VM with fnm and Node 24.22.2 ready but pnpm uninstalled showing `Found pnpm at unknown ... fnm exec which pnpm exit 1`, which incorrectly blocked Install. The source fix removes the redundant `which` probe and uses the bounded shared absolute candidate enumeration for the selected Node bin, Homebrew, and inherited PATH. An empty candidate set now remains a real missing result; an actual candidate version/probe failure keeps attention with its concrete path, and budget exhaustion remains attention rather than missing. The Node environment aggregate row keeps only its status icon/title while child diagnostics remain on the actual rows. This source-only correction is pending Debug/Release build, test execution, and fresh-VM manual retest; no test-passing or runtime-verification claim is made.

## Managed Node alias clarification — pending build/test
A `<fnm-root>/aliases/default/bin/node` symlink is valid managed evidence when its canonical target is inside fnm's `node-versions` store; only system, outside-store, prefix-collision, or dangling targets are rejected. Missing fnm now leaves Node missing and pnpm unverified without probing standalone Node, while failed fnm inspection remains unverified. This source-only clarification is pending the user's Debug/Release build and test execution.

## User-requested compile checks
The earlier source-only sections' no-build statements describe earlier passes and are not retroactive. After the user's limited compiler-check authorization:

- `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer /usr/bin/xcodebuild -quiet -project dev-manager.xcodeproj -scheme dev-manager -configuration Debug -destination 'platform=macOS,arch=arm64' -derivedDataPath /tmp/dev-manager-compile-check-debug CODE_SIGNING_ALLOWED=NO build-for-testing` passed with exit 0, compiling the app and test bundle; no tests ran.
- `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer /usr/bin/xcodebuild -quiet -project dev-manager.xcodeproj -scheme dev-manager -configuration Release -destination 'generic/platform=macOS' -derivedDataPath /tmp/dev-manager-compile-check-release CODE_SIGNING_ALLOWED=NO build` passed with exit 0.
- No compiler warnings were emitted for the changed provisioning code. Release emitted only the Xcode environment warning that the macOS placeholder device lacked an operating-system version; it is not a source diagnostic.

No `test`/`test-without-building`, app launch, installer, runtime probe, or manual test execution was performed. These checks used temporary derived data only; normal user builds should continue using Xcode's default derived-data location.

## Focused provisioning absence hardening — pending VM validation

The runtime inspector now makes the missing-versus-failure decision from bounded fnm inventory output plus read-only facts for the selected fnm root: direct managed-version directories and the `aliases/default/bin/node` target. `* system` and external aliases are explicitly unmanaged, while missing roots and empty stores are known absence. The previous English stderr fragment matching is gone, so a fresh fnm install whose default command says that no default has been set remains neutral Node-missing state; malformed aliases, unreadable roots, process failures, timeouts, and failed managed candidates remain attention. A configured managed default remains authoritative, including unsupported or broken defaults, and is never silently replaced.

The production orchestration accepts narrow command/filesystem/executable closures internally for deterministic DEBUG tests; production still uses the existing command runner and no shell/profile execution. Focused route regressions exercise no fnm → fnm with no managed Node → managed Node without pnpm → managed Node with Homebrew pnpm 12.6.0, plus changed absence wording, real inventory failure, malformed alias, and unsupported configured default. These tests compile but were not executed under the current user authorization. Pending validation is the requested no-fnm → fnm-present/no-Node VM transition and the remaining real-root alias/permission cases.

## Current hardening follow-up

A readable fnm root with an empty store and absent default is authoritative normal absence: runtime inspection records the root and performs zero `fnm list`, `fnm default`, Node, or pnpm commands. An absent default with a real inventory may use `fnm list` for selection, but never probes `fnm default`; a known configured managed default skips the unnecessary inventory listing. Inventory facts now distinguish valid semver version stores from incomplete/malformed entries, dangling aliases, broken roots, and unreadable paths without creating roots or crawling profiles. Before any `fnm exec ... node`, inspection validates the normalized `node-versions/vVERSION/installation/bin/node` path, canonical store membership, and executable availability, preventing incomplete or external links from invoking ambient Node. These semantics are covered by injected command-spy source tests; they were compiled but not executed.
