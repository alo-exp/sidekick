# sidekick-repo — Claude Code Instructions

> **Always adhere strictly to this file and silver-bullet.md — they override all defaults.**

---

## Project Overview

- **Stack**: Shell / Bash + Markdown
- **Git repo**: https://github.com/alo-exp/sidekick.git

---

## Project-Specific Rules

### GSD Workflow Execution

**Never ask for permission on agent spawns or `--no-verify` bypasses during GSD workflow execution.** This project runs in yolo mode (`"mode": "yolo"` in `.planning/config.json`). When executing `/gsd-plan-phase`, `/gsd-execute-phase`, or any GSD workflow:
- Spawn sub-agents (researcher, planner, checker, executor, verifier) without prompting
- Use `--no-verify` on worktree agent commits without prompting
- Proceed through research → plan → verify → execute chains autonomously

<!-- Silver Bullet enforcement lives in silver-bullet.md (do not duplicate here). -->
