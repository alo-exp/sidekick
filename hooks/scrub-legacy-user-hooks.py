#!/usr/bin/env python3
"""Sidekick Plugin - legacy user-hook scrubber with rollback support.

This migration removes only Sidekick-owned legacy hook blocks from user-level
Codex hook files, leaving unrelated user hooks untouched. When it changes a
file, it stores an exact backup under
~/.claude/.sidekick/legacy-hooks-scrub-backups/ so the scrub can be rolled
back later.
"""

from __future__ import annotations

import argparse
import json
import os
import shutil
import sys
import tempfile
from dataclasses import asdict, dataclass
from datetime import datetime, timezone
from pathlib import Path
from typing import Any


STATE_DIR = Path.home() / ".claude" / ".sidekick"
STATE_FILE = STATE_DIR / "legacy-hooks-scrub-state.json"
BACKUP_DIR = STATE_DIR / "legacy-hooks-scrub-backups"
TARGETS = (Path.home() / ".codex" / "hooks.json", Path.home() / ".Codex" / "hooks.json")
MIGRATION_ID = "legacy-hooks-scrub-v1"
SCRIPT_PATH = Path(__file__).resolve()

BLOCK_SIGNATURES = (
    {
        "event": "SessionStart",
        "matcher": None,
        "commands": ("install.sh",),
        "kind": "install",
    },
    {
        "event": "PreToolUse",
        "matcher": "Write|Edit|NotebookEdit|Bash|mcp__filesystem__write_file|mcp__filesystem__edit_file|mcp__filesystem__move_file|mcp__filesystem__create_directory",
        "commands": ("forge-delegation-enforcer.sh", "codex-delegation-enforcer.sh"),
        "kind": "delegation-enforcers",
    },
    {
        "event": "PreToolUse",
        "matcher": "Bash",
        "commands": ("validate-release-gate.sh",),
        "kind": "validate-release-gate",
    },
    {
        "event": "PostToolUse",
        "matcher": "Bash",
        "commands": ("forge-progress-surface.sh", "codex-progress-surface.sh"),
        "kind": "progress-surface",
    },
)


@dataclass
class TargetResult:
    path: str
    removed_blocks: int = 0
    backup_path: str | None = None
    status: str = "unchanged"
    error: str | None = None


def utc_now() -> datetime:
    return datetime.now(timezone.utc)


def iso_now() -> str:
    return utc_now().strftime("%Y-%m-%dT%H:%M:%SZ")


def stamp_now() -> str:
    return utc_now().strftime("%Y%m%dT%H%M%SZ")


def load_json(path: Path) -> Any:
    with path.open("r", encoding="utf-8") as fh:
        return json.load(fh)


def dump_json_atomic(path: Path, payload: Any) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    fd, tmp_name = tempfile.mkstemp(prefix=f".{path.name}.", suffix=".tmp", dir=str(path.parent))
    tmp_path = Path(tmp_name)
    try:
        with os.fdopen(fd, "w", encoding="utf-8") as fh:
            json.dump(payload, fh, indent=2, ensure_ascii=False)
            fh.write("\n")
        os.replace(tmp_path, path)
    finally:
        if tmp_path.exists():
            try:
                tmp_path.unlink()
            except FileNotFoundError:
                pass


def load_state() -> dict[str, Any] | None:
    if not STATE_FILE.exists():
        return None
    try:
        data = load_json(STATE_FILE)
    except Exception:
        return None
    return data if isinstance(data, dict) else None


def save_state(state: dict[str, Any]) -> None:
    dump_json_atomic(STATE_FILE, state)


def command_matches_install(command: str) -> bool:
    return all(snippet in command for snippet in ("test -f", ".installed", "install.sh", "touch", "bash"))


def command_matches_script(command: str, script_name: str) -> bool:
    return script_name in command and any(prefix in command for prefix in ("bash", "python3"))


def block_matches_signature(event_name: str, block: dict[str, Any], signature: dict[str, Any]) -> bool:
    if event_name != signature["event"]:
        return False

    if block.get("matcher") != signature["matcher"]:
        return False

    hooks = block.get("hooks")
    if not isinstance(hooks, list) or len(hooks) != len(signature["commands"]):
        return False

    for hook, script_name in zip(hooks, signature["commands"]):
        if not isinstance(hook, dict) or hook.get("type") != "command":
            return False
        command = hook.get("command")
        if not isinstance(command, str):
            return False
        if script_name == "install.sh":
            if not command_matches_install(command):
                return False
        elif not command_matches_script(command, script_name):
            return False

    return True


def detect_wrapper_shape(data: dict[str, Any]) -> tuple[dict[str, Any], str]:
    hooks_value = data.get("hooks")
    if isinstance(hooks_value, dict) and any(name in hooks_value for name in ("SessionStart", "PreToolUse", "PostToolUse")):
        return hooks_value, "wrapper"
    return data, "direct"


