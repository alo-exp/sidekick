#!/usr/bin/env python3
"""Render kit/_chrome templates into a consumer site's site/_chrome/ from site.config.json."""

from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path

REPO = Path(__file__).resolve().parents[1]
SCRIPT_DIR = Path(__file__).resolve().parent


def kit_chrome_dir(project_root: Path) -> Path:
    candidates = (
        SCRIPT_DIR / "chrome-templates",
        REPO / "kit" / "_chrome",
        project_root / "site" / "_chrome",
    )
    for path in candidates:
        if (path / "nav.html").is_file():
            return path
    raise FileNotFoundError("chrome templates not found — re-run bootstrap-alo-site.sh")


def load_config(project_root: Path) -> dict:
    for candidate in (project_root / "site.config.json", project_root / "site" / "site.config.json"):
        if candidate.is_file():
            return json.loads(candidate.read_text(encoding="utf-8"))
    raise FileNotFoundError(f"site.config.json not found under {project_root}")


def render_template(template: str, root: str, config: dict) -> str:
    nav_links = config.get("nav_links_html", "").replace("{{ROOT}}", root)
    alpha = config.get("alpha_badge_html", "")
    out = template
    replacements = {
        "ROOT": root,
        "PRODUCT_NAME": config.get("product_name", "Product"),
        "LOGO_PATH": config.get("logo_path", "logo.png"),
        "GITHUB_URL": config.get("github_url", "https://github.com/alo-exp"),
        "COPYRIGHT_YEAR": str(config.get("copyright_year", "2026")),
        "ALPHA_BADGE": alpha,
        "NAV_LINKS": nav_links,
        "BREADCRUMB": "{{BREADCRUMB}}",
        "HELP_LINKS": "{{HELP_LINKS}}",
        "HELP_SEARCH": "{{HELP_SEARCH}}",
    }
    for key, value in replacements.items():
        out = out.replace(f"{{{{{key}}}}}", value)
    return out


def main() -> int:
    parser = argparse.ArgumentParser(description="Render Ālo chrome partials from site.config.json")
    parser.add_argument("--project", type=Path, required=True, help="Consumer project root (contains site.config.json)")
    args = parser.parse_args()
    project = args.project.resolve()
    site = project / "site"
    chrome_out = site / "_chrome"
    chrome_out.mkdir(parents=True, exist_ok=True)

    config = load_config(project)
    chrome_src = kit_chrome_dir(project)
    for name in ("nav.html", "footer.html", "help-subnav.html"):
        template = (chrome_src / name).read_text(encoding="utf-8")
        rendered = render_template(template, "{{ROOT}}", config)
        (chrome_out / name).write_text(rendered, encoding="utf-8")
        print(f"wrote {chrome_out / name}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
