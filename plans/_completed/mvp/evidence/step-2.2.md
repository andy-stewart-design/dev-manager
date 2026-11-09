# Step 2.2 — listener attribution and local readiness

## Core owner acceptance

The owner approved startup-only checks without repeated HEAD polling, accepted the working HTTP discovery/browser flow, and finally reported that the delayed-start/Stop/fresh-run walkthrough worked as expected. See `step-2.3.md` for the actual owner report and narrowed MVP boundary. The core cancellation/readiness and final core verification tasks are checked. Silent-server fallback, multi-site, trusted HTTPS, expanded response fixtures, and additional native state tests remain unverified/deferred, not passed. Earlier pending core notes below are superseded only for this accepted baseline; no agent runtime actions were performed.

## Implemented

- Per-run discovery now caches only successful startup verifications by exact URL plus the full owned listener identity (PID, OS start time, process group, and port). The coordinator continues bounded listener/announcement scans for new targets and ownership changes, but does not issue another HTTP request for an unchanged verified endpoint.
- Failed/unresponsive candidates continue bounded retries until they respond or the run is stopped. Silent fallback protocol selection settles after the first responding protocol (HTTPS remains preferred when both respond); an explicit announced HTTPS URL is never downgraded. New announced URLs/ports are checked, and listener disappearance or identity replacement invalidates the cached entry.
- Stop/exit cancellation clears the per-run verification cache and protects against late publication. The existing `responding` state is displayed as startup `Ready`, not as a continuous health claim.

## Verification

- Scoped build passed (exit 0):

  `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -quiet -project dev-manager.xcodeproj -scheme dev-manager -configuration Debug -destination 'generic/platform=macOS' -derivedDataPath /tmp/dev-manager-2.2-build CODE_SIGNING_ALLOWED=NO build`

- No app launch, tests, hosted tests, dev commands, listeners, or runtime HTTP checks were performed.
- Manual Step 2.2 verification remains unchecked: start Astro and confirm the initial HEAD check then no ongoing HEAD polling; make a new port/run and confirm a new check; Stop clears readiness. Prior basic discovery observation does not verify this polling change.

## Scope note

This is the approved polling/readiness clarification only. No browser/Open action or UI redesign was added; those remain Step 2.3 work.
