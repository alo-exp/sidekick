# Audience

> Who each Sidekick document is for, and where to start.

---

## Reader Matrix

| Reader | Best first doc | Why |
|--------|----------------|-----|
| New user | [START-HERE.md](START-HERE.md) | Gives the quickest path from "what is this?" to the right workflow |
| Maintainer | [ARCHITECTURE.md](ARCHITECTURE.md), [TESTING.md](TESTING.md) | Explains how the system fits together and how it is verified |
| Release operator | [TESTING.md](TESTING.md), [CICD.md](CICD.md), [pre-release-quality-gate.md](pre-release-quality-gate.md) | Covers the release pyramid and the manual release gate |
| Plugin author | [GLOSSARY.md](GLOSSARY.md), [COMPATIBILITY.md](COMPATIBILITY.md), [internal/codex-command-packaging-guide.md](internal/codex-command-packaging-guide.md) | Clarifies the canonical terms and runtime packaging boundaries |
| Claude user | [help/](help/), [help/getting-started/](help/getting-started/) | Focuses on the Forge/Claude delegation experience |
| Kay user | [COMPATIBILITY.md](COMPATIBILITY.md), [internal/codex-command-packaging-guide.md](internal/codex-command-packaging-guide.md) | Focuses on the Kay sidekick runtime and its packaging contract |
| Kay operator | [COMPATIBILITY.md](COMPATIBILITY.md), [README.md](../README.md) | Explains how the MiniMax-backed Kay runtime fits into Sidekick |

## How to Use This Matrix

- Start with the row that matches your role.
- If you do not know your role, start with [START-HERE.md](START-HERE.md).
- If you need exact wording or definitions, move to [GLOSSARY.md](GLOSSARY.md).
- If you need runtime differences between Claude, Codex, and Kay, move to [COMPATIBILITY.md](COMPATIBILITY.md).
