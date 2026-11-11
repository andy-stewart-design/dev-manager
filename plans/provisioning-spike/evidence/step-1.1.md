# Step 1.1 evidence

Status: source follow-up recorded; Step 1.1 is not complete. User-build and manual VM gates remain pending.

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

## Follow-up verification

Source inspection only for this follow-up: the check IDs, row titles, paired runtime result, required Node-context wording, read-only fnm inventory check, Corepack no-network environment, neutral downstream state mapping, and status indicator/accessibility label were reviewed. `git diff --check` completed successfully. Per the user's instruction, no build, test, or `xcodebuild` command was run for this change; the latest source has not been VM-verified.

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

## Pending user build and manual VM gate

The VM is human-controlled and was not accessed by this run. The user must build the current source in Xcode, retrieve the current Debug artifact from Derived Data, and then record these observations. Do not mark the verification task complete until they are recorded:

1. Capture the clean VM/app baseline and confirm the supported Apple Silicon administrator environment.
2. Launch the current Debug artifact, open Setup, and capture separate visible `Node 24.22.2` and `pnpm 12.18.0` rows even when the pinned runtime is unavailable. The pnpm detail should say it is not yet verified in the required Node context, not that pnpm is independently missing.
3. Give consent to request Command Line Tools, cancel Apple's dialog, press Check again, and capture that developer tools remain missing/unusable and no dependent installation is presented.
4. Retry, accept Apple's graphical install/license flow, then press Check again. Capture the status showing functional developer-tool checks (not merely request/process return), plus the independent Node/pnpm statuses.
5. Include a screenshot or equivalent status capture showing the cancellation/retry and final functional Check-again results. Any failed or unrun manual item remains pending; no installer success is inferred from this host build.
