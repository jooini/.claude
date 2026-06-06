#!/usr/bin/env python3
"""Generate conservative hook consolidation candidates from hooks inventory."""

from __future__ import annotations

import argparse
import json
from collections import Counter, defaultdict
from pathlib import Path
from typing import Any


ROOT = Path(__file__).resolve().parents[1]
OUTPUT_PATH = ROOT / "registry" / "hook-consolidation-candidates.json"


def load_json(relative_path: str) -> dict[str, Any]:
    return json.loads((ROOT / relative_path).read_text(encoding="utf-8"))


def risk_level(
    hooks: list[dict[str, Any]],
    interleaved_hooks: list[dict[str, Any]] | None = None,
) -> str:
    interleaved_hooks = interleaved_hooks or []
    if any(hook.get("blocking") or hook.get("priority") == "P0" for hook in hooks):
        return "high"
    if interleaved_hooks:
        return "medium"
    if any(hook.get("calls_llm") or hook.get("priority") == "P1" for hook in hooks):
        return "medium"
    return "low"


def candidate_score(
    hooks: list[dict[str, Any]],
    interleaved_hooks: list[dict[str, Any]] | None = None,
) -> int:
    interleaved_hooks = interleaved_hooks or []
    score = len(hooks) * 10
    if all(not hook.get("blocking") for hook in hooks):
        score += 10
    if all(hook.get("priority") not in {"P0"} for hook in hooks):
        score += 10
    if len({tuple(hook.get("side_effects", [])) for hook in hooks}) == 1:
        score += 5
    if any(hook.get("calls_llm") for hook in hooks):
        score -= 5
    if interleaved_hooks:
        score -= 15
    return max(score, 0)


def reason_for(group_key: str, hooks: list[dict[str, Any]]) -> str:
    event, matcher, bucket = group_key.split("\x1f")
    if bucket == "event_matcher":
        return f"{event}/{matcher} has {len(hooks)} hooks with the same runtime trigger."
    if bucket.startswith("side_effect:"):
        side_effect = bucket.split(":", 1)[1]
        return f"{event}/{matcher} has {len(hooks)} hooks sharing side effect {side_effect}."
    return f"{event}/{matcher} has {len(hooks)} related hooks."


def summarize_hooks(hooks: list[dict[str, Any]]) -> list[dict[str, Any]]:
    return [
        {
            "id": hook.get("id"),
            "order": hook.get("order"),
            "script": hook.get("script"),
            "priority": hook.get("priority"),
            "blocking": hook.get("blocking"),
            "calls_llm": hook.get("calls_llm"),
            "side_effects": hook.get("side_effects", []),
            "timeout_seconds": hook.get("timeout_seconds"),
        }
        for hook in hooks
    ]


def order_metadata(
    hooks: list[dict[str, Any]],
    all_hooks: list[dict[str, Any]],
) -> dict[str, Any]:
    hook_ids = {str(hook.get("id")) for hook in hooks}
    orders = sorted(int(hook.get("order", -1)) for hook in hooks)
    event = hooks[0].get("event") if hooks else None
    matcher = hooks[0].get("matcher") if hooks else None
    first_order = orders[0] if orders else None
    last_order = orders[-1] if orders else None
    interleaved_hooks = []

    if first_order is not None and last_order is not None:
        for hook in all_hooks:
            if hook.get("event") != event or hook.get("matcher") != matcher:
                continue
            order = int(hook.get("order", -1))
            if first_order < order < last_order and str(hook.get("id")) not in hook_ids:
                interleaved_hooks.append(hook)

    return {
        "first_order": first_order,
        "last_order": last_order,
        "order_span": (
            last_order - first_order + 1
            if first_order is not None and last_order is not None
            else 0
        ),
        "contiguous_within_trigger": not interleaved_hooks,
        "interleaved_hook_count": len(interleaved_hooks),
        "interleaved_hooks": summarize_hooks(interleaved_hooks),
        "_raw_interleaved_hooks": interleaved_hooks,
    }


