# Step 2.3 — Open the correct local site

## Approved layout implementation

- `dev-manager/Projects/Views/ProjectDetailView.swift` owns the `Execution` and `Output` section boundaries. Site status and browser actions are grouped in `Execution`; terminal output remains its own `Output` section.
- `dev-manager/Discovery/Views/SiteStatusView.swift` is row content rather than a nested `Local Site` section. Ready now reuses the running-row system-image indicator sizing/spacing, keeps the green label, places the caption URL inline with middle truncation/help, and retains the right-aligned blue browser control and multisite URL menu. Existing discovering, no-site, diagnostic, opening, and browser-error states remain represented.
- `dev-manager/Projects/Views/ProjectOutputView.swift` preserves the existing waiting placeholder, bounded scroll area, monospace selectable logs, truncation notice, cleanup error, and visibility while active/after Stop.

## Verification

- Owner-approved compile-only check (no app/browser launch, tests, hosted tests, listeners, or HTTP requests):
  `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -quiet -project dev-manager.xcodeproj -scheme dev-manager -configuration Debug -destination 'generic/platform=macOS' -derivedDataPath /tmp/dev-manager-layout-build CODE_SIGNING_ALLOWED=NO build`
- Result: succeeded (exit status 0); Xcode emitted only the generic macOS placeholder-destination diagnostic.
- Follow-up styling build succeeded (exit status 0); visual validation remains pending for grouping, narrow-window truncation, and multisite menu behavior. No Step 2.3 scenarios or G2 status passes are newly claimed.
