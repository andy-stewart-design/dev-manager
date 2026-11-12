# Step 2.6 source-only evidence — per-tool provisioning presentation

## Scope

This note records the approved R12/AC12 implementation only. It does not claim a build, test, parse, launch, VM walkthrough, installer action, download, or final integration result.

## Approval and bounded change

The user approved the detailed initial-scan versus targeted-row flow with: “cool.let'sdoit”. The implementation is limited to the existing provisioning model, inspector/check values, and existing provisioning views, plus this evidence/change record. GitHub CLI and Bun remain out of scope. Existing command runner, runtime installer commands, fixture safety, shell parser/receipt, pins, and normal project runner are not changed.

## Implemented by source inspection

- `ProvisioningModel` derives a row-local action for Apple developer tools, Homebrew, fnm, Node, and pnpm, including enabled state, reason, label, and active target.
- Ready rows have green status and no Install action. Missing rows offer a bordered Install only when the prerequisite chain is ready. Missing-prerequisite and unverified rows keep Install disabled with an explanation. Row eligibility and the write-time guard use the same full dependency-chain evaluator, including pre-existing downstream tools with missing upstream prerequisites.
- Attention/conflict states offer Check again rather than blind installation. Apple/Homebrew external handoffs retain their waiting latches and expose Check installation after the handoff. Check actions inspect actual state before retrying.
- One targeted consent describes the selected tool and effect. Runtime actions call only the existing command for fnm, Node, or pnpm; no automatic dependency chain is installed. Reinspection occurs while the active target remains set, so an externally completed install is reused and a new conflict is refused.
- Active work shows progress for its target and disables other row actions, including Advanced and shell controls. Runtime install preflight and postflight use the fresh targeted inspection while retaining ownership; stale completions cannot clear a newer operation or overwrite its context.
- Fixture preparation is a separate consented Advanced action and only materializes the owned fixture when all runtime checks are ready. It does not install tools. Show fixture handoff remains available after preparation.
- Optional shell configuration is a separate row after the Node group once runtime is ready. Configure is separate and optional; Restore, fresh-shell verification, output, and repeat/recovery controls remain in Advanced.
- The global footer action and footer divider are removed; the main header, intro, inline info popovers, Node grouping, tertiary status icons, close/Escape behavior, and Advanced title-menu handoff remain.
- Installation diagnostics are visible in the status surface as selectable output, not only in an informational tooltip.

## Approved layout follow-up

The user also approved a bounded presentation refinement: retain the existing subtle bordered buttons; use one shared row layout with `rowMinimumHeight = 32`, `rowVerticalPadding = 10`, and horizontal `itemSpacing = 10`; apply it to Apple tools, Homebrew, the Node header/children, and optional shell with row-list stacks at spacing `0`. Keep content centered within each row, allow wrapped status/error text to grow, and place Node separators at `nodeIndent + statusIconWidth + itemSpacing` while actions remain flush right. Existing row indentation, inline info controls, optional shell alignment, scalable scrolling, and all provisioning behavior remain unchanged.

This follow-up is source-only and pending the user Debug build/manual layout review. No build, test, parse, launch, installer, download, VM, or final-gate result is claimed.

## Approved initial scan versus targeted-row recheck flow

Only the first whole-machine inspection uses the existing centered full-sheet `ProgressView` and “Inspecting installed tools…” label. The independent `hasLoadedInitialInspection` lifecycle flag is set after that global inspection returns states; later global checks retain the checklist and existing statuses. Advanced Check again can show one global progress notice without resetting rows to `.checking`. Row Check installation/Check again and install pre/postflight use row-local ownership and spinner presentation, suppressing redundant top progress while preserving visible errors.

`ProvisioningInspector.inspect(target:)` checks Apple developer tools alone, Homebrew alone, or a fresh fnm context plus the combined Node/pnpm runtime checks for runtime rows. Model application patches only returned IDs. A fresh unusable fnm context clears the cached executable rather than being reused. Ownership UUIDs cover global and targeted completions so stale work cannot clear a newer spinner or overwrite fresh runtime context.

This is source-only evidence pending targeted manual/debug tests and the existing Debug/manual review. No build, test, parse, launch, installer, download, VM, or final-gate result is claimed.

## New Step 2.6 manual/debug matrix — pending user verification

The following remain pending and unchecked: Debug build/manual launch; clean VM prerequisite absence; individual-only fnm/Node/pnpm installation; external Apple/Homebrew waiting and recheck; active-operation disabling; attention/conflict refusal; all-ready state; separate fixture preparation and Advanced fixture handoff; optional shell behavior; ordinary-project isolation; Release/setup absence; existing tests/regressions; and final acceptance review.

No fake build, test, VM, or final-gate result is recorded here.
