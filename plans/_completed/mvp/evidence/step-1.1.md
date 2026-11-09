# Step 1.1 — Persist project folders and editable commands

## Implementation

- Added `dev-manager/Project.swift` with a Codable project record containing a stable UUID, standardized folder path, and one editable command. New projects default to `pnpm dev`; folder paths and commands are validated without Git checks or dependency installation.
- Added `dev-manager/ProjectStore.swift` using app-owned Codable JSON at `~/Library/Application Support/Dev Manager/projects.json`. Writes are atomic. Missing settings start empty; unreadable, corrupt, or unsupported settings are retained, shown as an error, and put the store in read-only mode rather than being silently replaced. Failed writes leave the in-memory project list unchanged and report the error.
- Replaced the starter view with a folder-picker-backed project list/detail UI in `dev-manager/ContentView.swift`. It supports registration, selection, command editing/saving, invalid-folder status, blank-command feedback, and destructive-style `Remove Project…` confirmation. The command editor uses an explicit `LabeledContent` label and a native single-line field with the existing custom rounded background/border; the field, `Save Command` button, and conditional `Saved` indication now share one row. The owner's explicit full-width `maxWidth: .infinity` preference supersedes the earlier 360pt choice; save/Return behavior and accessibility labeling are unchanged. The confusing in-place folder-switch control was removed; a missing registered folder is recovered by removing the entry and re-adding the correct folder. The app entry point initializes one store in `dev-manager/dev_managerApp.swift`.
- `ProjectStore.removeProject(id:)` removes by stable ID only after the atomic settings write succeeds. Save failure retains the in-memory entry and reports a recoverable error; unknown IDs are rejected without a write. The UI reconciles selection after successful removal, disables removal in read-only mode, and its confirmation explicitly says the disk folder/files are untouched. No command/process execution or Start/Stop controls were added. The app target's App Sandbox is now disabled under the approved Step 1.1 sequencing correction; no other app security setting was changed.
- The existing folder-based target membership includes the new app and test sources. The existing native test target was given the minimal app host/dependency wiring needed for focused tests; no new testing framework or harness was added.

## Automated verification

From `/Users/andy/Documents/Development/dev-manager`, with the global developer directory unchanged and fresh derived-data directories:

```sh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -quiet -project dev-manager.xcodeproj -scheme dev-manager -configuration Debug -destination 'generic/platform=macOS' -derivedDataPath /tmp/dev-manager-step1.1-final-build CODE_SIGNING_ALLOWED=NO build
```

Result: exit 0 / native unsigned Debug build succeeded.

```sh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -quiet -project dev-manager.xcodeproj -scheme dev-manager -configuration Debug -destination 'platform=macOS,arch=arm64' -derivedDataPath /tmp/dev-manager-step1.1-final-test CODE_SIGNING_ALLOWED=NO test
```

Result: exit 0 / all 8 focused Swift Testing tests passed. The tests cover stable-ID/settings round-trip, successful removal persistence with unchanged project folder/file bytes, failed removal retention, unknown-ID safety, missing/non-directory/blank validation, corrupt-settings preservation, isolated write-failure reporting, and native test-target wiring. Xcode emitted non-fatal app-intents/linkd diagnostics during the app-hosted test launch; the test result was successful. All temporary settings and folders were under disposable `/tmp` directories; the live app settings were not modified.

The command-row presentation adjustment was verified with fresh derived data using:

```sh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer /usr/bin/xcodebuild -quiet -project dev-manager.xcodeproj -scheme dev-manager -configuration Debug -destination 'generic/platform=macOS' -derivedDataPath /tmp/dev-manager-command-row-build CODE_SIGNING_ALLOWED=NO build
```

Result: exit 0 / native unsigned Debug build succeeded. No focused tests were repeated because this is a presentation-only change. This is compile evidence only; visual confirmation that the field, Save button, and Saved indication align as intended remains pending owner review.

## Configuration verification

`xcodebuild -showBuildSettings` reports app-target `ENABLE_APP_SANDBOX = NO`, `ENABLE_HARDENED_RUNTIME = YES`, `CODE_SIGN_STYLE = Automatic`, and `MACOSX_DEPLOYMENT_TARGET = 15.0`. The built executable reports Mach-O `minos 15.0`. The unsigned build has no provisioning profile/team signature or embedded entitlement artifact, so this is static/build-output configuration evidence, not signed runtime proof.

## Approved configuration correction

