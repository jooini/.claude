#!/usr/bin/env python3
"""Generate order-preserving hook wrapper migration plans."""

from __future__ import annotations

import argparse
import json
import re
from itertools import combinations
from pathlib import Path
from typing import Any


ROOT = Path(__file__).resolve().parents[1]
OUTPUT_PATH = ROOT / "registry" / "hook-wrapper-plan.json"
DEFINITIONS_PATH = ROOT / "registry" / "hook-wrapper-definitions.json"


def load_json(relative_path: str) -> dict[str, Any]:
    return json.loads((ROOT / relative_path).read_text(encoding="utf-8"))


def slugify(value: str) -> str:
    value = value.replace("*", "all")
    value = value.replace("|", "-")
    value = re.sub(r"[^a-zA-Z0-9]+", "-", value)
    return value.strip("-").lower() or "empty"


def hook_timeout(hook: dict[str, Any]) -> int:
    timeout = hook.get("timeout_seconds")
    if isinstance(timeout, int) and timeout > 0:
        return timeout
    effective_timeout = hook.get("effective_timeout_seconds")
    if isinstance(effective_timeout, int) and effective_timeout > 0:
        return effective_timeout
    return 3


def wrapper_plan_id(candidate: dict[str, Any]) -> str:
    return "-".join(
        [
            slugify(str(candidate.get("event", ""))),
            slugify(str(candidate.get("matcher", ""))),
            slugify(str(candidate.get("bucket", ""))),
        ]
    )


def load_definitions() -> list[dict[str, Any]]:
    if not DEFINITIONS_PATH.exists():
        return []
    data = json.loads(DEFINITIONS_PATH.read_text(encoding="utf-8"))
    return data.get("definitions", [])


def settings_replacement_for(
    wrapper_id: str,
    async_value: bool | None,
    wrapper_timeout: int,
    status_message: str | None,
) -> dict[str, Any]:
    return {
        "command": (
            f"{ROOT}/scripts/hook-wrapper-runner.py {wrapper_id} "
            "--execute --allow-side-effects"
        ),
        "dry_run_command": f"{ROOT}/scripts/hook-wrapper-runner.py {wrapper_id}",
        "async": async_value,
        "timeout": wrapper_timeout,
        "statusMessage": status_message,
    }


def build_risk_notes(
    candidate: dict[str, Any],
    hooks: list[dict[str, Any]],
    async_values: set[bool],
    status_messages: list[str],
) -> list[str]:
    notes: list[str] = []
    if candidate.get("risk") != "low":
        notes.append(f"candidate risk is {candidate.get('risk')}")
    if len(async_values) > 1:
        notes.append("mixed async semantics")
    if status_messages:
        notes.append("statusMessage cannot be represented one-for-one in a single settings hook")
    if any(hook.get("blocking") for hook in hooks):
        notes.append("contains blocking hook")
    if any(hook.get("calls_llm") for hook in hooks):
        notes.append("contains LLM-backed hook")
    if candidate.get("interleaved_hook_count", 0):
        notes.append("contains interleaved hooks")
    return notes


def build_plan(candidate: dict[str, Any], inventory_by_id: dict[str, dict[str, Any]]) -> dict[str, Any]:
    hooks = [inventory_by_id[hook["id"]] for hook in candidate.get("hooks", [])]
    hooks.sort(key=lambda hook: hook["order"])
    async_values = {bool(hook.get("async")) for hook in hooks}
    status_messages = [
        str(hook.get("status_message"))
        for hook in hooks
        if hook.get("status_message")
    ]
    wrapper_id = wrapper_plan_id(candidate)
    total_timeout = sum(hook_timeout(hook) for hook in hooks)
    wrapper_timeout = total_timeout + 2
    risk_notes = build_risk_notes(candidate, hooks, async_values, status_messages)
    safe_initial_migration = (
        candidate.get("contiguous_within_trigger") is True
        and len(async_values) == 1
        and not status_messages
        and not any(hook.get("blocking") for hook in hooks)
        and not any(hook.get("calls_llm") for hook in hooks)
    )
    if safe_initial_migration and "candidate risk is medium" not in risk_notes:
        risk_notes = ["candidate risk is medium"]
    async_value = async_values.pop() if len(async_values) == 1 else None

    return {
        "id": wrapper_id,
        "source": "candidate",
        "event": candidate.get("event"),
        "matcher": candidate.get("matcher"),
        "bucket": candidate.get("bucket"),
        "source_candidate": {
            "risk": candidate.get("risk"),
            "recommendation": candidate.get("recommendation"),
            "score": candidate.get("score"),
            "hook_count": candidate.get("hook_count"),
            "first_order": candidate.get("first_order"),
            "last_order": candidate.get("last_order"),
        },
        "safe_initial_migration": safe_initial_migration,
        "risk_notes": risk_notes,
        "settings_replacement": settings_replacement_for(
            wrapper_id,
            async_value,
            wrapper_timeout,
            status_messages[0] if len(status_messages) == 1 else None,
        ),
        "timeout_strategy": {
            "per_hook_timeout_enforced_by_runner": True,
            "sum_hook_timeouts_seconds": total_timeout,
            "wrapper_timeout_seconds": wrapper_timeout,
        },
        "execution": [
            {
                "hook_id": hook.get("id"),
                "order": hook.get("order"),
                "command": hook.get("command"),
                "script": hook.get("script"),
                "async": hook.get("async"),
                "timeout_seconds": hook_timeout(hook),
                "blocking": hook.get("blocking"),
                "failure_mode": hook.get("failure_mode"),
                "status_message": hook.get("status_message"),
                "calls_llm": hook.get("calls_llm"),
                "side_effects": hook.get("side_effects", []),
            }
            for hook in hooks
        ],
    }


