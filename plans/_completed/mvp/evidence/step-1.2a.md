# Step 1.2a evidence

## Implementation handoff

Owner-approved bounded refactor (`ok lets do 1.2a`) is recorded as a source-organization handoff only. `ProjectRunner` remains the main-actor observable UI/control facade and preserves its public state, start/stop, termination, and authoritative ownership checks. `ProcessSupervisor` now owns active-run lifecycle, launch cancellation/identity, waits, cleanup, and run-ID guarded callbacks while continuing to use the existing `ProcessLauncher` and detached blocking OS work. `RunOutputAccumulator` in `LogBuffer.swift` owns partial UTF-8/progress/CR assembly and bounded incomplete-line handling; `OutputReader`/`OutputInbox` and `LogBuffer` remain the existing bounded delivery/storage path.

No app launch, hosted tests, dev process/listener, manual smoke test, dependency/settings/credential change, or commit was performed. User-reported latest Start/Stop, immediate Stop, and Quit behavior was working before this approved handoff; those remain pending owner verification after the refactor and are not claimed as tested here.

## Checks performed

- Static source review: single lifecycle owner is `ProcessSupervisor`; UI state projection remains in `ProjectRunner`; no AsyncStream or second store was introduced. Callback captures use weak references where lifecycle callbacks retain the supervisor/facade.
- Build: passed: `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer /usr/bin/xcodebuild -quiet -project dev-manager.xcodeproj -scheme dev-manager -configuration Debug -destination 'generic/platform=macOS' -derivedDataPath /tmp/dev-manager-1.2a-build CODE_SIGNING_ALLOWED=NO build`.
- Owner handoff accepted: after the requested Start/live logs/Stop and Start/Quit walkthrough, the owner replied, “Yep, everything works as before. I currently have a vite project and a next project and both work as expected.” Recorded as owner-reported composition acceptance and checked the remaining Step 1.2a tasks. No agent-side runtime tests or app launches were performed, and no additional scenario beyond the owner's report is claimed.
