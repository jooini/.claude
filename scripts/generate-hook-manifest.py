#!/usr/bin/env python3
"""Generate a full hook manifest from settings.json hooks."""

from __future__ import annotations

import argparse
import json
from pathlib import Path
from typing import Any


ROOT = Path(__file__).resolve().parents[1]
OUTPUT_PATH = ROOT / "registry" / "hooks-manifest.json"


def load_json(path: Path) -> dict[str, Any]:
    return json.loads(path.read_text(encoding="utf-8"))


def hook_count(hooks: dict[str, list[dict[str, Any]]]) -> int:
    return sum(len(group.get("hooks", [])) for groups in hooks.values() for group in groups)


def event_matrix(hooks: dict[str, list[dict[str, Any]]]) -> list[dict[str, Any]]:
    matrix = []
    for event, groups in hooks.items():
        matrix.append(
            {
                "event": event,
                "group_count": len(groups),
                "hook_count": sum(len(group.get("hooks", [])) for group in groups),
                "matchers": [group.get("matcher", "*") for group in groups],
            }
        )
    return matrix


def generate_manifest() -> dict[str, Any]:
    settings = load_json(ROOT / "settings.json")
    hooks = settings.get("hooks", {})
    return {
        "version": 1,
        "status": "transitional_full_manifest",
        "generated_from": "settings.json:hooks",
        "projection_target": "settings.json:hooks",
        "description": (
            "Full hook runtime manifest. During transition this is generated from "
            "settings.json; once stable it can become the registry source used to "
            "project settings.json hooks."
        ),
        "event_count": len(hooks),
        "hook_count": hook_count(hooks),
        "event_matrix": event_matrix(hooks),
        "hooks": hooks,
    }


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--write", action="store_true", help=f"write {OUTPUT_PATH.relative_to(ROOT)}")
    args = parser.parse_args()

    manifest = generate_manifest()
    rendered = json.dumps(manifest, ensure_ascii=False, indent=2) + "\n"
    if args.write:
        OUTPUT_PATH.write_text(rendered, encoding="utf-8")
    else:
        print(rendered, end="")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
