# Step 2.2 evidence

Status: The user-reported clean-file cycle succeeded, and the first legacy-cycle issue is now reported fixed by the user. A follow-up unrelated-comment-after-block test FAILED: the extractor included the newline after the end marker, so the recorded block comparison failed. The source correction is now pending user retest. The safety, isolation, and Phase 2 final-gate checks remain pending. No build, test, Release check, app launch, installation, download, or VM action was run by the agent.

## Source-only implementation review

- The DEBUG-only helper targets only the current user's `~/.zshrc`, never `~/.zprofile`, and uses a marked block with an absolute fnm invocation plus a safely quoted fnm parent-directory `PATH` entry before the later plain `fnm use`.
- Ownership metadata is written before target replacement and remains immutable across restore; block presence and recorded original content drive conservative retry/reconfigure behavior. Backup/target replacement uses native metadata copying and refuses metadata-copy failures rather than silently dropping ownership, ACLs, extended attributes, or flags.
- The first legacy-cycle issue was reported fixed by the user: with the originally absent `~/.zshrc` restored and then recreated as exactly `# KEEP ME`, the explicit Restore acknowledgement allowed Configure to preserve that baseline and begin a new cycle. The source retains the optional backward-compatible restored receipt, generation-specific backups for new cycles, and explicit legacy recovery through Restore.
- Follow-up failure: when unrelated content was appended after the managed block, Restore/Configure comparison failed because `managedBlock(from:)` included the newline following the end marker. The source now extracts only the exact marker range, preserves following content, and rejects markers that are not on line boundaries. This correction is pending user retest; no latest build or VM result is claimed.
- Restore removes the separator only when the complete current prefix is exactly the recorded backup followed by the app-added newline and the managed block remains at EOF. Otherwise it leaves the newline and user text unchanged. Repeated restore is a no-op; changed or conflicting owned blocks are refused.
- Existing noncomment fnm-related text is conservatively refused, including variable and line-continuation references; no shell parser or alias mutation was added.
- Fresh-shell diagnostics still use `/bin/zsh -i -c` with no login shell. The existing command timeout only times out the launched leader, not a descendant process group; no broader timeout change was made, so manual verification must retain that limitation.
- `ProvisioningModel` and `ProvisioningView` keep configuration consent-gated and separate from the no-shell-edit runtime path. No build, parse, test, VM, or manual shell verification is claimed here.

## Source-only verification

- Source inspection and diff review only, as required for this pass.
- `git diff --check` completed with no whitespace errors.
- An earlier `swiftc -parse` source check is historic and is not proof for the latest checkout. No `xcodebuild`, build, test, parse, Release check, app launch, installation, download, or VM action was run by the agent.

## Actual user results and pending retest (prerequisite: Step 2.1 is complete)

The user reported the original clean-file cycle succeeded: `~/.zshrc` was initially absent; Configure, repeat Configure, fresh-shell verification, and Restore all succeeded. The user then reported the first legacy-cycle issue fixed: after recreating `~/.zshrc` as exactly `# KEEP ME`, the explicit Restore acknowledgement allowed Configure to preserve the new baseline and start a new cycle. This remains user-reported evidence only.

A follow-up unrelated-comment-after-block test FAILED. With user content after the managed block, the extractor included the newline following the end marker, so the extracted block no longer matched `record.managedBlock` and the operation was refused. The source correction now owns only the exact marker range, preserves following content, and rejects same-line or otherwise malformed marker suffixes. It is pending user retest; no new build or VM result is claimed.

Exact retest after an updated Debug build is available:

1. Preserve the current test file and metadata; do not manually delete or edit the owned block.
2. Run the unrelated-comment-after-block case again. Confirm **Restore** removes only the exact managed block, preserves the following newline/comment and other content, and leaves the file unchanged on any malformed or same-line marker.
3. Confirm **Configure** accepts the restored baseline, appends one block, and repeat Configure is idempotent.
4. Run fresh-shell verification, then Restore; confirm unrelated content and metadata remain intact.
5. Reconfigure once more from that restored baseline and confirm the new cycle retains the prior backup.

If Configure finds an unrelated existing fnm initialization, it must still refuse it. If an active owned block is changed or manually removed, Configure must refuse it; pressing Restore is the explicit acknowledgement needed to mark that cycle restored.

## User manual checklist (prerequisite: Step 2.1 is complete)

The user reported building in Xcode, transferring the artifact to the clean Tart Apple Silicon administrator VM, and completing the instructed clean-file cycle. This is user-reported evidence only; the agent did not inspect files, versions, or screenshots.

1. **User-reported successful history:** With `~/.zshrc` initially absent (and `~/.zprofile` absent), the user used **Configure ~/.zshrc** and gave consent.
2. **User-reported successful history:** A second **Configure ~/.zshrc** produced no duplicate block.
3. **User-reported successful history:** **Check fresh Zsh** verified fnm, Node, and pnpm.
4. **User-reported successful history:** **Restore** returned the originally absent `~/.zshrc` to absent; `~/.zprofile` remained absent.
5. **User-reported result:** The first legacy-cycle issue was fixed after the explicit Restore acknowledgement; Configure preserved the recreated `# KEEP ME` baseline and started a new cycle.
6. **User-reported failure:** The unrelated-comment-after-block test failed because the extracted block included the newline after the end marker. The source correction is pending retest.
7. **Pending retest:** Repeat the unrelated-content Restore/Configure/fresh-shell cycle and the legacy-cycle sequence described above on the updated build.
8. **Remaining unchecked:** Create a clearly conflicting fnm configuration and confirm Configure refuses without rewriting it.
9. **Remaining unchecked:** Launch a known-working ordinary project through normal Start without setup, with no provisioning prompt or authorization request.
10. **Remaining unchecked:** Debug/Release build review, existing regression suite, and final Phase 2 acceptance review. No agent build or test result is claimed.
