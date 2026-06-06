#!/usr/bin/env python3
"""Validate planned hook wrapper activation gates with dry-run fixture replay."""

from __future__ import annotations

import argparse
import json
import subprocess
import sys
from pathlib import Path
from typing import Any


ROOT = Path(__file__).resolve().parents[1]
OUTPUT_PATH = ROOT / "registry" / "hook-wrapper-activation-report.json"


def load_json(relative_path: str) -> dict[str, Any]:
    return json.loads((ROOT / relative_path).read_text(encoding="utf-8"))


def run_dry_run(plan_id: str, fixture_id: str) -> dict[str, Any]:
    output = subprocess.check_output(
        [
            sys.executable,
            str(ROOT / "scripts" / "hook-wrapper-runner.py"),
            plan_id,
            "--fixture",
            fixture_id,
        ],
        cwd=ROOT,
        text=True,
    )
    return json.loads(output)


def validate_result(
    plan: dict[str, Any],
    fixture: dict[str, Any],
    result: dict[str, Any],
) -> dict[str, Any]:
    expected_steps = plan.get("execution", [])
    actual_steps = result.get("steps", [])
    failures: list[str] = []

    if result.get("mode") != "dry-run":
        failures.append("mode is not dry-run")
    if result.get("plan_id") != plan.get("id"):
        failures.append("plan_id mismatch")
    if result.get("event") != plan.get("event"):
        failures.append("event mismatch")
    if result.get("matcher") != plan.get("matcher"):
        failures.append("matcher mismatch")
    if result.get("payload_bytes", 0) <= 0:
        failures.append("empty payload")
    if len(actual_steps) != len(expected_steps):
        failures.append("step count mismatch")

    comparable_fields = [
        "order",
        "hook_id",
        "timeout_seconds",
        "blocking",
        "calls_llm",
    ]
    for index, expected in enumerate(expected_steps):
        if index >= len(actual_steps):
            continue
        actual = actual_steps[index]
        for field in comparable_fields:
            if actual.get(field) != expected.get(field):
                failures.append(f"step {index} {field} mismatch")

    orders = [step.get("order") for step in actual_steps]
    if orders != sorted(orders):
        failures.append("orders are not sorted")

    return {
        "fixture_id": fixture.get("id"),
        "event": fixture.get("event"),
        "matcher": fixture.get("matcher"),
        "payload_bytes": result.get("payload_bytes", 0),
        "step_count": len(actual_steps),
        "orders": orders,
        "status": "pass" if not failures else "fail",
        "failures": failures,
    }


def generate() -> dict[str, Any]:
    wrapper_plan = load_json("registry/hook-wrapper-plan.json")
    activation_gates = load_json("registry/hook-wrapper-activation-gates.json")
    fixtures = load_json("registry/hook-replay-fixtures.json")

    plans_by_id = {
        str(plan.get("id")): plan
        for plan in wrapper_plan.get("plans", [])
    }
    fixtures_by_id = {
        str(fixture.get("id")): fixture
        for fixture in fixtures.get("fixtures", [])
    }

    gate_results = []
    validation_count = 0
    failed_validations = 0
    for gate in activation_gates.get("gates", []):
        plan_id = str(gate.get("plan_id"))
        plan = plans_by_id[plan_id]
        fixture_results = []
        for fixture_id in gate.get("dry_run_fixtures", []):
            fixture = fixtures_by_id[str(fixture_id)]
            result = run_dry_run(plan_id, str(fixture_id))
            validation = validate_result(plan, fixture, result)
            validation_count += 1
            if validation["status"] != "pass":
                failed_validations += 1
            fixture_results.append(validation)

        gate_results.append(
            {
                "plan_id": plan_id,
                "event": gate.get("event"),
                "matcher": gate.get("matcher"),
                "activation_state": gate.get("activation_state"),
                "validation_mode": gate.get("validation_mode"),
                "fixture_count": len(fixture_results),
                "status": (
                    "pass"
                    if all(item["status"] == "pass" for item in fixture_results)
                    else "fail"
                ),
                "fixture_results": fixture_results,
            }
        )

    return {
        "version": 1,
        "description": "Dry-run validation report for planned hook wrapper activation gates.",
        "generated_from": [
            "registry/hook-wrapper-plan.json",
            "registry/hook-wrapper-activation-gates.json",
            "registry/hook-replay-fixtures.json",
        ],
        "runner": "scripts/hook-wrapper-runner.py",
        "gate_count": len(gate_results),
        "validation_count": validation_count,
        "failed_validation_count": failed_validations,
        "status": "pass" if failed_validations == 0 else "fail",
        "gates": gate_results,
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
