# Dev Manager MVP Overview

## Purpose and intended change

Dev Manager is a SwiftUI macOS app for keeping local development projects running without managing a terminal window for each one. It runs each project's actual development command, exposes its logs, and helps the user open the local website on the port the server really chose.

It is intended for the owner and a small group of known users through direct distribution outside the Mac App Store. The [specification](spec.md) defines the authoritative behavior.

## How it is used

Add a project folder, open that project's toolbar gear to review or edit a command such as `pnpm dev`, and press Start from the main detail view. The main detail stays focused on `Execution` and `Output`; settings, Save/Cancel, and app-entry removal live in the per-project settings sheet. Watch output if needed, then use Open once the local website responds. If the command exposes several local websites, choose from their URLs.

For example, Next.js may print both `http://localhost:3000` and a Network address. Only the localhost site belongs in the website choices. If port 3000 is occupied and the server moves to another port, discovery follows that run rather than using a saved address.

Closing the window leaves development commands running; reopening restores access, while quitting the app normally stops them. Projects can be started and stopped independently. To begin another run, a user stops the project and starts it again manually; a successful new run intentionally has fresh logs and discovery, with no Restart button or cross-run history. On a later launch, the app may warn-only clean up a stale run when its recorded process identity is still positively verified; this is best-effort, not adoption or guaranteed crash cleanup.

## Mental model

A **project** is a folder and one configurable command. A **run** is one execution of that command and its subprocesses. A **website** is a responding local web endpoint associated with that run.

Process lifecycle and website availability are distinct: a command can be running without a website, and a printed URL is not yet proof that its endpoint responds. Website choices belong to the current run, not permanently to the project. Logs remain available after Stop or exit until the next Start; that Start begins a fresh bounded buffer rather than cross-run history.

## Scope and non-goals

- In scope: native process controls, captured logs, package-manager-independent commands, automatic dynamic-port discovery, local-only browser opening, and bounded verified stale-run recovery.
- Collaboration model: the owner supplies the Xcode scaffold and participates heavily in manual validation. The emphasis is a useful working MVP with lightweight targeted automation, not a sophisticated test harness. The detailed recovery contract and composition followups are in the [specification](spec.md) and [implementation plan](plan.md).
- Out of scope: full terminal emulation, Git operations, dependency installation, LAN/public websites, an in-app Restart action, cross-run log history, automatic restarts, and guaranteed cleanup after a crash or Force Quit.

## Related documents

- Specification: [spec.md](spec.md)
- Implementation plan: [plan.md](plan.md)
