# Provisioning alpha notes

## User-approved alpha #1 — PART A

This pass relaxes DEBUG provisioning readiness for Node and pnpm from one exact pair to the small app support snapshot: stable Node majors 22, 24, and 26, with pnpm majors 10, 11, and 12 after a successful probe in the selected Node context. Node 24.21.0 with pnpm 12.6.0 is accepted. These are supported major families, not exact patch requirements, pnpm LTS claims, or automatic security-upgrade promises.

The policy is centralized in `ProvisioningRuntimePolicy`. Its snapshot is grounded in the official Node release schedule ([previous releases](https://nodejs.org/en/about/previous-releases), [release schedule](https://github.com/nodejs/Release#release-schedule)) and pnpm's installation compatibility table ([pnpm installation](https://pnpm.io/installation)). The policy keeps Node 24.22.2 and pnpm 12.18.0 as recommended installation targets only when the corresponding tool is actually missing.

## Runtime boundary

The read-only inspector checks GUI-safe inherited PATH/standard executable locations and a local fnm inventory without sourcing profiles, enabling Corepack networking, or installing anything. It prefers a working fnm default/context, otherwise retains a usable GUI Node context and reports pnpm independently. Inventory and PATH executable candidates are stable/local and bounded to eight before direct probes, with an aggregate runtime inspection budget of about 20 seconds and an eight-second maximum per probe. The model applies the concrete context atomically and clears stale context on a failed refresh. The context records actual Node/pnpm versions and paths plus fnm selector/path when managed.

Existing unsupported, prerelease, or unusable tools remain attention states; no automatic replacement, upgrade, default switch, project metadata parsing, runner fallback, or project execution change is introduced. The fixture remains DEBUG-only but records its selected concrete versions, absolute paths, fnm selector, and command in owned fixture metadata; existing fixture conflicts still refuse changes. Optional shell configuration receives the detected managed selector and is exposed with the core setup in PART B. Fresh-shell verification accepts any supported working pair and reports actual values.

## Focused source-review fixes

Stable fnm selectors are support-checked before prerelease normalization, and inventory RCs are not selected. Runtime inspection now has a local aggregate deadline of about 20 seconds, passes each probe a remaining timeout capped at eight seconds, stops with attention when exhausted, and caps inherited PATH scanning before filesystem checks. Unmanaged fixture handoff uses `/usr/bin/env` with safely quoted selected Node/pnpm parent directories plus a fixed system PATH; the managed fnm command is unchanged. Fixture package and runtime JSON are encoder-generated so quoted or backslash-containing paths and selectors remain valid.

This pass does not implement repo-aware provider metadata/version selection. The repo-aware execution plan's provider boundary, exact-version coexistence, and npm-global isolation remain future work. Known limitations are that the current shell setup helper still owns only its existing marked `~/.zshrc` block and does not configure unmanaged Node contexts, while existing custom commands remain shell-controlled and are not rewritten or given a runner fallback here. When a supported unmanaged Node/pnpm pair is already usable, fnm is explicitly optional: the UI reports that state without claiming an absent fnm binary is installed, and does not offer fnm installation or managed-shell setup for that context. A fresh machine with missing Node still requires fnm as the installation backend.

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
