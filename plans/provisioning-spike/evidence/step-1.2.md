# Step 1.2 evidence

Status: implementation tasks are complete; Step 1.2 verification and the Phase 1 gate remain pending. No Homebrew download, Installer launch, build, test, or VM action was run by the agent.

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

## Pending user verification

The user should build the current Debug source in Xcode, transfer the resulting Derived Data app to the fresh supported VM, and manually:

1. Confirm developer tools are ready, then open Setup and use the explicit Homebrew consent action.
2. Observe the official `Homebrew.pkg` download and normal macOS Installer handoff. Confirm the app remains waiting and does not claim Homebrew is ready merely because Installer opened.
3. Complete or cancel the Installer UI, return to the app, and press **Check again**. Only a successful current-user `/opt/homebrew/bin/brew --version` check may show Homebrew ready; cancellation, network/API/package errors, or a missing/unusable brew must remain incomplete with diagnostics.
4. Quit and reopen the app, open Setup, and press **Check again**. Confirm developer tools and Homebrew are reconstructed from actual machine state, with no duplicate installer request. If retrying after an incomplete attempt, perform the manual check first.
5. Record the console user/normal Installer authorization behavior and any relevant diagnostics without using Terminal or app-entered credentials.

The Step 1.2 verification task and Phase 1 exit gate remain unchecked until those user-owned VM observations are recorded. The Step 1.1 cancellation/retry result is recorded separately in `step-1.1.md`; it is not being used as Homebrew installation evidence.
