#!/usr/bin/env python3
"""Summarize MoAI router, adapter, Agy, and bridge telemetry."""

from __future__ import annotations

import argparse
import json
import sys
from collections import Counter, defaultdict
from datetime import datetime, timedelta, timezone
from pathlib import Path
from typing import Any


ROOT = Path.home() / ".claude"
CACHE = ROOT / "cache"
ROUTER_LOG = CACHE / "llm-router-calls.jsonl"
ADAPTER_LOG = CACHE / "llm-adapter-calls.jsonl"
AGY_LOG = CACHE / "agy-calls.jsonl"
BRIDGE_LOG = CACHE / "moai-bridge-live.jsonl"
HANDOFF = CACHE / "llm-handoff" / "current.json"
REPORT_PATH = CACHE / "moai-telemetry-report.json"

ADAPTER_HEALTH_EXCLUDED_CLASSES = {"expected_offline", "smoke", "sandbox_blocked"}


def utc_now() -> str:
    return datetime.now(timezone.utc).isoformat(timespec="seconds").replace("+00:00", "Z")


def parse_time(value: Any) -> datetime | None:
    if not isinstance(value, str) or not value:
        return None
    try:
        return datetime.fromisoformat(value.replace("Z", "+00:00"))
    except ValueError:
        return None


def iter_jsonl(path: Path) -> list[dict[str, Any]]:
    records: list[dict[str, Any]] = []
    if not path.exists():
        return records
    try:
        with path.open(encoding="utf-8") as handle:
            for line in handle:
                try:
                    item = json.loads(line)
                except json.JSONDecodeError:
                    continue
                if isinstance(item, dict):
                    records.append(item)
    except OSError:
        return []
    return records


def record_time(record: dict[str, Any]) -> datetime | None:
    return parse_time(record.get("timestamp") or record.get("generated_at") or record.get("updated_at"))


def filter_window(records: list[dict[str, Any]], cutoff: datetime) -> list[dict[str, Any]]:
    filtered = []
    for record in records:
        timestamp = record_time(record)
        if timestamp is not None and timestamp >= cutoff:
            filtered.append(record)
    return filtered


def average(values: list[int]) -> int:
    return int(sum(values) / len(values)) if values else 0


def latest_record(records: list[dict[str, Any]]) -> dict[str, Any] | None:
    if not records:
        return None
    return max(records, key=lambda item: record_time(item) or datetime.min.replace(tzinfo=timezone.utc))


def latest_matching_time(records: list[dict[str, Any]], predicate) -> datetime | None:
    matches = [
        timestamp
        for record in records
        if predicate(record)
        for timestamp in [record_time(record)]
        if timestamp is not None
    ]
    return max(matches) if matches else None


def is_health_relevant_adapter_error(record: dict[str, Any]) -> bool:
    return (
        record.get("status") != "ok"
        and record.get("health_class") not in ADAPTER_HEALTH_EXCLUDED_CLASSES
    )


def is_e2e_caller(value: Any) -> bool:
    caller = str(value or "")
    return caller.startswith("moai-system-check") or caller.startswith("moai-e2e")


def summarize_router(records: list[dict[str, Any]]) -> dict[str, Any]:
    by_status = Counter(str(item.get("status", "unknown")) for item in records)
    by_task = Counter(str(item.get("task", "unknown")) for item in records)
    provider_counts: Counter[str] = Counter()
    for item in records:
        for provider in item.get("providers") or []:
            provider_counts[str(provider)] += 1
    latest = latest_record(records)
    return {
        "calls": len(records),
        "by_status": dict(sorted(by_status.items())),
        "by_task": dict(sorted(by_task.items())),
        "providers": dict(sorted(provider_counts.items())),
        "latest": {
            "timestamp": latest.get("timestamp"),
            "task": latest.get("task"),
            "caller": latest.get("caller"),
            "status": latest.get("status"),
        } if latest else None,
    }


