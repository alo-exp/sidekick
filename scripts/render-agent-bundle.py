#!/usr/bin/env python3
"""Render a host-specific Sidekick skill bundle from the canonical skills tree."""

from __future__ import annotations

import argparse
import pathlib
import shutil
import tempfile

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


def host_alias_replacements(agent: str) -> list[tuple[str, str]]:
    return [
        (
            "New installs invoke /forge from skills/forge/SKILL.md.",
            "New installs invoke /forge from the generated host skill at "
            "forge/SKILL.md.",
        ),
        (
            "[`skills/forge/SKILL.md`](./forge/SKILL.md)",
            "[`forge/SKILL.md`](./forge/SKILL.md)",
        ),
        (
            "`skills/forge/SKILL.md`",
            f"`forge/SKILL.md` in this generated {agent} skill root "
            f"(`agents/{agent}/forge/SKILL.md` in the repository)",
        ),
        (
            "Prefer skills/codex-delegate/SKILL.md.",
            "Prefer the generated host skill at codex-delegate/SKILL.md.",
        ),
        (
            "[`skills/codex-delegate/SKILL.md`](./codex-delegate/SKILL.md)",
            "[`codex-delegate/SKILL.md`](./codex-delegate/SKILL.md)",
        ),
        (
            "`skills/codex-delegate/SKILL.md`",
            f"`codex-delegate/SKILL.md` in this generated {agent} skill root "
            f"(`agents/{agent}/codex-delegate/SKILL.md` in the repository)",
        ),
        (
            "`skills/forge.md`",
            f"`forge.md` in this generated {agent} skill root "
            f"(`agents/{agent}/forge.md` in the repository)",
        ),
        (
            "`skills/forge-stop/SKILL.md`",
            f"`forge-stop/SKILL.md` in this generated {agent} skill root "
            f"(`agents/{agent}/forge-stop/SKILL.md` in the repository)",
        ),
        (
            "`skills/codex-stop/SKILL.md`",
            f"`codex-stop/SKILL.md` in this generated {agent} skill root "
            f"(`agents/{agent}/codex-stop/SKILL.md` in the repository)",
        ),
        (
            "Prefer skills/kay-delegate/SKILL.md.",
            "Prefer the generated host skill at kay-delegate/SKILL.md.",
        ),
        (
            "[`skills/kay-delegate/SKILL.md`](./kay-delegate/SKILL.md)",
            "[`kay-delegate/SKILL.md`](./kay-delegate/SKILL.md)",
        ),
        (
            "`skills/kay-delegate/SKILL.md`",
            f"`kay-delegate/SKILL.md` in this generated {agent} skill root "
            f"(`agents/{agent}/kay-delegate/SKILL.md` in the repository)",
        ),
        (
            "`skills/kay-stop/SKILL.md`",
            f"`kay-stop/SKILL.md` in this generated {agent} skill root "
            f"(`agents/{agent}/kay-stop/SKILL.md` in the repository)",
        ),
    ]


def host_logic_replacements(agent: str) -> list[tuple[str, str]]:
    host_home_blocks = [
        (
            """if [[ -z "${SIDEKICK_HOST_HOME:-}" ]]; then
  if [[ -n "${CODEX_HOME:-${CODEX_THREAD_ID:-${CODEX_PROJECT_DIR:-${CODEX_PLUGIN_ROOT:-}}}}" ]]; then
    SIDEKICK_HOST_HOME="${CODEX_HOME:-${HOME}/.codex}"
  elif [[ -n "${CLAUDE_SESSION_ID:-${CLAUDE_PROJECT_DIR:-${CLAUDE_PLUGIN_ROOT:-}}}" ]]; then
    SIDEKICK_HOST_HOME="${HOME}/.claude"
  else
""",
            "    ",
            "  ",
            "",
        ),
        (
            """   if [[ -z "${SIDEKICK_HOST_HOME:-}" ]]; then
     if [[ -n "${CODEX_HOME:-${CODEX_THREAD_ID:-${CODEX_PROJECT_DIR:-${CODEX_PLUGIN_ROOT:-}}}}" ]]; then
       SIDEKICK_HOST_HOME="${CODEX_HOME:-${HOME}/.codex}"
     elif [[ -n "${CLAUDE_SESSION_ID:-${CLAUDE_PROJECT_DIR:-${CLAUDE_PLUGIN_ROOT:-}}}" ]]; then
       SIDEKICK_HOST_HOME="${HOME}/.claude"
     else
""",
            "       ",
            "     ",
            "   ",
        ),
    ]

    replacements: list[tuple[str, str]] = []
    for host_home_block, echo_indent, inner_fi_indent, outer_fi_indent in host_home_blocks:
        replacements.extend(
            [
                (
                    host_home_block
                    + f'{echo_indent}echo "No host home found for Forge mode"; exit 1\n'
                    + f"{inner_fi_indent}fi\n"
                    + f"{outer_fi_indent}fi\n",
                    "",
                ),
                (
                    host_home_block
                    + f'{echo_indent}echo "No host home found for Kay mode"; exit 1\n'
                    + f"{inner_fi_indent}fi\n"
                    + f"{outer_fi_indent}fi\n",
                    "",
                ),
                (
                    host_home_block
                    + f'{echo_indent}echo "No host home found for Codex mode"; exit 1\n'
                    + f"{inner_fi_indent}fi\n"
                    + f"{outer_fi_indent}fi\n",
                    "",
                ),
            ]
        )

    if agent == "codex":
        replacements.append(
            (
                'SIDEKICK_SESSION="${SIDEKICK_SESSION_ID:-${CODEX_THREAD_ID:-${CODEX_THREAD_ID:-${CLAUDE_SESSION_ID:-${SESSION_ID:-}}}}}"',
                'SIDEKICK_SESSION="${SIDEKICK_SESSION_ID:-${CODEX_THREAD_ID:-${SESSION_ID:-}}}"',
            )
        )
        return replacements

    replacements.append(
        (
            'SIDEKICK_SESSION="${SIDEKICK_SESSION_ID:-${CLAUDE_SESSION_ID:-${CODEX_THREAD_ID:-${CLAUDE_SESSION_ID:-${SESSION_ID:-}}}}}"',
            'SIDEKICK_SESSION="${SIDEKICK_SESSION_ID:-${CLAUDE_SESSION_ID:-${SESSION_ID:-}}}"',
        )
    )
    return replacements


