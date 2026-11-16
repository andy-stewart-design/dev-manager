# Optional GitHub CLI Overview

## Purpose and intended change

Dev Manager can optionally install GitHub CLI and help a user authenticate to a chosen GitHub host without making local project readiness depend on GitHub. The exact safety, host, device-login, and credential behavior is defined by the [specification](spec.md).

## How it is used

A user sees GitHub CLI as a separate top-level optional row. They may install it through the existing consent-based Homebrew path, inspect the selected host's account status, or open a focused hostname modal and complete GitHub's device login in the system browser. Missing CLI, offline status, and unauthenticated hosts remain non-blocking.

## Mental model

Binary availability and host authentication are different states: a working `gh` may still be unauthenticated, and one host's account must not affect another host. The app coordinates consent, validation, bounded status/login operations, and redacted presentation; Homebrew, `gh`, macOS, the browser, and GitHub retain ownership of installation, credentials, navigation, and authorization.

## Scope and non-goals

- In scope: optional Homebrew installation, host-scoped read-only status, device login, Enterprise hosts where supported, and cancellation/privacy boundaries.
- Out of scope: project readiness gates, password/PAT capture, Git configuration, logout/revocation, account management, custom OAuth, PTYs, and Release exposure.

## Related documents

- Specification: [spec.md](spec.md)
- Implementation plan: [plan.md](plan.md)
