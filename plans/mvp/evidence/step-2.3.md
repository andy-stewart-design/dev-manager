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

## Per-project settings sheet layout follow-up

- Scoped build (no app/browser launch, tests, hosted tests, listeners, HTTP requests, dependencies, or runtime commands):
  `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -quiet -project dev-manager.xcodeproj -scheme dev-manager -configuration Debug -destination 'generic/platform=macOS' -derivedDataPath /tmp/dev-manager-project-settings-build CODE_SIGNING_ALLOWED=NO build`
- Result: succeeded (exit status 0); Xcode emitted only the generic macOS placeholder-destination diagnostic.
- Manual validation is pending: open the per-project gear and inspect the read-only name/folder; confirm Name and Folder values share a leading column; click an existing Folder path and verify Finder selects that folder in its parent; confirm a missing folder disables the action with an explanation; edit then Cancel and confirm unchanged; edit then Save and reopen; verify a running server is unaffected; exercise the footer Remove confirmation Cancel versus confirm and the active-Remove block. No automated UX harness was added and no manual result is claimed.

## Approved settings-sheet UI follow-up

- Implemented only the three approved settings-sheet updates: explicit shared leading alignment for read-only Name/Folder rows; a disabled-when-missing monospaced Folder button that calls `NSWorkspace.shared.activateFileViewerSelecting([folderURL])`; and a footer with left-side destructive Remove plus right-side Cancel/Save.
- The existing app-entry-only confirmation, fresh `runner.canRemove` guard, command staging, and store/remove error retention were preserved. No folder mutation, renaming, process, discovery, or browser behavior was changed.
- Scoped compile-only build rerun after a small ShapeStyle inference fix: succeeded (exit status 0); Xcode emitted only the generic macOS placeholder-destination diagnostic. Manual visual layout and Finder-selection validation remain pending; no runtime action or test result is claimed.