def rewrite_file(path: pathlib.Path, agent: str) -> bool:
    try:
        text = path.read_text(encoding="utf-8")
    except UnicodeDecodeError:
        return False

    updated = text
    for old, new in HOST_REPLACEMENTS[agent]:
        updated = updated.replace(old, new)
    for old, new in host_logic_replacements(agent):
        updated = updated.replace(old, new)
    for old, new in host_alias_replacements(agent):
        updated = updated.replace(old, new)

    if updated == text:
        return False

    path.write_text(updated, encoding="utf-8")
    return True


def sanitize_root(root: pathlib.Path, agent: str) -> None:
    for path in sorted(root.rglob("*")):
        if path.is_file() and not path.is_symlink():
            rewrite_file(path, agent)


def is_relative_to(path: pathlib.Path, parent: pathlib.Path) -> bool:
    try:
        path.relative_to(parent)
    except ValueError:
        return False
    return True


def validate_host_bundle_root(
    target_root: pathlib.Path,
    agent: str,
    purpose: str,
    source_root: pathlib.Path | None = None,
) -> None:
    repo_root = pathlib.Path(__file__).resolve().parents[1]
    home_root = pathlib.Path.home().resolve(strict=False)
    cwd = pathlib.Path.cwd().resolve(strict=False)
    temp_root = pathlib.Path(tempfile.gettempdir()).resolve(strict=False)
    source = source_root.resolve(strict=True) if source_root else None
    target = target_root.resolve(strict=False)

    allowed_repo_dest = (repo_root / "agents" / agent).resolve(strict=False)
    allowed_temp_dest = (
        target.name == agent
        and target.parent.name.startswith("sidekick-agent-render.")
        and target.parent.is_dir()
        and is_relative_to(target.parent, temp_root)
    )
    if target != allowed_repo_dest and not allowed_temp_dest:
        raise SystemExit(
            f"refusing unsafe {purpose} root: "
            f"{target_root} (expected {allowed_repo_dest} or a Sidekick-owned temp dir ending in /{agent})"
        )

    dangerous_exact = {pathlib.Path("/").resolve(strict=False), repo_root, home_root, cwd}
    if source is not None:
        dangerous_exact.add(source)
    if target in dangerous_exact:
        raise SystemExit(f"refusing unsafe {purpose} root: {target_root}")

    if is_relative_to(repo_root, target) or is_relative_to(home_root, target):
        raise SystemExit(f"refusing ancestor {purpose} root: {target_root}")
    if source is not None and is_relative_to(source, target):
        raise SystemExit(f"refusing ancestor {purpose} root: {target_root}")


def validate_render_destination(source_root: pathlib.Path, dest_root: pathlib.Path, agent: str, force: bool) -> None:
    validate_host_bundle_root(dest_root, agent, "render destination", source_root=source_root)
    if (dest_root.exists() or dest_root.is_symlink()) and not force:
        raise SystemExit(f"refusing to replace existing render destination root without --force: {dest_root}")


def render_bundle(source_root: pathlib.Path, dest_root: pathlib.Path, agent: str, force: bool = False) -> None:
    if not source_root.is_dir():
        raise SystemExit(f"source root missing: {source_root}")
    validate_render_destination(source_root, dest_root, agent, force)

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
    parser.add_argument("--force", action="store_true", help="allow replacing an existing render destination")
    args = parser.parse_args()

    if args.mode == "render":
        if not args.source_root or not args.dest_root:
            parser.error("render mode requires --source-root and --dest-root")
        render_bundle(pathlib.Path(args.source_root), pathlib.Path(args.dest_root), args.agent, args.force)
        return 0

    if not args.root:
        parser.error("sanitize mode requires --root")
    root = pathlib.Path(args.root)
    validate_host_bundle_root(root, args.agent, "sanitize")
    sanitize_root(root, args.agent)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
