# Step 2.6 source-only evidence — per-tool provisioning presentation

## Scope

This note records the approved R12/AC12 implementation only. It does not claim a build, test, parse, launch, VM walkthrough, installer action, download, or final integration result.

## Approval and bounded change

The user approved the per-tool proposal with: “Yeah, I’m good with this. Let’s do it”. The implementation is limited to the existing provisioning model and three existing provisioning views, plus the plan/spec/overview/change records. GitHub CLI and Bun remain out of scope. Existing command runner, inspector, runtime installer commands, fixture safety, shell parser/receipt, pins, and normal project runner are not changed.

## Implemented by source inspection

- `ProvisioningModel` derives a row-local action for Apple developer tools, Homebrew, fnm, Node, and pnpm, including enabled state, reason, label, and active target.
- Ready rows have green status and no Install action. Missing rows offer a bordered Install only when the prerequisite chain is ready. Missing-prerequisite and unverified rows keep Install disabled with an explanation. Row eligibility and the write-time guard use the same full dependency-chain evaluator, including pre-existing downstream tools with missing upstream prerequisites.
- Attention/conflict states offer Check again rather than blind installation. Apple/Homebrew external handoffs retain their waiting latches and expose Check installation after the handoff. Check actions inspect actual state before retrying.
- One targeted consent describes the selected tool and effect. Runtime actions call only the existing command for fnm, Node, or pnpm; no automatic dependency chain is installed. Reinspection occurs while the active target remains set, so an externally completed install is reused and a new conflict is refused.
- Active work shows progress for its target and disables other row actions. The existing `allowDuringInstallation` check path is retained for post-command rechecks.
- Fixture preparation is a separate consented Advanced action and only materializes the owned fixture when all runtime checks are ready. It does not install tools. Show fixture handoff remains available after preparation.
- Optional shell configuration is a separate row after the Node group once runtime is ready. Configure is separate and optional; Restore, fresh-shell verification, output, and repeat/recovery controls remain in Advanced.
- The global footer action and footer divider are removed; the main header, intro, inline info popovers, Node grouping, tertiary status icons, close/Escape behavior, and Advanced title-menu handoff remain.
- Installation diagnostics are visible in the status surface as selectable output, not only in an informational tooltip.

## Approved layout follow-up

The user also approved a bounded presentation refinement: retain the existing subtle bordered buttons; use one shared row layout with `rowMinimumHeight = 32`, `rowVerticalPadding = 10`, and horizontal `itemSpacing = 10`; apply it to Apple tools, Homebrew, the Node header/children, and optional shell with row-list stacks at spacing `0`. Keep content centered within each row, allow wrapped status/error text to grow, and place Node separators at `nodeIndent + statusIconWidth + itemSpacing` while actions remain flush right. Existing row indentation, inline info controls, optional shell alignment, scalable scrolling, and all provisioning behavior remain unchanged.

This follow-up is source-only and pending the user Debug build/manual layout review. No build, test, parse, launch, installer, download, VM, or final-gate result is claimed.

## Approved inspection loading simplification

At the existing main content boundary, initial/manual inspection (`checks.isEmpty` or `isChecking && activeToolID == nil`) now replaces the checklist and global progress notice with one horizontally and vertically centered `ProgressView` plus “Inspecting installed tools…”. The loading view has a combined accessibility label, does not render a list behind it, and keeps the existing body/sheet dimensions. Active-tool rechecks exclude the loading state so installation progress remains on its target row; completed checks restore the existing checklist.

This is source-only evidence pending the user Debug build and manual review. No build, test, parse, launch, installer, download, VM, or final-gate result is claimed.

## New Step 2.6 manual/debug matrix — pending user verification

The following remain pending and unchecked: Debug build/manual launch; clean VM prerequisite absence; individual-only fnm/Node/pnpm installation; external Apple/Homebrew waiting and recheck; active-operation disabling; attention/conflict refusal; all-ready state; separate fixture preparation and Advanced fixture handoff; optional shell behavior; ordinary-project isolation; Release/setup absence; existing tests/regressions; and final acceptance review.

No fake build, test, VM, or final-gate result is recorded here.
