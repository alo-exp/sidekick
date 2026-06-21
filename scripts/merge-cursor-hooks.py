#!/usr/bin/env python3
"""Idempotently merge Sidekick hooks from cursor-hooks.json into ~/.cursor/hooks.json."""

from __future__ import annotations

import json
import os
import pathlib
import re
import shutil
import sys

install_path = sys.argv[1] if len(sys.argv) > 1 else ""
if not install_path:
    raise SystemExit("usage: merge-cursor-hooks.py <sidekick_install_path>")

hooks_src = os.path.join(install_path, "hooks", "cursor-hooks.json")
settings_path = os.path.join(os.path.expanduser("~"), ".cursor", "hooks.json")


def stable_install_path(raw_install_path: str) -> str:
    match = re.match(r"^(.*?/sidekick)/(\d+\.\d+\.\d+)$", raw_install_path)
    if not match:
        return raw_install_path
    versioned_path = pathlib.Path(raw_install_path)
    alias_path = pathlib.Path(match.group(1)) / "current"
    try:
        alias_path.parent.mkdir(parents=True, exist_ok=True)
        if alias_path.exists() or alias_path.is_symlink():
            if alias_path.is_dir() and not alias_path.is_symlink():
                shutil.rmtree(alias_path)
            else:
                alias_path.unlink()
        alias_path.symlink_to(versioned_path)
        return str(alias_path)
    except OSError:
        return raw_install_path


def resolve_command(command: str, root: str) -> str:
  resolved = command
  resolved = resolved.replace("${CURSOR_PLUGIN_ROOT:-${SIDEKICK_PLUGIN_ROOT:-}}", root)
  resolved = resolved.replace("${CURSOR_PLUGIN_ROOT}", root)
  resolved = resolved.replace("${SIDEKICK_PLUGIN_ROOT}", root)
  resolved = resolved.replace("${ROOT}", root)
  resolved = re.sub(r'^ROOT="[^"]*";\s*', "", resolved)
  return resolved


install_path = stable_install_path(install_path)
with open(hooks_src, encoding="utf-8") as handle:
    src = json.load(handle)

sidekick_hooks = src.get("hooks", {})
SIDEKICK_HOOK_RE = re.compile(r"/sidekick/[^/]+/hooks/")


def is_stale_sidekick_hook(entry: dict) -> bool:
    command = entry.get("command", "")
    if "${CURSOR_PLUGIN_ROOT}/hooks/" in command or "${SIDEKICK_PLUGIN_ROOT}/hooks/" in command:
        return True
    return bool(SIDEKICK_HOOK_RE.search(command)) and install_path not in command


def hook_script_basename(command: str) -> str:
    match = re.search(r"/hooks/([^/\" ]+\.sh)", command)
    return match.group(1) if match else ""


def should_replace_sidekick_hook(existing: dict, merged: dict) -> bool:
    old_cmd = existing.get("command", "")
    new_cmd = merged.get("command", "")
    if old_cmd == new_cmd:
        return True
    old_base = hook_script_basename(old_cmd)
    new_base = hook_script_basename(new_cmd)
    if not old_base or old_base != new_base:
        return False
    if "/sidekick/" in old_cmd or is_stale_sidekick_hook(existing):
        return True
    return old_base in {
        "codex-delegation-enforcer.sh",
        "codex-progress-surface.sh",
        "cursor-session-bootstrap.sh",
        "cursor-session-end.sh",
    }


if os.path.exists(settings_path):
    with open(settings_path, encoding="utf-8") as handle:
        settings = json.load(handle)
else:
    settings = {"version": 1, "hooks": {}}

settings.setdefault("version", 1)
existing_hooks = settings.setdefault("hooks", {})

for event, entries in list(existing_hooks.items()):
    if not isinstance(entries, list):
        continue
    cleaned = [entry for entry in entries if not is_stale_sidekick_hook(entry)]
    if cleaned:
        existing_hooks[event] = cleaned
    else:
        del existing_hooks[event]

for event, entries in sidekick_hooks.items():
    event_list = existing_hooks.setdefault(event, [])
    for new_entry in entries:
        merged_entry = dict(new_entry)
        merged_entry["command"] = resolve_command(new_entry.get("command", ""), install_path)
        new_cmd = merged_entry.get("command", "")
        replaced = False
        for index, entry in enumerate(event_list):
            if should_replace_sidekick_hook(entry, merged_entry):
                event_list[index] = merged_entry
                replaced = True
                break
        if not replaced:
            event_list.append(merged_entry)

pathlib.Path(settings_path).parent.mkdir(parents=True, exist_ok=True)
with open(settings_path, "w", encoding="utf-8") as handle:
    json.dump(settings, handle, indent=2)
    handle.write("\n")

print("Sidekick hooks registered in ~/.cursor/hooks.json")