def summarize_adapter(records: list[dict[str, Any]]) -> dict[str, Any]:
    by_status = Counter(str(item.get("status", "unknown")) for item in records)
    by_provider = Counter(str(item.get("provider", "unknown")) for item in records)
    by_health_class = Counter(str(item.get("health_class", "unknown")) for item in records)
    by_failure_reason = Counter(
        str(item.get("failure_reason"))
        for item in records
        if item.get("failure_reason")
    )
    relevant_errors = [
        item
        for item in records
        if is_health_relevant_adapter_error(item)
    ]
    durations = [
        int(item.get("duration_ms") or 0)
        for item in records
        if isinstance(item.get("duration_ms"), int) or str(item.get("duration_ms", "")).isdigit()
    ]
    return {
        "calls": len(records),
        "by_status": dict(sorted(by_status.items())),
        "by_provider": dict(sorted(by_provider.items())),
        "by_health_class": dict(sorted(by_health_class.items())),
        "by_failure_reason": dict(sorted(by_failure_reason.items())),
        "avg_duration_ms": average(durations),
        "health_relevant_errors": len(relevant_errors),
    }


def summarize_agy(records: list[dict[str, Any]]) -> dict[str, Any]:
    by_status = Counter(str(item.get("status", "unknown")) for item in records)
    durations = [
        int(item.get("duration_ms") or 0)
        for item in records
        if isinstance(item.get("duration_ms"), int) or str(item.get("duration_ms", "")).isdigit()
    ]
    latest = latest_record(records)
    return {
        "calls": len(records),
        "by_status": dict(sorted(by_status.items())),
        "avg_duration_ms": average(durations),
        "latest": {
            "timestamp": latest.get("timestamp"),
            "caller": latest.get("caller"),
            "status": latest.get("status"),
        } if latest else None,
    }


def summarize_bridge(records: list[dict[str, Any]]) -> dict[str, Any]:
    by_runner = defaultdict(Counter)
    for item in records:
        by_runner[str(item.get("runner", "unknown"))][str(item.get("status", "unknown"))] += 1
    latest = latest_record(records)
    return {
        "calls": len(records),
        "by_runner": {
            runner: dict(sorted(counter.items()))
            for runner, counter in sorted(by_runner.items())
        },
        "latest": {
            "timestamp": latest.get("timestamp"),
            "runner": latest.get("runner"),
            "phase": latest.get("phase"),
            "status": latest.get("status"),
        } if latest else None,
    }


def read_handoff() -> dict[str, Any] | None:
    if not HANDOFF.exists():
        return None
    try:
        value = json.loads(HANDOFF.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError):
        return None
    return value if isinstance(value, dict) else None


def build_e2e_evidence(
    router_records: list[dict[str, Any]],
    adapter_records: list[dict[str, Any]],
    agy_records: list[dict[str, Any]],
    bridge_records: list[dict[str, Any]],
    handoff: dict[str, Any] | None,
) -> dict[str, Any]:
    router_recent = any(
        is_e2e_caller(item.get("caller"))
        for item in router_records
    )
    codex_live_ok = any(
        item.get("provider") == "codex"
        and str(item.get("caller", "")).startswith("doctor-live")
        and item.get("status") == "ok"
        for item in adapter_records
    )
    gemini_live_ok = any(
        item.get("provider") == "gemini"
        and str(item.get("caller", "")).startswith("doctor-live")
        and item.get("status") == "ok"
        for item in adapter_records
    )
    agy_live_ok = any(
        str(item.get("caller", "")).startswith("doctor-live")
        and item.get("status") == "ok"
        for item in agy_records
    )
    bridge_agy_ok = any(
        item.get("runner") == "agy" and item.get("status") == "succeeded"
        for item in bridge_records
    )
    bridge_codex_ok = any(
        item.get("runner") == "codex" and item.get("status") == "succeeded"
        for item in bridge_records
    )
    handoff_ok = bool(
        handoff
        and is_e2e_caller(handoff.get("caller"))
        and handoff.get("task") in {"default", "scan", "implement"}
        and handoff.get("active_providers") is not None
    )
    checks = {
        "router_recent": router_recent,
        "adapter_codex_live_ok": codex_live_ok,
        "adapter_gemini_live_ok": gemini_live_ok,
        "agy_live_ok": agy_live_ok,
        "bridge_agy_ok": bridge_agy_ok,
        "bridge_codex_ok": bridge_codex_ok,
        "handoff_updated": handoff_ok,
    }
    return {
        **checks,
        "complete": all(checks.values()),
    }


