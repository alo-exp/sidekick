# Audience

> Who each current Sidekick document is for, and where to start.

## Reader Matrix

| Reader | Best first doc | Why |
| --- | --- | --- |
| New user | [START-HERE.md](START-HERE.md) | Gives the shortest path from overview to first delegated task. |
| Maintainer | [ARCHITECTURE.md](ARCHITECTURE.md), [TESTING.md](TESTING.md) | Explains system boundaries and verification. |
| Release operator | [TESTING.md](TESTING.md), [CICD.md](CICD.md), [pre-release-quality-gate.md](pre-release-quality-gate.md) | Covers test runners, release markers, and live gate evidence. |
| Plugin author | [GLOSSARY.md](GLOSSARY.md), [COMPATIBILITY.md](COMPATIBILITY.md) | Defines terms, generated surfaces, and host/runtime boundaries. |
| Claude Code user | [help/](help/), [help/getting-started/](help/getting-started/) | Shows how a Claude Code host activates Kay or Codex delegation. |
| Codex host user | [help/](help/), [COMPATIBILITY.md](COMPATIBILITY.md) | Shows how a Codex host activates Kay or Codex delegation. |
| Kay user | [help/workflows/](help/workflows/), [COMPATIBILITY.md](COMPATIBILITY.md) | Focuses on Kay runtime routing and provider selectors. |
| Codex sidekick user | [help/workflows/](help/workflows/), [GLOSSARY.md](GLOSSARY.md) | Focuses on local OpenAI Codex CLI delegation. |

## How To Use This Matrix

- Start with the row that matches your role.
- If you do not know your role, start with [START-HERE.md](START-HERE.md).
- If you need exact terms, read [GLOSSARY.md](GLOSSARY.md).
- If you need host/runtime differences, read [COMPATIBILITY.md](COMPATIBILITY.md).
