# Agreed planning changes

## Minimum macOS version

- Change: set the app and native unit-test minimum deployment targets to macOS 15.0 (Sequoia), replacing the previously unspecified target in the spec/plan. No macOS 14 compatibility work is planned.
- Actual agreement: after the assistant recommended macOS 14, the owner responded, “Honestly, 15.0 seems fine. That was released 2+ years ago.” The owner's chosen compatibility boundary takes precedence over that recommendation.
- Updated the spec's platform scope/remaining scaffold decisions and the plan's execution constraints/Step 0.1. Step IDs, task completion, acceptance mappings, and evidence paths are unchanged. This records a planning decision only; no Xcode configuration was changed and no build or runtime check was performed.

## Explicit request: complete the missing native test scaffold

- Change: for the current request to finish the technical scaffold portion of Phase 0/Step 0.1, add the missing lightweight native macOS unit-test target and one Swift Testing smoke-test source within the existing owner-created Xcode scaffold. Wire the existing `dev-manager` scheme's Test action through a shared scheme only as needed for the repeatable native test command.
- Actual authorization: the user explicitly asked to “do what we need to do to finish out 0.1” after the missing native target and build/test/launch validation were identified. This changes only who adds the missing target: the implementation worker may complete that target in the existing scaffold instead of the earlier owner-through-Xcode-only instruction.
- Narrow plan amendment: Step 0.1 now permits this explicit in-scaffold target addition and records it as the completed target task. IDs, gates, verification requirements, owner environment coordination, signing/security boundaries, and all other tasks remain unchanged. G0 and the entire Step 0.1 verification remain unchecked pending the remaining owner-side/manual prerequisites.
