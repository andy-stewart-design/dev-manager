# Step 0.1 — Scaffold handoff and baseline

- Inspected the owner's SwiftUI scaffold without modifying app source or Xcode configuration. `APP = dev-manager/`; entry point `dev-manager/dev_managerApp.swift`; root view `dev-manager/ContentView.swift`; `PROJECT = dev-manager.xcodeproj` (definition `dev-manager.xcodeproj/project.xcproj`). `TESTS` is absent: the project has only the `dev-manager` app target. No applicable project/ancestor instructions were found.
- Confirmed macOS 26.6.2 and Xcode 27.2 (27B52). The active command-line developer directory points to `/Library/Developer/CommandLineTools`, so unqualified `xcodebuild -version` fails; scoped `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer` works without changing global selection.
- From the project root, `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer /usr/bin/xcodebuild -project dev-manager.xcodeproj -list` succeeded and listed app target/scheme `dev-manager`, configurations Debug/Release, and no test target.
- Static settings: app deployment target 15.0, project-level deployment default 26.6, App Sandbox enabled, hardened runtime enabled, automatic signing with an owner-supplied team. Signing credentials/provisioning were not exercised. The future test target must explicitly use 15.0 or inherit an owner-corrected project default.

## Build check

From `/Users/andy/Documents/Development/dev-manager`, ran:

```sh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer /usr/bin/xcodebuild -quiet -project dev-manager.xcodeproj -scheme dev-manager -configuration Debug -destination 'generic/platform=macOS' -derivedDataPath /tmp/dev-manager-phase0.Pc6byp CODE_SIGNING_ALLOWED=NO build
```

The unsigned Debug build returned exit code 0. Xcode emitted generic-destination/platform metadata warnings; this establishes compilation only, not signing validity, successful launch, tests, macOS 15 runtime compatibility, or process-management behavior. No app was launched and no tests were run.

## G0 prerequisites remaining

- Owner: add the planned native macOS unit-test target through Xcode, use deployment target 15.0, and make it available to the app scheme's Test action; no UI tests are needed. Build/Run, close/reopen, and native Test baseline still need validation after that addition.
- Coordinate representative safe projects, shell/version-manager environment, and listener prerequisites with the owner before live dev-command validation. No development processes or test listeners have been started.
- At the scaffold handoff, App Sandbox was enabled; the owner-approved minimal change was subsequently moved into Step 1.1 and is recorded in `changes.md`. No signing or unrelated entitlement change was made during handoff.
- G0 is not satisfied: missing native test target and unobserved launch/test behavior keep Step 0.1's verification task unchecked. No feature implementation has begun.

## Follow-up: explicit technical scaffold completion

- Acting on the current request to finish the technical portion of 0.1, added the missing native macOS Swift Testing target within the existing scaffold rather than regenerating the project: `TESTS = dev-managerTests/`, source `dev-managerTests/ScaffoldSmokeTests.swift`, target `dev-managerTests`, and shared scheme `dev-manager.xcodeproj/xcshareddata/xcschemes/dev-manager.xcscheme` with the test action wired to that target. The source contains one honest scaffold smoke test only; no feature behavior, dependencies, UI tests, harness, or development server was added.
- Set the project default, app target, and test target `MACOSX_DEPLOYMENT_TARGET` values to `15.0`. The owner-supplied development team/signing style and hardened-runtime settings were retained; App Sandbox was enabled at this earlier baseline and was later disabled in the app target under the approved Step 1.1 correction. Test-target inspection reports `com.apple.product-type.bundle.unit-test`; `otool` reports `minos 15.0` for both the built app executable and test bundle.
- Final native build, using fresh derived data:

```sh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer /usr/bin/xcodebuild -quiet -project dev-manager.xcodeproj -scheme dev-manager -configuration Debug -destination 'generic/platform=macOS' -derivedDataPath /tmp/dev-manager-phase0-step01-build CODE_SIGNING_ALLOWED=NO build
```

  Result: exit 0 / build succeeded. This is an unsigned build; no provisioning or account changes were attempted.
- Final native test, using fresh derived data and the actual arm64 macOS destination:

```sh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer /usr/bin/xcodebuild -project dev-manager.xcodeproj -scheme dev-manager -configuration Debug -destination 'platform=macOS,arch=arm64' -derivedDataPath /tmp/dev-manager-phase0-step01-test CODE_SIGNING_ALLOWED=NO test
```

  Result: exit 0 / `ScaffoldSmokeTests` ran 1 test and passed. Xcode emitted a non-fatal `IDELaunchSession` diagnostic warning; the test result was successful.
- Baseline launch check used the built unsigned app without development commands or listeners: `open -n -g /tmp/dev-manager-phase0-step01-test/Build/Products/Debug/dev-manager.app`; after three seconds `ps` observed the launched executable, and only that `/private/tmp/.../dev-manager` PID was terminated with `kill -TERM`. No window was programmatically inspected; no Accessibility/control permission was requested. A visual Xcode Product > Run and close/reopen check remains owner-side.
- Static environment inspection found zsh setup with `/Users/andy/.zprofile` loading Homebrew and `.zshrc` evaluating `fnm env --use-on-cd --shell zsh`. Homebrew `fnm`, `node`, `npm`, and `pnpm` plus fnm-managed Node 22/24 installations are present. This identifies initial tool/environment seams but does not prove account login-shell selection, runtime versions, or Finder-launched tool resolution; no startup files were sourced or modified.
## Owner confirmation and G0 conclusion

- Owner reported, “project runs fine,” confirming starter launch from Xcode. Combined with the native build/test results and verified 15.0 deployment settings above, this satisfies the corrected scaffold gate; Step 0.1 verification and G0 are complete. This is not proof of macOS 15 runtime behavior, Finder toolchain inheritance, or development-process functionality.
- Owner correctly questioned the need for upfront Vite/Next repository paths: users will add projects through the app. Those paths and approved live-server scenarios are later manual-validation inputs, not scaffold blockers. Window/process lifetime remains an explicit Step 1.3 check; close/reopen was not separately observed here and is not claimed.
- The earlier plan intentionally left App Sandbox enabled until Step 1.2. The owner subsequently approved moving that already-planned change into Step 1.1; it is now recorded and implemented there. No Phase 1.2 process-execution work has begun. See `changes.md` for the narrow sequencing correction.
