# Step 1.1 evidence

Status: Step 1.1 manual gate confirmed by the user; Step 1.2 is now the active pending step. The baseline-detail caveat below remains open.

## Implemented

- Added a DEBUG-only Setup toolbar button and sheet.
- Added read-only checks for selected Apple developer tools, Homebrew, fnm, and the pinned runtime.
- Historical initial choice (superseded): Node `22.14.0` with pnpm `10.6.2` (compatible Node 22/pnpm 10 pair).
- Runtime pin follow-up: the active exact pair is now Node `24.22.2` with pnpm `12.18.0`. External verification selected Node 24.22.2 as a supported Maintenance LTS release (Krypton, support through 2028-04-30, with a darwin-arm64 distribution) and pnpm 12.18.0 as the compatible current stable release. The runtime check still requires this exact Node/pnpm pair; it does not treat generic Node installation, or the user's current Node `24.21.0`, as satisfying the pin.
- Official references: [Node latest v24.x](https://nodejs.org/dist/latest-v24.x/), [Node v24.22.2 archive](https://nodejs.org/en/download/archive/v24.22.2), [Node release schedule](https://raw.githubusercontent.com/nodejs/Release/main/schedule.json), [pnpm latest](https://registry.npmjs.org/pnpm/latest), [pnpm 12.18.0 metadata and engines](https://registry.npmjs.org/pnpm/12.18.0), [pnpm installation](https://pnpm.io/installation), and [pnpm latest release](https://github.com/pnpm/pnpm/releases/latest).
- Focused review fixes: the request button is unavailable until an initial completed check, and remains unavailable after Apple's request returns until a manual Check again. Direct checks use null stdin and an 8-second timeout; failures, timeouts, and unusable binaries report attention diagnostics.
- Runtime inspection first runs read-only `fnm list` and does not invoke `fnm exec` for an absent Node version. Version probes disable Corepack network/project auto-resolution and fnm Corepack enablement; pnpm is resolved before its version command, so missing pnpm is not treated as a successful Corepack download.
- Follow-up: replaced the combined `Spike fixture runtime` row with visible `Node 24.22.2` and `pnpm 12.18.0` rows. One runtime inspection now returns both results; pnpm remains independently visible and is only validated inside the pinned fnm Node context. When Node/fnm is unavailable or unusable, pnpm reports that it is not yet verified in that required context rather than claiming it is missing.
- Added narrow Apple Silicon/macOS 15+/logged-in-admin gating for machine-changing actions. The host is arm64, macOS `26.6.2`, and the current user is in the `admin` group; this is host evidence only, not VM acceptance.
- Added explicit consent before invoking `/usr/bin/xcode-select --install`. Process return is reported only as request submission; it never marks tools ready. The user must complete/cancel Apple's UI and press Check again.
- Read-only host inspection used the installed fnm help/list commands. No installer, provisioning, shell-file, password, sudo, or global runner changes were performed on the host.
- UI state refinement: added an explicit `.unverified(String)` state. Missing/unusable fnm or pinned Node now leaves dependent Node/pnpm checks neutral while preserving real Node/fnm attention and missing states; pnpm-specific failures remain attention. The unverified row uses a muted dashed-circle-and-question-mark indicator with an accessibility label.

## Manual 1.1 confirmation

The user reports that both representative Command Line Tools checks passed in a fresh Tart clone:

- Cancellation: the Apple installer dialog was canceled, then **Check again** still showed developer tools missing; setup did not advance.
- Retry: the Apple installer flow completed, then **Check again** showed the developer tools ready; readiness came from the functional recheck, not request submission.

The supplied screenshot (`/Users/andy/Library/Application Support/CleanShot/media/media_zfBBJrlmc/CleanShot 2026-11-11 at 6.54.48 AM@2x.png`) independently shows the ready state with selected tools at `/Library/Developer/CommandLineTools` and the `clang` path, while Homebrew is missing. It does not document the cancellation sequence. The screenshot predates the neutral-icon update; the user separately checked the updated neutral icons and reported that they look good.

The user also confirmed that the latest 1.1 code was built and launched for this walkthrough. This is user-reported confirmation, not an agent-run build; prior host build records below are preserved and are not replaced by it.

## Follow-up verification

Source inspection only for this follow-up: the check IDs, row titles, paired runtime result, required Node-context wording, read-only fnm inventory check, Corepack no-network environment, neutral downstream state mapping, and status indicator/accessibility label were reviewed. `git diff --check` completed successfully. Per the user's instruction, no build, test, or `xcodebuild` command was run for this change.

The host build records below are historical evidence from before this follow-up; they do not validate the current source. The user must build in Xcode and retrieve the resulting Derived Data for manual checking.

## Host checks

Command run from the repository root:

```sh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
/usr/bin/xcodebuild -quiet -project dev-manager.xcodeproj \
-scheme dev-manager -configuration Debug \
-destination 'generic/platform=macOS' \
-derivedDataPath /tmp/dev-manager-provisioning-debug \
CODE_SIGNING_ALLOWED=NO build
```

Outcome: exit 0. Xcode emitted its existing generic-macOS placeholder warning. Artifact:
`/tmp/dev-manager-provisioning-debug/Build/Products/Debug/Dev Manager.app`

The planned Debug build was rerun after the focused review fixes and again exited 0 with the same artifact path.

After the runtime pin follow-up to Node `24.22.2` and pnpm `12.18.0`, the same Debug build command exited 0. Xcode emitted the existing generic-macOS placeholder warning. Artifact:
`/tmp/dev-manager-provisioning-debug/Build/Products/Debug/Dev Manager.app`

Source inspection: `ProvisioningModel.swift`, `ProvisioningView.swift`, and the setup state/button in `ContentView.swift` are guarded by `#if DEBUG`; no Release configuration or existing runner source was changed.

## Remaining 1.1 caveat

The user described the source VM as a fresh Tart clone and confirmed launchability, but this note does not independently restate its macOS version, Apple Silicon architecture, administrator status, or snapshot details. Preserve that caveat for the broader evidence review; it does not invalidate the specifically reported cancellation/retry result.

No further 1.1 user build or manual gate is requested here. The VM is human-controlled and was not accessed by this run. The user must build the Step 1.2 source in Xcode, retrieve the current Debug artifact from Derived Data, and then record these observations for Step 1.2:

1. Build the Step 1.2 source in Xcode and transfer the resulting Debug artifact from Derived Data to the VM.
2. Confirm the supported Apple Silicon administrator environment, then open Setup and verify that Homebrew remains missing until the package handoff is completed.
3. Give consent to download the exact official `Homebrew.pkg`, observe the normal macOS Installer handoff, and confirm the app shows waiting rather than Homebrew ready.
4. Complete or cancel Installer, press Check again, and record whether `/opt/homebrew/bin/brew --version` succeeds as the current user. Any failure remains an error/attention state.
5. Quit and reopen the app, press Check again, and confirm actual developer-tool/Homebrew state is reused without an automatic duplicate installer request. Record any failed or unrun item as pending.
