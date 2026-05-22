#!/usr/bin/env python3
"""Render a host-specific Sidekick skill bundle from the canonical skills tree."""

from __future__ import annotations

import argparse
import pathlib
import shutil

HOST_REPLACEMENTS = {
    "claude": [
        ("${SIDEKICK_HOST_HOME}", "${HOME}/.claude"),
        ("$SIDEKICK_HOST_HOME", "$HOME/.claude"),
        ("SIDEKICK_HOST_SESSION_ID", "CLAUDE_SESSION_ID"),
        ("SIDEKICK_HOST_PROJECT_DIR", "CLAUDE_PROJECT_DIR"),
        ("SIDEKICK_HOST_PLUGIN_ROOT", "CLAUDE_PLUGIN_ROOT"),
    ],
    "codex": [
        ("${SIDEKICK_HOST_HOME}", "${HOME}/.codex"),
        ("$SIDEKICK_HOST_HOME", "$HOME/.codex"),
        ("SIDEKICK_HOST_SESSION_ID", "CODEX_THREAD_ID"),
        ("SIDEKICK_HOST_PROJECT_DIR", "CODEX_PROJECT_DIR"),
        ("SIDEKICK_HOST_PLUGIN_ROOT", "CODEX_PLUGIN_ROOT"),
    ],
}


def rewrite_file(path: pathlib.Path, agent: str) -> bool:
    try:
        text = path.read_text(encoding="utf-8")
    except UnicodeDecodeError:
        return False

    updated = text
    for old, new in HOST_REPLACEMENTS[agent]:
        updated = updated.replace(old, new)

    if updated == text:
        return False

    path.write_text(updated, encoding="utf-8")
    return True


def sanitize_root(root: pathlib.Path, agent: str) -> None:
    for path in sorted(root.rglob("*")):
        if path.is_file() and not path.is_symlink():
            rewrite_file(path, agent)


def render_bundle(source_root: pathlib.Path, dest_root: pathlib.Path, agent: str) -> None:
    if not source_root.is_dir():
        raise SystemExit(f"source root missing: {source_root}")

    if dest_root.exists() or dest_root.is_symlink():
        if dest_root.is_dir() and not dest_root.is_symlink():
            shutil.rmtree(dest_root)
        else:
            dest_root.unlink()

    dest_root.parent.mkdir(parents=True, exist_ok=True)
    shutil.copytree(source_root, dest_root, symlinks=False)
    sanitize_root(dest_root, agent)


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("mode", choices=("render", "sanitize"))
    parser.add_argument("--agent", required=True, choices=("claude", "codex"))
    parser.add_argument("--source-root")
    parser.add_argument("--dest-root")
    parser.add_argument("--root")
    args = parser.parse_args()

    if args.mode == "render":
        if not args.source_root or not args.dest_root:
            parser.error("render mode requires --source-root and --dest-root")
        render_bundle(pathlib.Path(args.source_root), pathlib.Path(args.dest_root), args.agent)
        return 0

    if not args.root:
        parser.error("sanitize mode requires --root")
    sanitize_root(pathlib.Path(args.root), args.agent)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
