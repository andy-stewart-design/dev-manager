# Step 2.7 source-only evidence — persistent bounded installation diagnostics and quiet shell row

## Scope

This note records the approved final cleanup only. It does not claim a build, test, parse, launch, VM walkthrough, installation, download, log-write exercise, or final integration result.

## Approved change

The user-approved request was to “remove inline INSTALLATION OUTPUT from provisioning UI” and “remove optionalShellrowsecondline,” with the current screenshot described as showing the npm transcript and Optional Shell Configuration subtitle. The implementation keeps the existing provisioning model, pins, commands, timeout policies, loading/recheck ownership, shared row spacing, centered row layout, and safety boundaries.

## Implemented by source inspection

- Added one concrete `ProvisioningInstallationLog` helper under `dev-manager/Provisioning/`.
- Runtime installation records use the existing fixed installation labels and returned bounded process tails. Each record adds an ISO-8601 timestamp, exit/timeout status, stdout, and stderr without environment or credential data.
- The app-owned path is `~/Library/Application Support/Dev Manager/Logs/provisioning.log`, with a 256 KiB current-file cap and one `provisioning.log.1` rotated previous file. New log directories are private (`0700`) and written log files are private (`0600`); symlinked, dangling, or non-directory app-owned paths are refused.
- Source inspection now validates every existing current/rotated regular log as single-link (`st_nlink == 1`), owned by the effective user, exactly `0600`, and within the size cap before reading or replacing it. Existing-only discovery performs no chmod or other write, and creation does not globally chmod the Application Support root.
- Rotation validates both log paths and atomically renames current over the validated previous file, preserving the previous backup if rename fails; it does not unlink first, so the one-backup size cap has no deletion window.
- A successful append updates a validated log URL. A failed append exposes a warning without changing the installation result or its original command error. A failed runtime installation links only the log actually written for that failure. A validated prior log is discoverable from Advanced after a new model/app session.
- `AppendResult`, `PathKind`, `LogError`, and `errorDescription` have explicit nonisolated boundaries for the project’s default MainActor isolation without adding mutable nonisolated state.
- Removed `installationOutput` and both inline installation transcript presentations. Fresh-shell verification output remains in Advanced.
- Removed only the optional shell row's second-line state label. Its title, info detail button, status icon/color, Configure action, and error notices remain.

## Pending user verification

All verification remains pending. The user-owned Debug build and manual checks still need to confirm a successful runtime installation creates the log; a runtime failure exposes its just-written failure-log reference; reopening the app reveals an existing prior log; rotation/cap, ownership, link-count, permissions, and unsafe-path behavior; and a log-write failure leaves the original installation result/error intact. No runtime logger exercise, rotation test, build, test, parse, launch, installation, download, VM walkthrough, or final integration result is claimed here. All prior acceptance gates, AC13, Step 2.7, and the final integration gate remain unchecked; no fake passes are recorded.
