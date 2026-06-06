#!/usr/bin/env python3
"""Run a planned hook wrapper with order-preserving stdin replay."""

from __future__ import annotations

import argparse
import json
import os
import subprocess
import sys
from datetime import datetime, timezone
from pathlib import Path
from typing import Any


ROOT = Path(__file__).resolve().parents[1]
PLAN_PATH = ROOT / "registry" / "hook-wrapper-plan.json"
FIXTURE_PATH = ROOT / "registry" / "hook-replay-fixtures.json"
RUN_LOG_PATH = ROOT / "cache" / "hook-wrapper-runs.jsonl"


def load_json(path: Path) -> dict[str, Any]:
    return json.loads(path.read_text(encoding="utf-8"))


def load_plan(plan_id: str) -> dict[str, Any]:
    report = load_json(PLAN_PATH)
    for plan in report.get("plans", []):
        if plan.get("id") == plan_id:
            return plan
    raise SystemExit(f"unknown hook wrapper plan id: {plan_id}")


def load_fixture(fixture_id: str) -> bytes:
    fixtures = load_json(FIXTURE_PATH)
    for fixture in fixtures.get("fixtures", []):
        if fixture.get("id") == fixture_id:
            return (json.dumps(fixture.get("payload", {}), ensure_ascii=False) + "\n").encode()
    raise SystemExit(f"unknown hook replay fixture id: {fixture_id}")


def read_payload(args: argparse.Namespace) -> bytes:
    if args.fixture:
        return load_fixture(args.fixture)
    return sys.stdin.buffer.read()


def dry_run(plan: dict[str, Any], payload: bytes) -> dict[str, Any]:
    execution_contract = plan.get("execution_contract", {})
    return {
        "ts": datetime.now(timezone.utc).isoformat(timespec="seconds").replace("+00:00", "Z"),
        "mode": "dry-run",
        "plan_id": plan.get("id"),
        "event": plan.get("event"),
        "matcher": plan.get("matcher"),
        "payload_bytes": len(payload),
        "safe_initial_migration": plan.get("safe_initial_migration"),
        "risk_notes": plan.get("risk_notes", []),
        "execution_contract": execution_contract,
        "steps": [
            {
                "order": step.get("order"),
                "hook_id": step.get("hook_id"),
                "command": step.get("command"),
                "timeout_seconds": step.get("timeout_seconds"),
                "blocking": step.get("blocking"),
                "calls_llm": step.get("calls_llm"),
            }
            for step in plan.get("execution", [])
        ],
    }


def parse_env_overrides(items: list[str] | None) -> dict[str, str]:
    overrides: dict[str, str] = {}
    for item in items or []:
        if "=" not in item:
            raise SystemExit(f"--env must be KEY=VALUE: {item}")
        key, value = item.split("=", 1)
        if not key:
            raise SystemExit(f"--env key is empty: {item}")
        overrides[key] = value
    return overrides