def build_definition_plan(definition: dict[str, Any]) -> dict[str, Any]:
    wrapper_id = str(definition["id"])
    hooks = sorted(definition.get("execution", []), key=lambda hook: hook["order"])
    async_values = {bool(hook.get("async")) for hook in hooks}
    status_messages = [
        str(hook.get("status_message"))
        for hook in hooks
        if hook.get("status_message")
    ]
    status_policy = definition.get("status_message_policy") or {}
    wrapper_status_message = status_policy.get("wrapper_status_message")
    if wrapper_status_message is None and len(status_messages) == 1:
        wrapper_status_message = status_messages[0]
    total_timeout = sum(hook_timeout(hook) for hook in hooks)
    wrapper_timeout = total_timeout + 2
    async_value = async_values.pop() if len(async_values) == 1 else None
    return {
        "id": wrapper_id,
        "source": "definition",
        "definition_state": definition.get("state"),
        "event": definition.get("event"),
        "matcher": definition.get("matcher"),
        "bucket": definition.get("bucket"),
        "source_candidate": None,
        "safe_initial_migration": bool(definition.get("safe_initial_migration")),
        "risk_notes": definition.get("risk_notes", []),
        "execution_contract": definition.get("execution_contract", {}),
        "status_message_policy": status_policy,
        "settings_replacement": settings_replacement_for(
            wrapper_id,
            async_value,
            wrapper_timeout,
            wrapper_status_message,
        ),
        "timeout_strategy": {
            "per_hook_timeout_enforced_by_runner": True,
            "sum_hook_timeouts_seconds": total_timeout,
            "wrapper_timeout_seconds": wrapper_timeout,
        },
        "execution": hooks,
    }


def overlapping_plans(plans: list[dict[str, Any]]) -> list[dict[str, Any]]:
    overlaps: list[dict[str, Any]] = []
    for left, right in combinations(plans, 2):
        left_hooks = {step["hook_id"] for step in left.get("execution", [])}
        right_hooks = {step["hook_id"] for step in right.get("execution", [])}
        shared = sorted(left_hooks & right_hooks)
        if shared:
            overlaps.append(
                {
                    "left": left["id"],
                    "right": right["id"],
                    "shared_hook_ids": shared,
                }
            )
    return overlaps


def generate() -> dict[str, Any]:
    candidates_report = load_json("registry/hook-consolidation-candidates.json")
    inventory = load_json("registry/hooks-inventory.json")
    inventory_by_id = {hook["id"]: hook for hook in inventory.get("hooks", [])}
    wrapper_candidates = [
        candidate
        for candidate in candidates_report.get("candidates", [])
        if candidate.get("recommendation") == "candidate-for-router-or-wrapper"
    ]
    definition_plans = [build_definition_plan(definition) for definition in load_definitions()]
    definition_ids = {plan["id"] for plan in definition_plans}
    candidate_plans = [
        build_plan(candidate, inventory_by_id)
        for candidate in wrapper_candidates
        if wrapper_plan_id(candidate) not in definition_ids
    ]
    plans = definition_plans + candidate_plans
    safe_initial = [plan for plan in plans if plan.get("safe_initial_migration")]
    active_definitions = [
        plan for plan in definition_plans if plan.get("definition_state") == "active"
    ]
    planned_definitions = [
        plan for plan in definition_plans if plan.get("definition_state") == "planned"
    ]

    return {
        "version": 1,
        "generated_from": [
            "registry/hook-consolidation-candidates.json",
            "registry/hooks-inventory.json",
        ],
        "description": "Order-preserving wrapper migration options. Plans are mutually exclusive when hook ids overlap.",
        "runner": "scripts/hook-wrapper-runner.py",
        "definitions_file": "registry/hook-wrapper-definitions.json",
        "fixture_file": "registry/hook-replay-fixtures.json",
        "wrapper_ready_candidate_count": len(wrapper_candidates),
        "definition_count": len(definition_plans),
        "active_definition_count": len(active_definitions),
        "planned_definition_count": len(planned_definitions),
        "candidate_plan_count": len(candidate_plans),
        "plan_count": len(plans),
        "safe_initial_migration_count": len(safe_initial),
        "overlap_count": len(overlapping_plans(plans)),
        "plans": plans,
        "overlaps": overlapping_plans(plans),
    }


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--write", action="store_true", help=f"write {OUTPUT_PATH.relative_to(ROOT)}")
    args = parser.parse_args()

    rendered = json.dumps(generate(), ensure_ascii=False, indent=2) + "\n"
    if args.write:
        OUTPUT_PATH.write_text(rendered, encoding="utf-8")
    else:
        print(rendered, end="")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
