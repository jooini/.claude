#!/usr/bin/env python3
"""Generate a complete hook inventory from settings.json."""

from __future__ import annotations

import argparse
import json
import os
import re
import shlex
from pathlib import Path
from typing import Any


ROOT = Path(__file__).resolve().parents[1]
OUTPUT_PATH = ROOT / "registry" / "hooks-inventory.json"
TIMEOUT_POLICY_PATH = ROOT / "registry" / "hook-timeout-policy.json"
WRAPPER_DEFINITIONS_PATH = ROOT / "registry" / "hook-wrapper-definitions.json"


def load_json(path: Path) -> dict[str, Any]:
    return json.loads(path.read_text(encoding="utf-8"))


def load_optional_json(path: Path) -> dict[str, Any]:
    if not path.exists():
        return {}
    return load_json(path)


def normalize_matcher(matcher: str | None) -> str:
    if matcher is None:
        return "*"
    return matcher


def script_from_command(command: str) -> str | None:
    try:
        parts = shlex.split(command)
    except ValueError:
        parts = command.split()
    candidates = []
    for part in parts:
        expanded = os.path.expandvars(part)
        expanded = os.path.expanduser(expanded)
        candidates.append(expanded)
    for candidate in candidates:
        if candidate.endswith(".sh") or "/hooks/" in candidate:
            return candidate
    return candidates[0] if candidates else None


def relative_to_root(path: str | None) -> str | None:
    if not path:
        return None
    candidate = Path(path)
    try:
        return str(candidate.relative_to(ROOT))
    except ValueError:
        return path


def read_script_text(path: str | None) -> str:
    if not path:
        return ""
    candidate = Path(path)
    if not candidate.exists() or not candidate.is_file():
        return ""
    try:
        return candidate.read_text(encoding="utf-8", errors="ignore")
    except OSError:
        return ""


def infer_llm_providers(command: str, script_text: str) -> list[str]:
    haystack = f"{command}\n{script_text}".lower()
    providers = []
    patterns = {
        "gemini_or_agy": [
            r"\bgemini\b",
            r"\bagy\b",
            r"llm-call\.sh[^\n]*\bgemini\b",
            r"llm-call\.sh[^\n]*\bagy\b",
            "gemini_cli",
            "gemini-wrapped",
            "ask-gemini",
        ],
        "codex": [
            "codex exec",
            "codex:",
            "ask-codex",
            r"llm-call\.sh[^\n]*\bcodex\b",
        ],
        "ollama": [
            "ollama",
            "leonard.local:11434",
            "/api/tags",
            r"llm-call\.sh[^\n]*\b(ini|ollama|gemma|qwen)\b",
        ],
        "gemma": [
            "gemma",
            "ask-gemma",
            r"llm-call\.sh[^\n]*\b(gemma|ini)\b",
        ],
        "qwen_ini": [
            "/ini",
            "qwen",
            "qwen3",
            r"llm-call\.sh[^\n]*\b(ini|qwen)\b",
        ],
    }
    for provider, provider_patterns in patterns.items():
        if any(re.search(pattern, haystack) for pattern in provider_patterns):
            providers.append(provider)
    return providers


def infer_side_effects(command: str, script_text: str) -> list[str]:
    haystack = f"{command}\n{script_text}".lower()
    side_effects = []
    checks = {
        "cache_write": ["cache/", ".claude/cache", "cache_dir", "output_file", "state_file"],
        "outcome_log": ["outcome_log"],
        "notification": ["osascript", "display notification", " say ", "afplay", "terminal-notifier"],
        "audio": ["afplay", "say -v"],
        "git": ["git ", "git-"],
        "network": ["curl ", "gh ", "ssh ", "npx ", "npm "],
        "rag_index": ["rag-auto-index", "rag-ingest", "lancedb", "local-rag"],
        "vault_write": ["obsidian", "vault", "weaversbrain"],
        "taskhub": ["taskhub", "taskcreate", "taskupdate"],
        "metrics": ["metrics", "usage", "trace", "jsonl"],
        "mcp": ["mcp"],
        "agent_build": ["build-agents", "agent-build"],
        "badge": ["badge", "iterm"],
    }
    for side_effect, needles in checks.items():
        if any(needle in haystack for needle in needles):
            side_effects.append(side_effect)
    return side_effects