def recommendation_for(risk: str, interleaved_hooks: list[dict[str, Any]]) -> str:
    if risk == "high":
        return "manual-review-only"
    if interleaved_hooks:
        return "order-review-before-wrapper"
    return "candidate-for-router-or-wrapper"


def build_candidate(
    group_key: str,
    hooks: list[dict[str, Any]],
    all_hooks: list[dict[str, Any]],
) -> dict[str, Any]:
    event, matcher, bucket = group_key.split("\x1f")
    order = order_metadata(hooks, all_hooks)
    raw_interleaved_hooks = order.pop("_raw_interleaved_hooks")
    risk = risk_level(hooks, raw_interleaved_hooks)
    priorities = Counter(str(hook.get("priority")) for hook in hooks)
    side_effects = Counter(
        side_effect
        for hook in hooks
        for side_effect in hook.get("side_effects", [])
    )
    return {
        "event": event,
        "matcher": matcher,
        "bucket": bucket,
        "risk": risk,
        "score": candidate_score(hooks, raw_interleaved_hooks),
        "hook_count": len(hooks),
        **order,
        "priority_counts": dict(sorted(priorities.items())),
        "llm_hook_count": sum(1 for hook in hooks if hook.get("calls_llm")),
        "side_effects": dict(sorted(side_effects.items())),
        "reason": reason_for(group_key, hooks),
        "recommendation": recommendation_for(risk, raw_interleaved_hooks),
        "hooks": summarize_hooks(hooks),
    }


def generate_candidates() -> dict[str, Any]:
    inventory = load_json("registry/hooks-inventory.json")
    hooks = inventory.get("hooks", [])
    groups: dict[str, list[dict[str, Any]]] = defaultdict(list)

    for hook in hooks:
        event = hook.get("event", "")
        matcher = hook.get("matcher", "")
        groups[f"{event}\x1f{matcher}\x1fevent_matcher"].append(hook)
        for side_effect in hook.get("side_effects", []):
            groups[f"{event}\x1f{matcher}\x1fside_effect:{side_effect}"].append(hook)

    candidates = []
    seen_fingerprints: set[tuple[str, ...]] = set()
    for group_key, grouped_hooks in groups.items():
        if len(grouped_hooks) < 2:
            continue
        fingerprint = tuple(hook.get("id", "") for hook in grouped_hooks)
        if fingerprint in seen_fingerprints:
            continue
        seen_fingerprints.add(fingerprint)
        candidates.append(build_candidate(group_key, grouped_hooks, hooks))

    candidates.sort(key=lambda item: (-item["score"], item["risk"], item["event"], item["matcher"]))
    low_risk = [item for item in candidates if item["risk"] == "low"]
    medium_risk = [item for item in candidates if item["risk"] == "medium"]
    high_risk = [item for item in candidates if item["risk"] == "high"]
    wrapper_ready = [
        item for item in candidates if item["recommendation"] == "candidate-for-router-or-wrapper"
    ]
    order_review = [
        item for item in candidates if item["recommendation"] == "order-review-before-wrapper"
    ]
    manual_review = [
        item for item in candidates if item["recommendation"] == "manual-review-only"
    ]

    return {
        "version": 1,
        "generated_from": "registry/hooks-inventory.json",
        "description": "Conservative hook consolidation candidates. This report does not imply automatic merging.",
        "hook_count": inventory.get("hook_count"),
        "candidate_count": len(candidates),
        "low_risk_count": len(low_risk),
        "medium_risk_count": len(medium_risk),
        "high_risk_count": len(high_risk),
        "wrapper_ready_count": len(wrapper_ready),
        "order_review_count": len(order_review),
        "manual_review_count": len(manual_review),
        "top_candidates": candidates[:12],
        "candidates": candidates,
    }


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--write", action="store_true", help=f"write {OUTPUT_PATH.relative_to(ROOT)}")
    args = parser.parse_args()

    report = generate_candidates()
    rendered = json.dumps(report, ensure_ascii=False, indent=2) + "\n"
    if args.write:
        OUTPUT_PATH.write_text(rendered, encoding="utf-8")
    else:
        print(rendered, end="")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