def build_current_status(
    *,
    router_records: list[dict[str, Any]],
    adapter_records: list[dict[str, Any]],
    agy_records: list[dict[str, Any]],
    bridge_records: list[dict[str, Any]],
    handoff: dict[str, Any] | None,
    current_minutes: int,
) -> dict[str, Any]:
    cutoff = datetime.now(timezone.utc) - timedelta(minutes=current_minutes)
    recent_router = filter_window(router_records, cutoff)
    recent_adapter = filter_window(adapter_records, cutoff)
    recent_agy = filter_window(agy_records, cutoff)
    recent_bridge = filter_window(bridge_records, cutoff)
    handoff_time = parse_time(handoff.get("updated_at")) if handoff else None
    recent_handoff = handoff if handoff_time is not None and handoff_time >= cutoff else None

    evidence = build_e2e_evidence(
        recent_router,
        recent_adapter,
        recent_agy,
        recent_bridge,
        recent_handoff,
    )
    evidence_times = {
        "router_recent": latest_matching_time(
            recent_router,
            lambda item: is_e2e_caller(item.get("caller")),
        ),
        "adapter_codex_live_ok": latest_matching_time(
            recent_adapter,
            lambda item: item.get("provider") == "codex"
            and str(item.get("caller", "")).startswith("doctor-live")
            and item.get("status") == "ok",
        ),
        "adapter_gemini_live_ok": latest_matching_time(
            recent_adapter,
            lambda item: item.get("provider") == "gemini"
            and str(item.get("caller", "")).startswith("doctor-live")
            and item.get("status") == "ok",
        ),
        "agy_live_ok": latest_matching_time(
            recent_agy,
            lambda item: str(item.get("caller", "")).startswith("doctor-live")
            and item.get("status") == "ok",
        ),
        "bridge_agy_ok": latest_matching_time(
            recent_bridge,
            lambda item: item.get("runner") == "agy" and item.get("status") == "succeeded",
        ),
        "bridge_codex_ok": latest_matching_time(
            recent_bridge,
            lambda item: item.get("runner") == "codex" and item.get("status") == "succeeded",
        ),
        "handoff_updated": handoff_time if recent_handoff else None,
    }
    complete_times = [value for value in evidence_times.values() if value is not None]
    completed_at = max(complete_times).isoformat(timespec="seconds").replace("+00:00", "Z") if evidence["complete"] and complete_times else None
    completed_datetime = parse_time(completed_at)
    adapter_errors_after_e2e = [
        item
        for item in adapter_records
        if is_health_relevant_adapter_error(item)
        and completed_datetime is not None
        and (record_time(item) or datetime.min.replace(tzinfo=timezone.utc)) > completed_datetime
    ]
    status = "ok" if evidence["complete"] and not adapter_errors_after_e2e else "stale"
    if evidence["complete"] and adapter_errors_after_e2e:
        status = "degraded"
    return {
        "status": status,
        "window_minutes": current_minutes,
        "completed_at": completed_at,
        "adapter_errors_after_e2e": len(adapter_errors_after_e2e),
        "e2e_evidence": evidence,
        "evidence_times": {
            key: value.isoformat(timespec="seconds").replace("+00:00", "Z") if value else None
            for key, value in evidence_times.items()
        },
    }


