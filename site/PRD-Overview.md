# PRD Overview

Sidekick helps a host AI delegate coding tasks to supported local sidekicks while retaining host accountability for planning, verification, and communication.

## Goals

- Provide clear activation and stop workflows for Kay and Codex.
- Prevent host direct edits while a sidekick mode is active.
- Keep sidekick outputs bounded and redacted in the host transcript.
- Require host verification after every delegated task.
- Ship release evidence through strict local tests and Kay-wrapped live gates.

## Success Criteria

A release is acceptable when manifests expose only Kay and Codex, generated host bundles match canonical skills, current docs match the supported surface, strict tests pass, skip-safe live wrappers pass, and the release gate records the required Kay-wrapped live evidence.
