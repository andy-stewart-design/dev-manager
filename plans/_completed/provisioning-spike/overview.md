# Machine Provisioning Spike Overview

## Purpose and intended change

Explore whether a non-developer can prepare a Mac and run a local project without opening Terminal, copying commands, or editing shell files.

This is a small development-only experiment, using a disposable Apple Silicon macOS VM and a logged-in administrator—not a production onboarding system.

## How it is used

The user opens a setup screen, approves the necessary changes, and completes Apple's developer-tool and Homebrew installation dialogs. The app then offers separate, current-state actions for Apple developer tools, Homebrew, fnm, Node, and pnpm, enforcing their prerequisite chain without automatic chaining. The DEBUG surface keeps diagnostics and spike-only controls available from the sheet-title context menu in a separate Advanced / spike tools surface; it has no global footer action. Once the machine is ready, an unconfigured shell appears as a clearly optional row after the Node group; shell configuration never blocks readiness or closing.

After demonstrating operation without shell edits, a separate opt-in experiment explores making fnm available in future Zsh sessions.

## Mental model

The app coordinates setup and verifies the result. macOS owns privileged installer dialogs and authentication. Existing project execution remains separate: launching a project is not permission to install machine-wide tools. The implementation is organized under [`dev-manager/Provisioning/`](../../dev-manager/Provisioning/) with UI in [`Views/`](../../dev-manager/Provisioning/Views/): the model coordinates concrete inspection, installer, runtime, fixture, command, shell-safety, and bounded installation-log components without changing the existing runner. Runtime installation diagnostics are discoverable from Advanced rather than shown as an inline transcript.

## Scope and non-goals

- In scope: minimal setup controls, one fixed runtime, a fixture project, manual VM checks, and concise findings.
- Out of scope: production polish, a provisioning framework, standard-user deployment, Intel, GitHub authentication, upgrades/uninstall, and a new automated test harness.

## Related documents

- Specification: [spec.md](spec.md)
- Implementation plan: [plan.md](plan.md)
- Architecture evidence: [step-2.4.md](evidence/step-2.4.md)
- Final cleanup evidence: [step-2.7.md](evidence/step-2.7.md)