def classify_hook(event: str, matcher: str, command: str) -> dict[str, Any]:
    lower_command = command.lower()
    priority = "P2"
    blocking = event == "PreToolUse"
    failure_mode = "fail-open"

    if event in {"SessionStart", "UserPromptSubmit"} and "router" in lower_command:
        priority = "P0"
    elif event == "PreToolUse":
        priority = "P1"
        failure_mode = "may-block"
        if any(
            keyword in lower_command
            for keyword in [
                "danger",
                "block",
                "no-coauthor",
                "korean-block",
                "delegation-enforcer",
                "gemini-prescan-enforcer",
                "commit-korean-check",
            ]
        ):
            priority = "P0"
            failure_mode = "fail-closed-or-blocking-warning"
    elif event == "PostToolUse":
        blocking = False
        if any(
            keyword in lower_command
            for keyword in [
                "error",
                "gemma-error",
                "decision",
                "metrics",
                "dependency",
                "rag-auto-index",
            ]
        ):
            priority = "P1"
        else:
            priority = "P2"
    elif event == "Stop":
        blocking = False
        if any(keyword in lower_command for keyword in ["pipeline-check", "closure-gate"]):
            priority = "P0"
            failure_mode = "warn-or-gate"
        elif any(keyword in lower_command for keyword in ["summary", "learning", "budget"]):
            priority = "P1"
    elif event == "SessionEnd":
        blocking = False
        priority = "P2"
    elif event == "Notification":
        blocking = False
        priority = "P3"
    elif event == "PreCompact":
        blocking = False
        priority = "P2"

    return {
        "priority": priority,
        "blocking": blocking,
        "failure_mode": failure_mode,
        "classification_source": "derived",
    }


def priority_rank(priority: str) -> int:
    return {"P0": 0, "P1": 1, "P2": 2, "P3": 3}.get(priority, 9)


def merge_priorities(priorities: list[str]) -> str:
    if not priorities:
        return "P2"
    return sorted(priorities, key=priority_rank)[0]


def load_active_wrapper_definitions() -> dict[str, dict[str, Any]]:
    data = load_optional_json(WRAPPER_DEFINITIONS_PATH)
    return {
        definition["id"]: definition
        for definition in data.get("definitions", [])
        if definition.get("state") == "active" and definition.get("id")
    }


def wrapper_id_from_command(command: str) -> str | None:
    if "hook-wrapper-runner.py" not in command:
        return None
    try:
        parts = shlex.split(command)
    except ValueError:
        parts = command.split()
    for index, part in enumerate(parts):
        if part.endswith("hook-wrapper-runner.py") and index + 1 < len(parts):
            return parts[index + 1]
    return None


def policy_lookup(policy: dict[str, Any]) -> dict[tuple[str, str, str], dict[str, Any]]:
    lookup: dict[tuple[str, str, str], dict[str, Any]] = {}
    for item in policy.get("required_hooks", []):
        key = (item["event"], item["matcher"], item["command_contains"])
        lookup[key] = item
    return lookup


def matching_policy(
    lookup: dict[tuple[str, str, str], dict[str, Any]],
    event: str,
    matcher: str,
    command: str,
) -> dict[str, Any] | None:
    for (policy_event, policy_matcher, command_contains), item in lookup.items():
        if policy_event != event:
            continue
        if policy_matcher != "*" and policy_matcher != matcher:
            continue
        if command_contains in command:
            return item
    return None