def strip_sidekick_blocks(data: dict[str, Any]) -> tuple[dict[str, Any], list[dict[str, Any]]]:
    container, shape = detect_wrapper_shape(data)
    if not isinstance(container, dict):
        raise ValueError("hook container is not an object")

    cleaned = json.loads(json.dumps(container))
    removed: list[dict[str, Any]] = []

    for event_name in ("SessionStart", "PreToolUse", "PostToolUse"):
        entries = cleaned.get(event_name)
        if not isinstance(entries, list):
            continue

        kept_entries: list[Any] = []
        for entry in entries:
            matched = False
            if isinstance(entry, dict):
                for signature in BLOCK_SIGNATURES:
                    if block_matches_signature(event_name, entry, signature):
                        removed.append(
                            {
                                "event": event_name,
                                "kind": signature["kind"],
                                "matcher": signature["matcher"],
                            }
                        )
                        matched = True
                        break
            if not matched:
                kept_entries.append(entry)
        cleaned[event_name] = kept_entries

    if shape == "wrapper":
        return {**data, "hooks": cleaned}, removed
    return cleaned, removed


def hook_file_summary(path: Path, removed: list[dict[str, Any]]) -> str:
    if not removed:
        return f"{path}: no Sidekick legacy hook blocks found"
    kinds = ", ".join(sorted({item["kind"] for item in removed}))
    return f"{path}: removed {len(removed)} Sidekick legacy hook block(s) ({kinds})"


def backup_path_for(target: Path, run_stamp: str) -> Path:
    safe_name = target.as_posix().lstrip("/").replace("/", "_")
    return BACKUP_DIR / run_stamp / f"{safe_name}.bak"


def write_cleaned_target(target: Path, cleaned: dict[str, Any]) -> None:
    fd, tmp_name = tempfile.mkstemp(prefix=f".{target.name}.", suffix=".tmp", dir=str(target.parent))
    tmp_path = Path(tmp_name)
    try:
        with os.fdopen(fd, "w", encoding="utf-8") as fh:
            json.dump(cleaned, fh, indent=2, ensure_ascii=False)
            fh.write("\n")
        os.replace(tmp_path, target)
    finally:
        if tmp_path.exists():
            try:
                tmp_path.unlink()
            except FileNotFoundError:
                pass


def apply_migration(force: bool = False) -> int:
    state = load_state()
    if state and state.get("status") in {"applied", "clean", "rolled_back"} and not force:
        print(f"[sidekick] legacy hook scrub already {state['status']}; skipping")
        return 0

    run_stamp = stamp_now()
    results: list[TargetResult] = []
    any_changes = False
    any_errors = False

    for target in TARGETS:
        result = TargetResult(path=str(target))
        if not target.exists():
            result.status = "absent"
            results.append(result)
            continue

        try:
            original = load_json(target)
            if not isinstance(original, dict):
                raise ValueError("user hook file must be a JSON object")

            cleaned, removed = strip_sidekick_blocks(original)
            result.removed_blocks = len(removed)

            if removed:
                any_changes = True
                backup_path = backup_path_for(target, run_stamp)
                backup_path.parent.mkdir(parents=True, exist_ok=True)
                shutil.copy2(target, backup_path)
                write_cleaned_target(target, cleaned)
                result.backup_path = str(backup_path)
                result.status = "scrubbed"
                print(f"[sidekick] {hook_file_summary(target, removed)}")
                print(f"[sidekick] backup saved to {backup_path}")
            else:
                result.status = "clean"
                print(f"[sidekick] {target}: no legacy Sidekick hooks found")
        except Exception as exc:  # pragma: no cover - defensive runtime path
            result.status = "error"
            result.error = str(exc)
            any_errors = True
            print(f"[sidekick] warning: could not scrub {target}: {exc}", file=sys.stderr)
        results.append(result)

    state_payload: dict[str, Any] = {
        "migration": MIGRATION_ID,
        "status": "partial" if any_errors else ("applied" if any_changes else "clean"),
        "checked_at": iso_now(),
        "targets": [asdict(item) for item in results],
    }
    save_state(state_payload)

    if any_changes:
        print(f"[sidekick] rollback available via: python3 \"{SCRIPT_PATH}\" --rollback")
    else:
        print("[sidekick] no legacy Sidekick user-hook entries to scrub")

    return 0


def rollback_migration() -> int:
    state = load_state()
    if not state or state.get("migration") != MIGRATION_ID:
        print("[sidekick] no legacy hook scrub state found; nothing to roll back")
        return 0

    targets = state.get("targets") if isinstance(state.get("targets"), list) else []
    restored_any = False

    for entry in targets:
        if not isinstance(entry, dict):
            continue
        target = entry.get("path")
        backup_path = entry.get("backup_path")
        if not isinstance(target, str) or not isinstance(backup_path, str):
            continue
        target_path = Path(target)
        backup = Path(backup_path)
        if not backup.exists():
            print(f"[sidekick] warning: backup missing for {target_path}: {backup}", file=sys.stderr)
            continue
        target_path.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(backup, target_path)
        print(f"[sidekick] restored {target_path} from {backup}")
        restored_any = True

    if not restored_any:
        print("[sidekick] nothing was restored; migration state unchanged")
        return 0

    save_state(
        {
            "migration": MIGRATION_ID,
            "status": "rolled_back",
            "rolled_back_at": iso_now(),
            "targets": targets,
        }
    )
    return 0


def main() -> int:
    parser = argparse.ArgumentParser(description="Scrub legacy Sidekick user-hook entries with rollback support.")
    parser.add_argument("--rollback", action="store_true", help="Restore the last scrubbed user hook files from backup.")
    parser.add_argument("--force", action="store_true", help="Re-run the scrub even if a prior state exists.")
    args = parser.parse_args()

    if args.rollback:
        return rollback_migration()
    return apply_migration(force=args.force)


if __name__ == "__main__":
    raise SystemExit(main())
