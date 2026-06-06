#!/usr/bin/env python3
"""Generate order-review guidance for remaining hook consolidation candidates."""

from __future__ import annotations

import argparse
import json
from collections import Counter
from pathlib import Path
from typing import Any


ROOT = Path(__file__).resolve().parents[1]
JSON_OUTPUT_PATH = ROOT / "registry" / "hook-order-review.json"
MD_OUTPUT_PATH = ROOT / "registry" / "hook-order-review.md"


def load_json(relative_path: str) -> dict[str, Any]:
    return json.loads((ROOT / relative_path).read_text(encoding="utf-8"))


def candidate_id(candidate: dict[str, Any]) -> str:
    return "::".join(
        [
            str(candidate.get("event", "")),
            str(candidate.get("matcher", "")),
            str(candidate.get("bucket", "")),
        ]
    )


def blocker_from_risk_note(note: str) -> str:
    mapping = {
        "candidate risk is medium": "medium_risk_candidate",
        "mixed async semantics": "mixed_async_semantics",
        "statusMessage cannot be represented one-for-one in a single settings hook": "status_message_semantics",
        "contains LLM-backed hook": "contains_llm_backed_hook",
        "contains blocking hook": "contains_blocking_hook",
        "contains interleaved hooks": "non_contiguous_interleaved_hooks",
    }
    return mapping.get(note, note.replace(" ", "_"))


def candidate_blockers(candidate: dict[str, Any]) -> list[str]:
    blockers: list[str] = []
    if candidate.get("risk") == "high":
        blockers.append("high_risk_manual_review")
    elif candidate.get("risk") == "medium":
        blockers.append("medium_risk_candidate")
    if candidate.get("interleaved_hook_count", 0):
        blockers.append("non_contiguous_interleaved_hooks")
    if candidate.get("llm_hook_count", 0):
        blockers.append("contains_llm_backed_hook")
    if any(hook.get("blocking") for hook in candidate.get("hooks", [])):
        blockers.append("contains_blocking_hook")
    if len({hook.get("async") for hook in candidate.get("hooks", [])}) > 1:
        blockers.append("mixed_async_semantics")
    return sorted(set(blockers))


def strategy_for(
    event: str,
    matcher: str,
    bucket: str,
    blockers: list[str],
) -> tuple[str, str]:
    blocker_set = set(blockers)
    if "high_risk_manual_review" in blocker_set:
        return (
            "manual-review-only",
            "Document output, timeout, and blocking semantics before any wrapper migration.",
        )
    if "non_contiguous_interleaved_hooks" in blocker_set:
        return (
            "order-preserving-router-required",
            "Do not wrap only this side-effect subset. Either keep the current order or design a router that includes every interleaved hook in sequence.",
        )
    if matcher == "Bash" and "mixed_async_semantics" in blocker_set:
        return (
            "split-sync-guard-before-async-router",
            "Keep synchronous guard behavior separate, then consider an async background router for the remaining non-blocking hooks.",
        )
    if event == "Stop":
        return (
            "stop-router-output-contract-required",
            "Define which Stop hook output is user-visible, which work is background-only, and how long-running LLM calls are capped.",
        )
    if "status_message_semantics" in blocker_set:
        return (
            "status-aware-wrapper-required",
            "A single settings hook can expose only one statusMessage, so document whether the wrapper-level message is acceptable before migration.",
        )
    if "contains_llm_backed_hook" in blocker_set:
        return (
            "llm-timeout-and-telemetry-review",
            "Require per-child timeout, stdout/stderr passthrough, and adapter telemetry checks before migration.",
        )
    if bucket == "event_matcher":
        return (
            "candidate-for-wrapper-after-review",
            "Contiguous event/matcher group; run fixture replay and compare side effects before migration.",
        )
    return (
        "keep-as-is",
        "No migration strategy selected.",
    )


def hook_summary(hooks: list[dict[str, Any]]) -> list[dict[str, Any]]:
    return [
        {
            "order": hook.get("order"),
            "script": hook.get("script"),
            "priority": hook.get("priority"),
            "blocking": hook.get("blocking"),
            "calls_llm": hook.get("calls_llm"),
            "timeout_seconds": hook.get("timeout_seconds"),
            "side_effects": hook.get("side_effects", []),
        }
        for hook in hooks
    ]


def build_wrapper_item(plan: dict[str, Any]) -> dict[str, Any]:
    blockers = sorted(
        {blocker_from_risk_note(note) for note in plan.get("risk_notes", [])}
    )
    strategy, next_action = strategy_for(
        str(plan.get("event", "")),
        str(plan.get("matcher", "")),
        str(plan.get("bucket", "")),
        blockers,
    )
    return {
        "id": plan.get("id"),
        "source": "wrapper-plan",
        "event": plan.get("event"),
        "matcher": plan.get("matcher"),
        "bucket": plan.get("bucket"),
        "state": plan.get("definition_state") or "candidate",
        "blockers": blockers,
        "strategy": strategy,
        "next_action": next_action,
        "hook_count": len(plan.get("execution", [])),
        "execution": hook_summary(plan.get("execution", [])),
    }


