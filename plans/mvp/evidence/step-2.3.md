# Step 2.3 — Open the correct local site

## Approved layout implementation

- `dev-manager/Projects/Views/ProjectDetailView.swift` owns the `Execution` and `Output` section boundaries. Site status and browser actions are grouped in `Execution`; terminal output remains its own `Output` section, which is now always rendered for a selected project.
- The execution and website rows share a 32-point minimum matching the regular bordered button while retaining natural growth for wrapping diagnostics; Ready therefore does not shift the row when its browser control appears.
- `dev-manager/Discovery/Views/SiteStatusView.swift` remains row content rather than a nested `Local Site` section. Ready keeps the green label, inline caption URL, right-aligned blue browser control, and multisite URL menu. Existing discovering, no-site, diagnostic, opening, and browser-error states remain represented.
- `dev-manager/Projects/Views/ProjectOutputView.swift` accepts an optional run state. It shows `No output yet.` before a run or after an empty stopped run, and `Waiting for output…` for an active empty run, while preserving the bounded scroll area, monospace selectable logs, truncation notice, cleanup error, and retained output after Stop.

## Verification

- Owner-approved compile-only check (no app/browser launch, tests, hosted tests, listeners, or HTTP requests):
  `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -quiet -project dev-manager.xcodeproj -scheme dev-manager -configuration Debug -destination 'generic/platform=macOS' -derivedDataPath /tmp/dev-manager-layout-build CODE_SIGNING_ALLOWED=NO build`
- Result: succeeded (exit status 0); Xcode emitted only the generic macOS placeholder-destination diagnostic.
- Follow-up styling build succeeded (exit status 0); visual validation remains pending for grouping, narrow-window truncation, multisite menu behavior, the initial empty Output placeholder, and Ready-row stability. No Step 2.3 scenarios or G2 status passes are newly claimed.

- Layout follow-up build result: succeeded (exit status 0); Xcode emitted only the generic macOS placeholder-destination diagnostic. Manual owner UI review remains pending; the requested checks are start-empty, Start-before-Ready row stability, and Stop with logs retained.

## Per-project settings sheet layout follow-up

- Scoped build (no app/browser launch, tests, hosted tests, listeners, HTTP requests, dependencies, or runtime commands):
  `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -quiet -project dev-manager.xcodeproj -scheme dev-manager -configuration Debug -destination 'generic/platform=macOS' -derivedDataPath /tmp/dev-manager-project-settings-build CODE_SIGNING_ALLOWED=NO build`
- Result: succeeded (exit status 0); Xcode emitted only the generic macOS placeholder-destination diagnostic.
- Manual validation is pending: open the per-project gear and inspect the read-only name/folder; confirm Name and Folder values share a leading column; click an existing Folder path and verify Finder selects that folder in its parent; confirm a missing folder disables the action with an explanation; edit then Cancel and confirm unchanged; edit then Save and reopen; verify a running server is unaffected; exercise the footer Remove confirmation Cancel versus confirm and the active-Remove block. No automated UX harness was added and no manual result is claimed.

## Approved settings-sheet UI follow-up

- Implemented only the three approved settings-sheet updates: explicit shared leading alignment for read-only Name/Folder rows; a disabled-when-missing monospaced Folder button that calls `NSWorkspace.shared.activateFileViewerSelecting([folderURL])`; and a footer with left-side destructive Remove plus right-side Cancel/Save.
- The existing app-entry-only confirmation, fresh `runner.canRemove` guard, command staging, and store/remove error retention were preserved. No folder mutation, renaming, process, discovery, or browser behavior was changed.
- Scoped compile-only build rerun after a small ShapeStyle inference fix: succeeded (exit status 0); Xcode emitted only the generic macOS placeholder-destination diagnostic. Manual visual layout and Finder-selection validation remain pending; no runtime action or test result is claimed.

## Sidebar execution-status indicators

- Implemented the requested shared status simplification: `circle.fill` only for `.running`, hollow `circle` otherwise; Execution keeps its existing phase colors, while the sidebar process icon uses an explicit white override. Phase titles, tooltips, accessibility labels, and the separate trailing orange folder warning remain intact.
- Scoped compile-only build succeeded with the approved command below (no app launch, tests, browser/Finder action, listeners, HTTP, dependencies, or runtime behavior was exercised). Manual UI validation remains pending.

`DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -quiet -project dev-manager.xcodeproj -scheme dev-manager -configuration Debug -destination 'generic/platform=macOS' -derivedDataPath /tmp/dev-manager-layout-build CODE_SIGNING_ALLOWED=NO build`