def wrapper_metadata(
    definition: dict[str, Any] | None,
    policy_items: dict[tuple[str, str, str], dict[str, Any]],
) -> dict[str, Any] | None:
    if not definition:
        return None
    event = str(definition.get("event", ""))
    matcher = normalize_matcher(definition.get("matcher"))
    providers: set[str] = set()
    side_effects: set[str] = set()
    priorities: list[str] = []
    blocking = False
    child_scripts = []
    child_hook_ids = []

    for step in definition.get("execution", []):
        command = str(step.get("command", ""))
        script_path = script_from_command(command)
        relative_script = relative_to_root(script_path)
        script_text = read_script_text(script_path)
        providers.update(infer_llm_providers(command, script_text))
        side_effects.update(infer_side_effects(command, script_text))
        child_scripts.append(relative_script)
        child_hook_ids.append(step.get("hook_id"))
        classification = classify_hook(event, matcher, command)
        policy_item = matching_policy(policy_items, event, matcher, command)
        if policy_item:
            classification = {
                "priority": policy_item["priority"],
                "blocking": policy_item["blocking"],
                "failure_mode": policy_item["failure_mode"],
                "classification_source": "hook-policy",
            }
        priorities.append(classification["priority"])
        blocking = blocking or bool(classification["blocking"])

    return {
        "wrapped_hook_count": len(definition.get("execution", [])),
        "wrapped_hook_ids": child_hook_ids,
        "wrapped_scripts": child_scripts,
        "llm_providers": sorted(providers),
        "side_effects": sorted(side_effects),
        "classification": {
            "priority": merge_priorities(priorities),
            "blocking": blocking,
            "failure_mode": "wrapped-hooks-preserved",
            "classification_source": "hook-wrapper-definitions",
        },
    }


def timeout_script_lookup(policy: dict[str, Any]) -> dict[str, dict[str, Any]]:
    return {
        item["script"]: item
        for item in policy.get("script_overrides", [])
        if "script" in item and "timeout_seconds" in item
    }


def timeout_rule_matches(
    rule: dict[str, Any],
    *,
    event: str,
    priority: str,
    blocking: bool,
    async_flag: bool,
    calls_llm: bool,
) -> bool:
    checks = {
        "event": event,
        "priority": priority,
        "blocking": blocking,
        "async": async_flag,
        "calls_llm": calls_llm,
    }
    for key, value in checks.items():
        if key in rule and rule[key] != value:
            return False
    return True


def matching_timeout_policy(
    policy: dict[str, Any],
    script_lookup: dict[str, dict[str, Any]],
    *,
    relative_script: str | None,
    event: str,
    priority: str,
    blocking: bool,
    async_flag: bool,
    calls_llm: bool,
) -> dict[str, Any] | None:
    if relative_script and relative_script in script_lookup:
        item = dict(script_lookup[relative_script])
        item["source"] = "hook-timeout-policy:script"
        return item

    for rule in policy.get("default_timeout_rules", []):
        if timeout_rule_matches(
            rule,
            event=event,
            priority=priority,
            blocking=blocking,
            async_flag=async_flag,
            calls_llm=calls_llm,
        ):
            item = dict(rule)
            item["source"] = f"hook-timeout-policy:default:{rule.get('name', 'unnamed')}"
            return item
    return None


def resolve_timeout(settings_timeout: Any, timeout_item: dict[str, Any] | None) -> dict[str, Any]:
    policy_timeout = timeout_item.get("timeout_seconds") if timeout_item else None
    if settings_timeout is not None:
        return {
            "effective_timeout_seconds": settings_timeout,
            "timeout_source": "settings",
            "timeout_policy_seconds": policy_timeout,
            "timeout_policy_source": timeout_item.get("source") if timeout_item else None,
            "timeout_policy_reason": timeout_item.get("reason") if timeout_item else None,
        }
    if policy_timeout is not None:
        return {
            "effective_timeout_seconds": policy_timeout,
            "timeout_source": timeout_item.get("source"),
            "timeout_policy_seconds": policy_timeout,
            "timeout_policy_source": timeout_item.get("source"),
            "timeout_policy_reason": timeout_item.get("reason"),
        }
    return {
        "effective_timeout_seconds": None,
        "timeout_source": "missing",
        "timeout_policy_seconds": None,
        "timeout_policy_source": None,
        "timeout_policy_reason": None,
    }


def count_by_key(items: list[dict[str, Any]], key: str) -> dict[str, int]:
    counts: dict[str, int] = {}
    for item in items:
        value = str(item.get(key))
        counts[value] = counts.get(value, 0) + 1
    return dict(sorted(counts.items()))


