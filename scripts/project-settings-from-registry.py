#!/usr/bin/env python3
"""Project registry manifests and non-secret policy onto settings.json.

Current scope:
- replace settings.json:hooks from registry/hooks-manifest.json
- overlay non-secret env, MCP command, permission guards, and selected top-level settings
  (statusLine, enabledPlugins, skills) from registry/settings-policy.json

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
SETTINGS_POLICY_PATH = ROOT / "registry" / "settings-policy.json"


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


def validate_settings_policy(policy: dict[str, Any]) -> None:
    if policy.get("version") != 1:
        raise ValueError("settings-policy version must be 1")
    if policy.get("status") != "active":
        raise ValueError("settings-policy status must be active")


def append_missing(items: list[Any], required: list[Any]) -> list[Any]:
    projected = list(items)
    for item in required:
        if item not in projected:
            projected.append(item)
    return projected


def project_env(projected: dict[str, Any], policy: dict[str, Any]) -> None:
    env_policy = policy.get("env", {})
    env = copy.deepcopy(projected.get("env", {}))
    env.update(env_policy.get("required_exact", {}))

    path_prefix = env_policy.get("path_must_start_with")
    current_path = str(env.get("PATH", ""))
    if path_prefix and current_path and not current_path.startswith(path_prefix):
        env["PATH"] = f"{path_prefix}:{current_path}"
    elif path_prefix and not current_path:
        env["PATH"] = str(path_prefix)
    projected["env"] = env


def project_mcp_servers(projected: dict[str, Any], policy: dict[str, Any]) -> None:
    required_servers = policy.get("mcp", {}).get("settings_json_required_servers", {})
    servers = copy.deepcopy(projected.get("mcpServers", {}))
    for name, required in required_servers.items():
        if name not in servers:
            raise ValueError(f"settings.json missing MCP server required by policy: {name}")
        server = copy.deepcopy(servers[name])
        if "command" in required:
            server["command"] = required["command"]
        env = server.get("env", {})
        for key in required.get("required_env_keys", []):
            if key not in env:
                raise ValueError(f"settings.json MCP server {name} missing env key: {key}")
        servers[name] = server
    projected["mcpServers"] = servers


def project_permissions(projected: dict[str, Any], policy: dict[str, Any]) -> None:
    permission_policy = policy.get("permissions", {})
    permissions = copy.deepcopy(projected.get("permissions", {}))
    if "default_mode" in permission_policy:
        permissions["defaultMode"] = permission_policy["default_mode"]
    permissions["additionalDirectories"] = append_missing(
        permissions.get("additionalDirectories", []),
        permission_policy.get("required_additional_directories", []),
    )
    permissions["allow"] = append_missing(
        permissions.get("allow", []),
        permission_policy.get("required_allow", []),
    )
    permissions["deny"] = append_missing(
        permissions.get("deny", []),
        permission_policy.get("required_deny", []),
    )
    projected["permissions"] = permissions


def project_top_level_settings(
    original_settings: dict[str, Any],
    projected: dict[str, Any],
    policy: dict[str, Any],
) -> None:
    settings_scope = policy.get("projection_scope", {}).get("settings_json", [])
    for key in ["statusLine", "enabledPlugins", "skills"]:
        if key in settings_scope and key in original_settings:
            projected[key] = copy.deepcopy(original_settings[key])


def project_settings(
    settings: dict[str, Any],
    hook_manifest: dict[str, Any],
    settings_policy: dict[str, Any],
) -> dict[str, Any]:
    validate_hook_manifest(hook_manifest)
    validate_settings_policy(settings_policy)
    projected = copy.deepcopy(settings)
    projected["hooks"] = copy.deepcopy(hook_manifest["hooks"])
    project_env(projected, settings_policy)
    project_mcp_servers(projected, settings_policy)
    project_permissions(projected, settings_policy)
    project_top_level_settings(settings, projected, settings_policy)
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
    settings_policy = load_json(SETTINGS_POLICY_PATH)
    projected = project_settings(settings, hook_manifest, settings_policy)

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
