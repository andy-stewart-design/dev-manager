# Approved Step 1.1 deviations

- The user approved GitHub CLI installation and reuse alongside the existing provisioning surface, including the surface's existing Release availability; this supersedes the plan/spec wording that treated production Release exposure as deferred. No distribution, signing, rollout, or authentication UI is added.
- The user approved implementation-time Debug compilation, Release compilation, and isolated full test execution. Verification remains incomplete until the user performs the manual VM detection/install/reuse scenarios.
- Step 1.1 adds a focused `ProvisioningGitHubCLITests.swift` file and small injected discovery/installer seams beyond the original expected-file list. These are limited to deterministic command/filesystem inspection and model operation coverage; no universal process abstraction or live CLI/Brew execution is introduced.
- The implementation keeps GitHub CLI binary availability independent from the managed Node runtime, uses the existing Homebrew prerequisite branch, and does not introduce authentication commands, auth fields, or a Release distribution workflow.
