# Step 1.1 evidence — Install and reuse GitHub CLI

## Scope implemented

- Added the optional top-level `githubCLI` check and separate `ProvisioningGitHubCLIContext` containing only a verified absolute executable URL and meaningful parsed version.
- Discovery preserves standard Homebrew/user locations, appends a bounded GUI `PATH` scan without hiding Homebrew, deduplicates candidates, distinguishes absent/non-executable/broken output, and runs only absolute `gh --version` for inspection.
- Added the independent Apple developer tools → Homebrew → GitHub CLI prerequisite branch. GitHub CLI is not part of `allRuntimeToolsReady`, fnm/Node/pnpm inspection, fixture readiness, shell readiness, or project execution.
- Added consented `brew install gh` installation using the existing bounded runner, preflight/post-install targeted reinspection, installation-only diagnostics, row progress, stale-operation ownership, reuse/no-upgrade behavior, and explicit failure handling.
- Added focused injected discovery/model/installer-description tests. No authentication command, login/status UI, credential field, Git configuration change, live CLI/Brew invocation, or host-auth probe was added.

## Verification performed

- Debug compile/test bundle:
  `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer /usr/bin/xcodebuild -quiet -project dev-manager.xcodeproj -scheme dev-manager -configuration Debug -destination 'platform=macOS,arch=arm64' -derivedDataPath /tmp/dev-manager-gh-debug CODE_SIGNING_ALLOWED=NO build-for-testing`
  Result: passed, exit 0. The existing two known actor-isolation warnings in `ProvisioningShellTransactionTests.swift` remain; no new GitHub CLI warnings were emitted.
- Release app build:
  `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer /usr/bin/xcodebuild -quiet -project dev-manager.xcodeproj -scheme dev-manager -configuration Release -destination 'generic/platform=macOS' -derivedDataPath /tmp/dev-manager-gh-release CODE_SIGNING_ALLOWED=NO build`
  Result: passed, exit 0. Xcode emitted only the known generic macOS placeholder operating-system-version warning.
- Isolated full suite, rebuilt Debug binary, no exclusions:
  result bundle `/tmp/dev-manager-gh-tests-1794915422-39528/result.xcresult`
  Result: passed, 118 tests, 0 failures, 0 skipped, 0 expected failures; 5 dynamic-parameter test runs. Tests used a copied `.xctestrun` with isolated `HOME`, `CFFIXED_USER_HOME`, `ZDOTDIR`, and `TMPDIR`, plus 60-second per-test allowances. Focused GitHub CLI tests were present and passed.
- `git diff --check`: passed.
- Read-only host run journal check around the final verification command was unchanged:
  `~/Library/Application Support/Dev Manager/runs.json` SHA-256 `4f53cda18c2baa0c0354bb5f9a3ecbe5ed12ab4d8e11ba873c2f11161202b945` before and after.

## Manual gate and caveats

PENDING user VM verification: with Apple developer tools/Homebrew ready and Node unavailable, detect/install missing `gh`, decline consent, exercise a failed/retry path, reopen, and reuse an existing working version without upgrade. Confirm local project readiness remains usable without `gh`. No live installation, authentication, VM transfer, app launch, or credentials were performed by this implementation run. The Step 1.1 manual completion gate and Phase 1 exit gate remain unchecked; do not start Phase 2 authentication work until user approval.