Static review found a sequencing conflict: this step stores folder paths only, while the existing sandbox can require persisted picker authorization to access those folders after relaunch. Its app-support location can also differ from the later non-sandboxed app's location. The owner approved moving the already-planned App Sandbox disablement from Step 1.2 into Step 1.1; the app target now uses `ENABLE_APP_SANDBOX = NO`. No security-scoped bookmark infrastructure, process runner, or other Step 1.2 work was added.

No live settings file existed at either the non-sandboxed app-support path or the expected sandbox container path when checked. No owner data was copied, deleted, migrated, or printed. If a prior sandboxed settings file appears later, surface it for owner direction rather than resetting or migrating it automatically. Full Step 1.1 verification remains pending owner UI validation.

## Manual verification status

Owner UI validation remains pending and is intentionally not claimed here. The owner should launch the built app from Xcode or Finder and:

1. Add a safe folder through the picker, confirm the default `pnpm dev`, edit/save the command, quit, and relaunch. Confirm folder/command/identity are retained and no command runs during add, save, or restore.
2. Enter a blank command and confirm the visible validation/disabled save feedback; delete or rename a registered folder and confirm the invalid-folder message. Recover by removing the saved entry and re-adding the correct folder; a non-directory input is covered by the isolated automated validator because the picker accepts folders only.
3. Confirm the command row uses the available width with the field leading-aligned and `Save Command`/`Saved` beside it (and remains usable at a smaller window width), then cancel `Remove Project…` and verify no entry/selection/disk change, then confirm removal and verify the folder/files remain unchanged. Confirm a failed save leaves the entry/selection visible with a recoverable error if an owner-approved isolated setup is used.
4. Confirm the visible settings error path using an owner-approved isolated copy if desired; do not corrupt the live settings file.

Step 1.1 implementation tasks are checked in `plans/mvp/plan.md`; the Step 1.1 verification/completion task remains unchecked until this owner UI walkthrough—including confirmation of the final command-editor alignment—is observed. The automated tests and source inspection do not substitute for the owner's Cancel/remove, relaunch, blank-command, and disk-preservation checks. Step 1.2 and all process execution work are intentionally deferred.

## Approved source organization refactor

The owner approved the proposed structure with “This seems good to me” and explicitly requested `dev_managerApp.swift` be renamed to the exact filename `devManagerApp.swift`. The current source map is:

- `dev-manager/App/devManagerApp.swift`
- `dev-manager/App/ContentView.swift`
- `dev-manager/Projects/Project.swift`
- `dev-manager/Projects/ProjectStore.swift`
- `dev-manager/Projects/Views/ProjectSidebar.swift`
- `dev-manager/Projects/Views/ProjectDetailView.swift`
- `dev-manager/Projects/Views/CommandEditor.swift`
- `dev-manager/Assets.xcassets/` (unchanged root asset catalog)
- `dev-managerTests/ScaffoldSmokeTests.swift`
- `dev-managerTests/Projects/ProjectStoreTests.swift`

Responsibilities remain split without new generic abstractions: `ContentView` owns split-view composition and selection/folder-picker coordination; `ProjectSidebar` owns the list/row/Add action; `ProjectDetailView` owns project information, section composition, and removal confirmation; `CommandEditor` owns its local draft, full-width leading field, validation, and save action. The model/store semantics, single app-lifetime store, selection behavior, Save/Saved row, Return save, blank feedback, persistence/error handling, and removal behavior were preserved. No process state or Phase 1.2 work was added.

The existing folder-based app/test target membership required no explicit project-file reference change. The native build compiled all moved app files and the moved `ProjectStoreTests.swift` from their new paths; no stale root source files, duplicate `@main`, or duplicate tests remain.

## Refactor verification

Native unsigned build with fresh derived data:

```sh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer /usr/bin/xcodebuild -quiet -project dev-manager.xcodeproj -scheme dev-manager -configuration Debug -destination 'generic/platform=macOS' -derivedDataPath /tmp/dev-manager-refactor-build CODE_SIGNING_ALLOWED=NO build
```

Result: exit 0 / build succeeded.

Existing focused native tests with fresh derived data:

```sh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer /usr/bin/xcodebuild -project dev-manager.xcodeproj -scheme dev-manager -configuration Debug -destination 'platform=macOS,arch=arm64' -derivedDataPath /tmp/dev-manager-refactor-test CODE_SIGNING_ALLOWED=NO test
```

Result: exit 0 / all 8 existing Swift Testing tests passed. Xcode emitted only the known non-fatal app-intents/linkd diagnostics during the app-hosted test launch. No custom harness, UI automation, process listener, or runtime command test was used. Owner manual UI walkthrough remains pending and is not claimed here.
