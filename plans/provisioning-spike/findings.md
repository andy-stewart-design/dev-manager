# Provisioning spike findings

## Human-facing result

The walkthrough used a clean Tart Apple Silicon VM with a logged-in administrator. The app was built on the development host in Xcode and transferred by the user. The user reported that the Command Line Tools cancellation/retry path succeeded; the ready-state screenshot noted in the earlier evidence shows the selected tools. The user also supplied a screenshot showing Homebrew `7.0.13` executing as the current user and reported that quitting and reopening the app reused that state successfully.

The runtime fixture walkthrough was reported successful: Node `24.22.2`, pnpm `12.18.0`, the dependency-free HTTP fixture, Stop/restart, relaunch, and repeat setup all succeeded according to the user's report. The user reported that neither `~/.zshrc` nor `~/.zprofile` existed after that no-shell-edit walkthrough.

The user then reported the instructed clean-file Step 2.2 cycle as successful after building in Xcode and transferring the artifact to the VM: with `~/.zshrc` initially absent, Configure succeeded, repeat Configure added no duplicate, Check fresh Zsh verified fnm/Node/pnpm, and Restore returned the originally absent `~/.zshrc` to absent; `~/.zprofile` stayed absent. This successful history is preserved as user-reported only: the agent did not inspect files, versions, or screenshots, and did not build or test the latest checkout.

The first legacy-cycle issue was subsequently reported fixed by the user: after restoring the originally absent file, recreating `~/.zshrc` as only `# KEEP ME`, and explicitly pressing Restore, Configure preserved that baseline and started a new cycle. The source retains the optional restored receipt, explicit legacy recovery, scanning for unrelated fnm text on reconfigure, and generation-specific backups.

A follow-up unrelated-comment-after-block test **FAILED**. The extractor included the newline following the end marker, so the recorded block comparison failed when later user content was present. The source correction now extracts only the exact start-marker-through-end-marker range, preserves following content, and rejects same-line or malformed marker boundaries. This correction is pending user retest; no new build or VM result is claimed.

Existing-fnm conflict refusal, ordinary-project no-prompt behavior, Release build/gating, and the existing regression suite remain **NOT RUN**. The Phase 2 final gate remains unchecked. No result is inferred from source authoring alone. Source review also retains the existing fresh-shell timeout limitation: it times out the launched leader, not descendant process groups.

## Recommendation

The go/no-go recommendation is provisional: do not treat this spike as production-ready or make a production rollout decision until the user retests the source correction for unrelated content after the managed block and completes the remaining Step 2.2 shell walkthrough plus the Release/regression/isolation checks. The implementation intentionally keeps shell configuration optional; the fixture and normal app path do not depend on it.