def build_candidate_item(candidate: dict[str, Any]) -> dict[str, Any]:
    blockers = candidate_blockers(candidate)
    strategy, next_action = strategy_for(
        str(candidate.get("event", "")),
        str(candidate.get("matcher", "")),
        str(candidate.get("bucket", "")),
        blockers,
    )
    return {
        "id": candidate_id(candidate),
        "source": "consolidation-candidate",
        "event": candidate.get("event"),
        "matcher": candidate.get("matcher"),
        "bucket": candidate.get("bucket"),
        "risk": candidate.get("risk"),
        "recommendation": candidate.get("recommendation"),
        "blockers": blockers,
        "strategy": strategy,
        "next_action": next_action,
        "hook_count": candidate.get("hook_count"),
        "first_order": candidate.get("first_order"),
        "last_order": candidate.get("last_order"),
        "interleaved_hook_count": candidate.get("interleaved_hook_count"),
        "hooks": hook_summary(candidate.get("hooks", [])),
        "interleaved_hooks": hook_summary(candidate.get("interleaved_hooks", [])),
    }


def generate_json() -> dict[str, Any]:
    consolidation = load_json("registry/hook-consolidation-candidates.json")
    wrapper_plan = load_json("registry/hook-wrapper-plan.json")

    active_wrappers = [
        build_wrapper_item(plan)
        for plan in wrapper_plan.get("plans", [])
        if plan.get("source") == "definition" and plan.get("definition_state") == "active"
    ]
    wrapper_review_items = [
        build_wrapper_item(plan)
        for plan in wrapper_plan.get("plans", [])
        if plan.get("source") == "candidate"
    ]
    order_review_items = [
        build_candidate_item(candidate)
        for candidate in consolidation.get("candidates", [])
        if candidate.get("recommendation") == "order-review-before-wrapper"
    ]
    manual_review_items = [
        build_candidate_item(candidate)
        for candidate in consolidation.get("candidates", [])
        if candidate.get("recommendation") == "manual-review-only"
    ]
    all_review_items = wrapper_review_items + order_review_items + manual_review_items
    blocker_counts = Counter(
        blocker
        for item in all_review_items
        for blocker in item.get("blockers", [])
    )
    strategy_counts = Counter(item.get("strategy") for item in all_review_items)

    return {
        "version": 1,
        "generated_from": [
            "registry/hook-consolidation-candidates.json",
            "registry/hook-wrapper-plan.json",
        ],
        "description": "Review guide for hook candidates that should not be migrated automatically.",
        "active_wrapper_count": len(active_wrappers),
        "wrapper_review_count": len(wrapper_review_items),
        "order_review_count": len(order_review_items),
        "manual_review_count": len(manual_review_items),
        "review_item_count": len(all_review_items),
        "blocker_counts": dict(sorted(blocker_counts.items())),
        "strategy_counts": dict(sorted(strategy_counts.items())),
        "active_wrappers": active_wrappers,
        "wrapper_review_items": wrapper_review_items,
        "order_review_items": order_review_items,
        "manual_review_items": manual_review_items,
    }


def markdown_table(headers: list[str], rows: list[list[str]]) -> str:
    lines = [
        "| " + " | ".join(headers) + " |",
        "| " + " | ".join("---" for _ in headers) + " |",
    ]
    lines.extend("| " + " | ".join(row) + " |" for row in rows)
    return "\n".join(lines)


def render_items(items: list[dict[str, Any]], limit: int = 12) -> str:
    rows = []
    for item in items[:limit]:
        rows.append(
            [
                str(item.get("event")),
                str(item.get("matcher")),
                str(item.get("bucket")),
                str(item.get("hook_count")),
                ", ".join(item.get("blockers", [])),
                str(item.get("strategy")),
            ]
        )
    if not rows:
        return "No items.\n"
    return markdown_table(
        ["event", "matcher", "bucket", "hooks", "blockers", "strategy"],
        rows,
    ) + "\n"


def generate_markdown(report: dict[str, Any]) -> str:
    summary_rows = [
        ["active wrappers", str(report.get("active_wrapper_count"))],
        ["wrapper review items", str(report.get("wrapper_review_count"))],
        ["order-review items", str(report.get("order_review_count"))],
        ["manual-review items", str(report.get("manual_review_count"))],
        ["total review items", str(report.get("review_item_count"))],
    ]
    blocker_rows = [
        [key, str(value)] for key, value in report.get("blocker_counts", {}).items()
    ]
    strategy_rows = [
        [key, str(value)] for key, value in report.get("strategy_counts", {}).items()
    ]

    return "\n".join(
        [
            "<!-- generated by scripts/generate-hook-order-review.py; do not edit by hand -->",
            "",
            "# Hook Order Review",
            "",
            "This document classifies remaining hook consolidation candidates that should not be migrated automatically.",
            "",
            "## Summary",
            "",
            markdown_table(["metric", "value"], summary_rows),
            "",
            "## Blockers",
            "",
            markdown_table(["blocker", "count"], blocker_rows) if blocker_rows else "No blockers.",
            "",
            "## Strategies",
            "",
            markdown_table(["strategy", "count"], strategy_rows) if strategy_rows else "No strategies.",
            "",
            "## Wrapper Review Items",
            "",
            render_items(report.get("wrapper_review_items", [])),
            "## Order Review Items",
            "",
            render_items(report.get("order_review_items", [])),
            "## Manual Review Items",
            "",
            render_items(report.get("manual_review_items", [])),
            "",
        ]
    ).rstrip() + "\n"


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--write", action="store_true", help="write registry hook order review files")
    parser.add_argument("--markdown", action="store_true", help="print markdown instead of JSON")
    args = parser.parse_args()

    report = generate_json()
    if args.write:
        JSON_OUTPUT_PATH.write_text(
            json.dumps(report, ensure_ascii=False, indent=2) + "\n",
            encoding="utf-8",
        )
        MD_OUTPUT_PATH.write_text(generate_markdown(report), encoding="utf-8")
    elif args.markdown:
        print(generate_markdown(report), end="")
    else:
        print(json.dumps(report, ensure_ascii=False, indent=2))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
