#!/usr/bin/env python3
"""Project registry manifests onto settings.json.

Current scope: replace settings.json:hooks from registry/hooks-manifest.json.
The default command prints the projected settings JSON to stdout. Use --check to
verify semantic equality with the current settings.json, or --write to update it.
"""

from __future__ import annotations

import argparse
import copy
import json
import sys
from pathlib import Path
from typing import Any


ROOT = Path(__file__).resolve().parents[1]
SETTINGS_PATH = ROOT / "settings.json"
HOOK_MANIFEST_PATH = ROOT / "registry" / "hooks-manifest.json"


def load_json(path: Path) -> dict[str, Any]:
    return json.loads(path.read_text(encoding="utf-8"))


def hook_count(hooks: dict[str, list[dict[str, Any]]]) -> int:
    return sum(len(group.get("hooks", [])) for groups in hooks.values() for group in groups)


def validate_hook_manifest(manifest: dict[str, Any]) -> None:
    if manifest.get("projection_target") != "settings.json:hooks":
        raise ValueError("hooks-manifest projection_target must be settings.json:hooks")
    hooks = manifest.get("hooks")
    if not isinstance(hooks, dict):
        raise ValueError("hooks-manifest hooks must be an object")
    if manifest.get("hook_count") != hook_count(hooks):
        raise ValueError("hooks-manifest hook_count does not match hooks payload")


def project_settings(settings: dict[str, Any], hook_manifest: dict[str, Any]) -> dict[str, Any]:
    validate_hook_manifest(hook_manifest)
    projected = copy.deepcopy(settings)
    projected["hooks"] = copy.deepcopy(hook_manifest["hooks"])
    return projected


def render_json(data: dict[str, Any]) -> str:
    return json.dumps(data, ensure_ascii=False, indent=2) + "\n"


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--check", action="store_true", help="fail if projected settings differ from settings.json")
    parser.add_argument("--write", action="store_true", help="write projected settings back to settings.json")
    args = parser.parse_args()

    settings = load_json(SETTINGS_PATH)
    hook_manifest = load_json(HOOK_MANIFEST_PATH)
    projected = project_settings(settings, hook_manifest)

    if args.check:
        if projected != settings:
            print("settings.json differs from registry projection", file=sys.stderr)
            return 1
        return 0

    rendered = render_json(projected)
    if args.write:
        SETTINGS_PATH.write_text(rendered, encoding="utf-8")
    else:
        print(rendered, end="")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
