#!/usr/bin/env python3
"""Backfill health_class and failure_reason in LLM adapter telemetry."""

from __future__ import annotations

import argparse
import json
import os
import shutil
from collections import Counter
from datetime import datetime, timezone
from pathlib import Path
from typing import Any


ROOT = Path(__file__).resolve().parents[1]
DEFAULT_PATH = ROOT / "cache" / "llm-adapter-calls.jsonl"
HEALTH_PATH = ROOT / "cache" / "llm-provider-health.json"


def utc_stamp() -> str:
    return datetime.now(timezone.utc).strftime("%Y%m%d%H%M%S")


def as_int(value: Any, default: int = 0) -> int:
    try:
        return int(value)
    except (TypeError, ValueError):
        return default


def load_provider_health() -> dict[str, str]:
    try:
        health = json.loads(HEALTH_PATH.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError):
        return {}
    providers = health.get("providers") or {}
    return {
        str(provider): str(info.get("status"))
        for provider, info in providers.items()
        if isinstance(info, dict)
    }


def infer_health_class(
    record: dict[str, Any],
    provider: str,
    caller: str,
    status: str,
    exit_code: int,
    provider_health: dict[str, str],
) -> str:
    value = record.get("health_class")
    if isinstance(value, str) and value:
        return value
    if status == "ok" and exit_code == 0:
        return "ok"
    caller_lower = caller.lower()
    if "smoke" in caller_lower or "doctor-live" in caller_lower:
        return "smoke"
    if provider in {"ini", "ollama", "gemma", "qwen"} and provider_health.get("gemma") == "expected_offline":
        return "expected_offline"
    return "runtime_failure"


def infer_failure_reason(
    record: dict[str, Any],
    caller: str,
    status: str,
    exit_code: int,
    health_class: str,
) -> str | None:
    value = record.get("failure_reason")
    if isinstance(value, str) and value:
        return value
    if status == "ok" and exit_code == 0:
        return None
    caller_lower = caller.lower()
    prompt_length = as_int(record.get("prompt_length"))
    if health_class == "expected_offline":
        return "expected_offline"
    if health_class == "smoke" or "smoke" in caller_lower or "doctor-live" in caller_lower:
        return "smoke_failure"
    if health_class == "sandbox_blocked":
        return "sandbox_blocked"
    if exit_code == 124:
        return "timeout_large_prompt" if prompt_length >= 20000 else "timeout"
    if exit_code == 127:
        return "missing_executable"
    if exit_code == 2:
        return "usage_error"
    return "runtime_error"


def load_records(path: Path) -> tuple[list[dict[str, Any]], int]:
    records: list[dict[str, Any]] = []
    invalid = 0
    if not path.exists():
        return records, invalid
    for line in path.read_text(encoding="utf-8", errors="replace").splitlines():
        if not line.strip():
            continue
        try:
            record = json.loads(line)
        except json.JSONDecodeError:
            invalid += 1
            continue
        if isinstance(record, dict):
            records.append(record)
        else:
            invalid += 1
    return records, invalid


def normalize_record(record: dict[str, Any], provider_health: dict[str, str]) -> tuple[dict[str, Any], bool]:
    updated = dict(record)
    provider = str(updated.get("provider") or "unknown")
    caller = str(updated.get("caller") or "unknown")
    exit_code = as_int(updated.get("exit_code"))
    status = str(updated.get("status") or ("ok" if exit_code == 0 else "error"))
    changed = False

    health_class = infer_health_class(updated, provider, caller, status, exit_code, provider_health)
    if updated.get("health_class") != health_class:
        updated["health_class"] = health_class
        changed = True

    failure_reason = infer_failure_reason(updated, caller, status, exit_code, health_class)
    if updated.get("failure_reason") != failure_reason:
        updated["failure_reason"] = failure_reason
        changed = True

    return updated, changed


def write_records(path: Path, records: list[dict[str, Any]]) -> Path:
    backup = path.with_suffix(path.suffix + f".bak.{utc_stamp()}")
    if path.exists():
        shutil.copy2(path, backup)
    else:
        path.parent.mkdir(parents=True, exist_ok=True)
    temp = path.with_suffix(path.suffix + ".tmp")
    with temp.open("w", encoding="utf-8") as handle:
        for record in records:
            handle.write(json.dumps(record, ensure_ascii=False) + "\n")
    os.replace(temp, path)
    return backup


def main() -> int:
    parser = argparse.ArgumentParser(description="Normalize LLM adapter telemetry JSONL.")
    parser.add_argument("--path", default=str(DEFAULT_PATH), help="adapter JSONL path")
    parser.add_argument("--write", action="store_true", help="rewrite the JSONL after creating a timestamped backup")
    parser.add_argument("--json", action="store_true", help="print JSON summary")
    args = parser.parse_args()

    path = Path(args.path).expanduser()
    provider_health = load_provider_health()
    records, invalid = load_records(path)
    normalized = []
    changed = 0
    by_health_class: Counter[str] = Counter()
    by_failure_reason: Counter[str] = Counter()

    for record in records:
        updated, did_change = normalize_record(record, provider_health)
        normalized.append(updated)
        changed += 1 if did_change else 0
        by_health_class[str(updated.get("health_class") or "unknown")] += 1
        if updated.get("failure_reason"):
            by_failure_reason[str(updated["failure_reason"])] += 1

    backup = None
    if args.write and changed:
        backup = str(write_records(path, normalized))

    summary = {
        "path": str(path),
        "records": len(records),
        "invalid_lines": invalid,
        "changed": changed,
        "write": bool(args.write),
        "backup": backup,
        "by_health_class": dict(sorted(by_health_class.items())),
        "by_failure_reason": dict(sorted(by_failure_reason.items())),
    }
    if args.json:
        print(json.dumps(summary, ensure_ascii=False, indent=2))
    else:
        print(f"path\t{summary['path']}")
        print(f"records\t{summary['records']}")
        print(f"invalid-lines\t{summary['invalid_lines']}")
        print(f"changed\t{summary['changed']}")
        print(f"write\t{summary['write']}")
        if backup:
            print(f"backup\t{backup}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
