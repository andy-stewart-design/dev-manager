# Repo-aware Execution Overview

## Purpose and intended change

Dev Manager should understand enough about a Node project to suggest how to run it and explain which tools it needs, instead of accepting a folder and blindly trying `pnpm dev`.

This feature builds on production machine provisioning. It connects repository requirements to day-to-day execution while retaining custom commands for other technologies and unusual setups.

## How it is used

A developer adds a project folder. The app reads its metadata and, when resolution succeeds, suggests a package script and npm or pnpm. A banner at the top explains any missing tools; **Set up requirements** approves that setup.

**Install dependencies** is a separate action, with an explanation that installation may run repository scripts. Once the tools are ready, Run uses the resolved toolchain. A developer can instead choose a custom shell command.

For a monorepo, the developer adds the root with its own runnable script or selects an individual package folder. Relevant workspace requirements can be inherited without changing the selected working directory.

## Mental model

- **Project understanding:** read repository declarations and explain the proposed command and tools.
- **Machine readiness:** prepare the approved Node/package-manager versions through provisioning.
- **Project dependencies:** install separately, with their own approval and output.
- **Execution:** guided mode uses the resolved tools; custom mode retains shell-controlled behavior.

Tool readiness is not a claim that project dependencies are installed or current. Preparing one project is not intended to change another project's toolchain.

## Scope and non-goals

- In scope: Node-first guidance, npm/pnpm, a requirements banner, approved setup and dependency installation, and repository-aware execution.
- Out of scope: productionizing foundational provisioning, other managed ecosystems, an app-level version switcher, workspace browsing, and multi-service orchestration.

## Related documents

- Authoritative specification: [spec.md](spec.md)
- Implementation plan: [plan.md](plan.md)
- Foundational provisioning context: [provisioning spike specification](../_completed/provisioning-spike/spec.md)