def build_report(days: int, current_minutes: int) -> dict[str, Any]:
    cutoff = datetime.now(timezone.utc) - timedelta(days=days)
    router_records = filter_window(iter_jsonl(ROUTER_LOG), cutoff)
    adapter_records = filter_window(iter_jsonl(ADAPTER_LOG), cutoff)
    agy_records = filter_window(iter_jsonl(AGY_LOG), cutoff)
    bridge_records = filter_window(iter_jsonl(BRIDGE_LOG), cutoff)
    handoff = read_handoff()

    adapter = summarize_adapter(adapter_records)
    history_status = "ok" if adapter["health_relevant_errors"] == 0 else "degraded"
    current = build_current_status(
        router_records=router_records,
        adapter_records=adapter_records,
        agy_records=agy_records,
        bridge_records=bridge_records,
        handoff=handoff,
        current_minutes=current_minutes,
    )
    return {
        "schema_version": 1,
        "generated_at": utc_now(),
        "status": current["status"],
        "window_days": days,
        "history": {
            "status": history_status,
            "adapter_health_relevant_errors": adapter["health_relevant_errors"],
        },
        "current": current,
        "paths": {
            "router": str(ROUTER_LOG),
            "adapter": str(ADAPTER_LOG),
            "agy": str(AGY_LOG),
            "bridge": str(BRIDGE_LOG),
            "handoff": str(HANDOFF),
        },
        "router": summarize_router(router_records),
        "adapter": adapter,
        "agy": summarize_agy(agy_records),
        "bridge": summarize_bridge(bridge_records),
        "handoff": {
            "updated_at": handoff.get("updated_at"),
            "task": handoff.get("task"),
            "caller": handoff.get("caller"),
            "active_provider": handoff.get("active_provider"),
            "active_providers": handoff.get("active_providers"),
        } if handoff else None,
        "e2e_evidence": build_e2e_evidence(
            router_records,
            adapter_records,
            agy_records,
            bridge_records,
            handoff,
        ),
    }


def print_text(report: dict[str, Any]) -> None:
    print(f"MoAI telemetry report: {report['status'].upper()} (history={report['history']['status'].upper()})")
    print(f"window: {report['window_days']}d current={report['current']['window_minutes']}m")
    router = report["router"]
    adapter = report["adapter"]
    agy = report["agy"]
    bridge = report["bridge"]
    e2e = report["current"]["e2e_evidence"]
    print(f"router: calls={router['calls']} status={router['by_status']} tasks={router['by_task']}")
    print(
        f"adapter: calls={adapter['calls']} status={adapter['by_status']} "
        f"providers={adapter['by_provider']} health_errors={adapter['health_relevant_errors']}"
    )
    print(f"agy: calls={agy['calls']} status={agy['by_status']}")
    print(f"bridge: calls={bridge['calls']} runners={bridge['by_runner']}")
    print(f"handoff: {report['handoff']}")
    print(
        f"current: status={report['current']['status']} "
        f"completed_at={report['current']['completed_at']} "
        f"errors_after_e2e={report['current']['adapter_errors_after_e2e']}"
    )
    print(f"e2e: complete={e2e['complete']} evidence={e2e}")


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description="Summarize MoAI router and bridge telemetry.")
    parser.add_argument("--days", type=int, default=7, help="lookback window in days")
    parser.add_argument("--current-minutes", type=int, default=60, help="freshness window for current E2E status")
    parser.add_argument("--json", action="store_true", help="print JSON")
    parser.add_argument("--write", action="store_true", help=f"write latest report to {REPORT_PATH}")
    parser.add_argument("--require-e2e", action="store_true", help="exit non-zero unless E2E evidence is complete")
    return parser


def main() -> int:
    args = build_parser().parse_args()
    report = build_report(max(1, args.days), max(1, args.current_minutes))
    if args.write:
        REPORT_PATH.parent.mkdir(parents=True, exist_ok=True)
        REPORT_PATH.write_text(json.dumps(report, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")

    if args.json:
        print(json.dumps(report, ensure_ascii=False, indent=2))
    else:
        print_text(report)

    if args.require_e2e and not report["current"]["e2e_evidence"]["complete"]:
        return 1
    return 0 if report["status"] in {"ok", "degraded"} else 1


if __name__ == "__main__":
    raise SystemExit(main())