def execute_plan(
    plan: dict[str, Any],
    payload: bytes,
    *,
    cwd: Path,
    env_overrides: dict[str, str],
) -> dict[str, Any]:
    results = []
    final_exit_code = 0
    execution_contract = plan.get("execution_contract", {})
    stop_after_blocking_exit = bool(execution_contract.get("stop_after_blocking_exit"))
    preserve_first_nonzero_exit = bool(execution_contract.get("preserve_first_nonzero_exit"))
    child_env = os.environ.copy()
    child_env.update(env_overrides)
    for step in plan.get("execution", []):
        command = step.get("command")
        timeout_seconds = int(step.get("timeout_seconds") or 3)
        try:
            completed = subprocess.run(
                command,
                input=payload,
                capture_output=True,
                shell=True,
                executable="/bin/zsh",
                timeout=timeout_seconds,
                cwd=cwd,
                env=child_env,
            )
            exit_code = completed.returncode
            timed_out = False
            stdout_bytes = len(completed.stdout or b"")
            stderr_bytes = len(completed.stderr or b"")
            if completed.stdout:
                sys.stdout.buffer.write(completed.stdout)
                sys.stdout.buffer.flush()
            if completed.stderr:
                sys.stderr.buffer.write(completed.stderr)
                sys.stderr.buffer.flush()
        except subprocess.TimeoutExpired as error:
            exit_code = 124
            timed_out = True
            stdout_bytes = len(error.stdout or b"")
            stderr_bytes = len(error.stderr or b"")
            if error.stdout:
                sys.stdout.buffer.write(error.stdout)
                sys.stdout.buffer.flush()
            if error.stderr:
                sys.stderr.buffer.write(error.stderr)
                sys.stderr.buffer.flush()

        blocked = bool(step.get("blocking") and exit_code != 0)
        if blocked and (final_exit_code == 0 or not preserve_first_nonzero_exit):
            final_exit_code = exit_code
        results.append(
            {
                "order": step.get("order"),
                "hook_id": step.get("hook_id"),
                "command": command,
                "timeout_seconds": timeout_seconds,
                "exit_code": exit_code,
                "timed_out": timed_out,
                "stdout_bytes": stdout_bytes,
                "stderr_bytes": stderr_bytes,
                "blocked": blocked,
            }
        )
        if blocked and stop_after_blocking_exit:
            break

    return {
        "ts": datetime.now(timezone.utc).isoformat(timespec="seconds").replace("+00:00", "Z"),
        "mode": "execute",
        "plan_id": plan.get("id"),
        "event": plan.get("event"),
        "matcher": plan.get("matcher"),
        "payload_bytes": len(payload),
        "cwd": str(cwd),
        "exit_code": final_exit_code,
        "execution_contract": execution_contract,
        "steps": results,
    }


def append_run_log(result: dict[str, Any]) -> None:
    RUN_LOG_PATH.parent.mkdir(parents=True, exist_ok=True)
    with RUN_LOG_PATH.open("a", encoding="utf-8") as handle:
        handle.write(json.dumps(result, ensure_ascii=False, separators=(",", ":")) + "\n")


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("plan_id", help="plan id from registry/hook-wrapper-plan.json")
    parser.add_argument("--fixture", help="fixture id from registry/hook-replay-fixtures.json")
    parser.add_argument("--execute", action="store_true", help="run hook commands instead of dry-run")
    parser.add_argument(
        "--allow-side-effects",
        action="store_true",
        help="required with --execute because hooks can write files, notify, or call networks",
    )
    parser.add_argument(
        "--print-result",
        action="store_true",
        help="print execute result JSON after forwarding hook output",
    )
    parser.add_argument(
        "--cwd",
        default=str(ROOT),
        help="working directory for child hook commands when executing",
    )
    parser.add_argument(
        "--env",
        action="append",
        default=[],
        help="environment override for child hook commands, formatted KEY=VALUE",
    )
    parser.add_argument(
        "--result-file",
        help="write execute/dry-run result JSON to this path",
    )
    args = parser.parse_args()

    plan = load_plan(args.plan_id)
    payload = read_payload(args)
    if args.execute and not args.allow_side_effects:
        raise SystemExit("--execute requires --allow-side-effects")

    env_overrides = parse_env_overrides(args.env)
    result = (
        execute_plan(
            plan,
            payload,
            cwd=Path(args.cwd).resolve(),
            env_overrides=env_overrides,
        )
        if args.execute
        else dry_run(plan, payload)
    )
    if args.result_file:
        Path(args.result_file).write_text(
            json.dumps(result, ensure_ascii=False, indent=2) + "\n",
            encoding="utf-8",
        )
    if args.execute:
        append_run_log(result)
        if args.print_result:
            print(json.dumps(result, ensure_ascii=False, indent=2))
    else:
        print(json.dumps(result, ensure_ascii=False, indent=2))
    return int(result.get("exit_code", 0))


if __name__ == "__main__":
    raise SystemExit(main())
