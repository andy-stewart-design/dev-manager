# Step 2.3 — Open the correct local site

## Implementation completed

- `dev-manager/Discovery/Views/SiteStatusView.swift` now shows one URL-labeled `Open in Browser` action for one ready local site and a URL-labeled menu for multiple sites; no arbitrary primary is selected.
- `dev-manager/Projects/Views/ProjectDetailView.swift` passes website actions through `ProjectRunner` while preserving the existing command editor, lifecycle controls, logs, and local-only status layout.
- `dev-manager/Runs/ProjectRunner.swift`, `ProcessSupervisor.swift`, and `RunState.swift` add a narrow per-project opening state/error surface and final current-run checks before `NSWorkspace.shared.open`.
- `dev-manager/Discovery/SiteDiscovery.swift` adds fresh, read-only owned-listener/full-identity validation for the exact ready candidate. It does not issue a new HTTP probe or follow redirects. Stop/exit/run identity changes prevent opening; browser-open failure is visible without changing process state.

## Verification

- Build command (owner-specified, no app launch):
  `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -quiet -project dev-manager.xcodeproj -scheme dev-manager -configuration Debug -destination 'generic/platform=macOS' -derivedDataPath /tmp/dev-manager-2.3-build CODE_SIGNING_ALLOWED=NO build`
- Result: succeeded (exit status 0). Xcode emitted only its generic macOS placeholder destination diagnostic.
- Owner accepted the core browser workflow: after the requested Vite/Next/Astro opening, delayed readiness, occupied-port, and Stop-action walkthrough, the owner replied, “Yep, that seems to be working great.” Recorded as positive owner acceptance of that handoff, not as scenario-by-scenario diagnostic results. No additional live multi-site, trusted-HTTPS, no-site/404, silent-server fallback, or Stop-during-opening observations were separately reported. Those cases remain unverified; no installs or trust changes were made.
- UI automation, hosted tests, native tests, app/browser launches, listeners, and HTTP requests were not run.

The core owner walkthrough is accepted. The full Step 2.3 completion gate and G2 remain unchecked for the additional cases not reported above; no unperformed checks are marked passed.