def generate_inventory() -> dict[str, Any]:
    settings = load_json(ROOT / "settings.json")
    policy = load_json(ROOT / "registry" / "hook-policy.json")
    timeout_policy = load_optional_json(TIMEOUT_POLICY_PATH)
    policy_items = policy_lookup(policy)
    active_wrappers = load_active_wrapper_definitions()
    timeout_policy_items = timeout_script_lookup(timeout_policy)
    hooks = []
    order = 0

    for event, groups in settings.get("hooks", {}).items():
        for group_index, group in enumerate(groups):
            matcher = normalize_matcher(group.get("matcher"))
            for hook_index, hook in enumerate(group.get("hooks", [])):
                command = hook.get("command", "")
                script_path = script_from_command(command)
                relative_script = relative_to_root(script_path)
                absolute_script = Path(script_path) if script_path else None
                exists = bool(absolute_script and absolute_script.exists())
                executable = bool(absolute_script and absolute_script.exists() and os.access(absolute_script, os.X_OK))
                script_text = read_script_text(script_path)
                wrapper_id = wrapper_id_from_command(command)
                wrapper_info = wrapper_metadata(active_wrappers.get(wrapper_id), policy_items)
                llm_providers = (
                    wrapper_info["llm_providers"]
                    if wrapper_info
                    else infer_llm_providers(command, script_text)
                )
                classification = classify_hook(event, matcher, command)
                policy_item = matching_policy(policy_items, event, matcher, command)
                if policy_item:
                    classification = {
                        "priority": policy_item["priority"],
                        "blocking": policy_item["blocking"],
                        "failure_mode": policy_item["failure_mode"],
                        "classification_source": "hook-policy",
                    }
                elif wrapper_info:
                    classification = wrapper_info["classification"]
                async_flag = bool(hook.get("async", False))
                calls_llm = bool(llm_providers)
                timeout_item = matching_timeout_policy(
                    timeout_policy,
                    timeout_policy_items,
                    relative_script=relative_script,
                    event=event,
                    priority=classification["priority"],
                    blocking=classification["blocking"],
                    async_flag=async_flag,
                    calls_llm=calls_llm,
                )
                timeout = resolve_timeout(hook.get("timeout"), timeout_item)

                hooks.append(
                    {
                        "id": f"{event}:{group_index}:{hook_index}",
                        "order": order,
                        "event": event,
                        "matcher": matcher,
                        "command": command,
                        "type": hook.get("type", "command"),
                        "async": async_flag,
                        "timeout_seconds": hook.get("timeout"),
                        **timeout,
                        "status_message": hook.get("statusMessage"),
                        "script": relative_script,
                        "script_exists": exists,
                        "script_executable": executable,
                        "calls_llm": calls_llm,
                        "llm_providers": llm_providers,
                        "side_effects": (
                            wrapper_info["side_effects"]
                            if wrapper_info
                            else infer_side_effects(command, script_text)
                        ),
                        "wrapped_hook_count": wrapper_info["wrapped_hook_count"] if wrapper_info else 0,
                        "wrapped_hook_ids": wrapper_info["wrapped_hook_ids"] if wrapper_info else [],
                        "wrapped_scripts": wrapper_info["wrapped_scripts"] if wrapper_info else [],
                        **classification,
                    }
                )
                order += 1

    events = sorted({hook["event"] for hook in hooks})
    priority_counts = count_by_key(hooks, "priority")
    timeout_source_counts = count_by_key(hooks, "timeout_source")
    side_effect_count = sum(len(hook.get("side_effects", [])) for hook in hooks)
    return {
        "version": 1,
        "generated_from": "settings.json",
        "hook_count": len(hooks),
        "event_count": len(events),
        "llm_hook_count": sum(1 for hook in hooks if hook.get("calls_llm")),
        "timeout_missing_count": sum(1 for hook in hooks if hook.get("timeout_seconds") is None),
        "effective_timeout_missing_count": sum(
            1 for hook in hooks if hook.get("effective_timeout_seconds") is None
        ),
        "side_effect_count": side_effect_count,
        "priority_counts": priority_counts,
        "timeout_source_counts": timeout_source_counts,
        "events": events,
        "hooks": hooks,
    }


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--write", action="store_true", help=f"write {OUTPUT_PATH.relative_to(ROOT)}")
    args = parser.parse_args()

    inventory = generate_inventory()
    rendered = json.dumps(inventory, ensure_ascii=False, indent=2) + "\n"
    if args.write:
        OUTPUT_PATH.write_text(rendered, encoding="utf-8")
    else:
        print(rendered, end="")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
