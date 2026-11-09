# Step 2.1 evidence

## Implementation

- Added `dev-manager/Discovery/LocalURLCandidate.swift`: Foundation URL parsing/normalization restricted to HTTP/HTTPS `localhost`, `127.0.0.1`, and `::1`; rejects credentials, invalid ports, LAN/public/deceptive hosts, and non-web schemes; normalizes host case and an omitted root slash.
- Added `dev-manager/Discovery/LocalURLParser.swift`: bounded per-stdout/stderr streaming state, split UTF-8 handling, ANSI CSI/OSC stripping, chunk-safe URL token buffering, punctuation handling, EOF flushing, and cross-stream duplicate suppression. It returns candidates only; it does not probe, attribute ownership, update run state, or open a browser.
- Added `dev-managerTests/Discovery/LocalURLCandidateTests.swift` with small native Swift Testing table cases for Vite/Next/Astro-style output, ANSI and byte chunking, loopback policy, paths/query, deduplication, false-local URLs, invalid ports, and incomplete tokens. Tests were not executed.

## Verification

- Final compile-only command passed (exit 0; no app launch and no test execution):
  `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -quiet -project dev-manager.xcodeproj -scheme dev-manager -configuration Debug -destination 'platform=macOS,arch=arm64' -derivedDataPath /tmp/dev-manager-2.1-build CODE_SIGNING_ALLOWED=NO build-for-testing`
- The initial compile was blocked by older `ProjectRunnerTests.swift` constructors missing the previously added `startTime` argument. Those call sites now pass the corresponding spawned process's actual start time; no process test was executed or broadened. App and test bundles subsequently compiled successfully.
- Parser source review added bracket-aware IPv6 normalization, safe Data slice indexing, and a 256-unique-candidate bound in addition to the 16,384-character pending-text bound per stream. Files live in `Discovery/` following the approved modular layout. These are implementation/static checks, not claims of executed parser cases.
- Parser tests remain pending and were deliberately not run. This compile/static check does not claim AC11 runtime, server readiness, ownership attribution, browser behavior, or AC11/AC7/AC8 acceptance.

## Handoff

Pure parsing step only. No UI, runner wiring, listener probing, browser action, phase-gate edit, or 2.2 work was performed. Focused parser execution may be owner-approved later if desired.
