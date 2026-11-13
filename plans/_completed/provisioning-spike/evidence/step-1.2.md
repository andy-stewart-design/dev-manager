# Step 1.2 evidence

Status: implementation tasks and the user-owned Step 1.2 manual verification are complete; the Phase 1 gate is confirmed from the combined 1.1/1.2 evidence. No Homebrew download, Installer launch, build, test, or VM action was run by the agent.

## Implemented

- Added a DEBUG-only Homebrew action requiring completed detection, supported Apple Silicon/macOS 15+/logged-in-admin gating, verified developer tools, explicit consent, and no concurrent check/installer action.
- Queries GitHub's latest Homebrew release API with JSON and User-Agent headers, selects the exact `Homebrew.pkg` asset, validates its HTTPS `github.com/Homebrew/brew/releases/download/` browser URL, downloads through URLSession to a writable app temporary `.pkg` path, requires a final HTTPS response (including normal GitHub CDN redirects), and rejects HTTP failures or empty files. No custom CDN allowlist or package trust framework was added.
- Opens the local package through `NSWorkspace`/Launch Services and relies on macOS Installer's normal signature, Gatekeeper, authorization, and ownership/security decisions. No sudo, password, privileged helper, shell edit, command-line installer, override plist, quarantine bypass, or re-signing was added; source review does not substitute for the pending manual Installer observation.
- Uses a waiting state after handoff and never marks Homebrew ready because a package was downloaded or opened. `/opt/homebrew/bin/brew --version` run as the current user is the only successful Homebrew check; failures remain diagnostic attention states.
- Requires **Check again** after a handoff or failed attempt before retrying. A completed check re-arms the Homebrew action only when detection is actually `.missing`; existing but unusable/conflicting Homebrew remains `.attention` and cannot be automatically replaced or repaired. A newly opened setup screen runs detection again and does not relaunch an external installer automatically. The existing 8-second command-check timeout remains separate from the package URLSession timeouts.
- `ProvisioningView.swift` presents consent, waiting, error, and manual recheck messaging. No production runner or unrelated scheme configuration was changed.

## Source-only verification

- Inspected the changed model/view and confirmed the Homebrew flow is inside the existing `#if DEBUG` boundary, gates handoff on a completed `.missing` check, remains blocked while checking/downloading, uses only the official API/release prefix plus final-response HTTPS validation, and has no privileged installer path or automatic retry.
- Ran `git diff --check` successfully after the Step 1.2 edits.
- Per the user's explicit no-build instruction, no `xcodebuild`, build, test, installer, provisioning, download, or app-launch command was run by the agent. Prior host build evidence remains in `step-1.1.md`; the user builds in Xcode and transfers Derived Data.

## User-owned manual verification

The user built and launched the current Debug artifact in Xcode and transferred it through the Tart shared folder. This is user-reported manual execution, not an agent-run planned CLI build; no `xcodebuild` result is claimed here.

### Screenshot-observed state

The supplied screenshot (`/Users/andy/Library/Application Support/CleanShot/media/media_Skbfb7ileB/CleanShot 2026-11-11 at 7.14.28 AM@2x.png`) shows Apple developer tools ready and Homebrew `7.0.13`; it also shows `/opt/homebrew/bin/brew` ran as the current user. This records the visible state in that screenshot only and does not by itself establish the relaunch sequence.

### User-reported relaunch observation

The user subsequently explicitly confirmed that quitting and reopening the app recognized Homebrew without requesting another download. This supplies the relaunch/reuse observation required by AC4; no duplicate Homebrew handoff was reported.

Together with Step 1.1's separately recorded user confirmation of real installer cancellation/retry, these observations satisfy the Step 1.2 verification task and the Phase 1 composition gate for the reported human-built/launched walkthrough. The user did not report Terminal use or an app-entered password. Installer authorization behavior beyond the supplied evidence remains unrecorded, and Step 1.1's environment-metadata caveat remains applicable.
