#!/usr/bin/env python3
"""Regression tests for MoAI telemetry current/history split."""

from __future__ import annotations

import importlib.util
import json
import tempfile
import unittest
from datetime import datetime, timedelta, timezone
from pathlib import Path


ROOT = Path.home() / ".claude"
REPORT_PATH = ROOT / "scripts" / "moai-telemetry-report.py"


def load_report_module():
    spec = importlib.util.spec_from_file_location("moai_telemetry_report_under_test", REPORT_PATH)
    if spec is None or spec.loader is None:
        raise RuntimeError(f"cannot import {REPORT_PATH}")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def iso(value: datetime) -> str:
    return value.astimezone(timezone.utc).isoformat(timespec="seconds").replace("+00:00", "Z")


def write_jsonl(path: Path, records: list[dict]) -> None:
    path.write_text(
        "".join(json.dumps(record) + "\n" for record in records),
        encoding="utf-8",
    )


class TelemetryReportTest(unittest.TestCase):
    def test_current_ok_can_coexist_with_degraded_history(self) -> None:
        module = load_report_module()
        now = datetime.now(timezone.utc)
        old = now - timedelta(hours=3)
        recent = now - timedelta(minutes=5)

        with tempfile.TemporaryDirectory() as temp_dir:
            temp = Path(temp_dir)
            module.ROUTER_LOG = temp / "router.jsonl"
            module.ADAPTER_LOG = temp / "adapter.jsonl"
            module.AGY_LOG = temp / "agy.jsonl"
            module.BRIDGE_LOG = temp / "bridge.jsonl"
            module.HANDOFF = temp / "handoff.json"

            write_jsonl(
                module.ROUTER_LOG,
                [
                    {
                        "timestamp": iso(recent),
                        "caller": "moai-system-check",
                        "task": "default",
                        "status": "dry-run",
                        "providers": ["codex", "gemini"],
                    }
                ],
            )
            write_jsonl(
                module.ADAPTER_LOG,
                [
                    {
                        "timestamp": iso(old),
                        "provider": "gemini",
                        "caller": "manual",
                        "status": "error",
                        "health_class": "runtime_failure",
                        "duration_ms": 100,
                        "failure_reason": "runtime_error",
                    },
                    {
                        "timestamp": iso(recent),
                        "provider": "codex",
                        "caller": "doctor-live:doctor-live:codex",
                        "status": "ok",
                        "health_class": "ok",
                        "duration_ms": 100,
                    },
                    {
                        "timestamp": iso(recent),
                        "provider": "gemini",
                        "caller": "doctor-live:doctor-live:gemini",
                        "status": "ok",
                        "health_class": "ok",
                        "duration_ms": 100,
                    },
                ],
            )
            write_jsonl(
                module.AGY_LOG,
                [
                    {
                        "timestamp": iso(recent),
                        "caller": "doctor-live:doctor-live:gemini",
                        "status": "ok",
                        "duration_ms": 100,
                    }
                ],
            )
            write_jsonl(
                module.BRIDGE_LOG,
                [
                    {
                        "timestamp": iso(recent),
                        "runner": "agy",
                        "phase": "investigate",
                        "status": "succeeded",
                    },
                    {
                        "timestamp": iso(recent),
                        "runner": "codex",
                        "phase": "handoff",
                        "status": "succeeded",
                    },
                ],
            )
            module.HANDOFF.write_text(
                json.dumps(
                    {
                        "updated_at": iso(recent),
                        "task": "default",
                        "caller": "moai-system-check",
                        "active_providers": [],
                    }
                ),
                encoding="utf-8",
            )

            report = module.build_report(7, 60)

        self.assertEqual(report["status"], "ok")
        self.assertEqual(report["current"]["status"], "ok")
        self.assertTrue(report["current"]["e2e_evidence"]["complete"])
        self.assertEqual(report["history"]["status"], "degraded")
        self.assertEqual(report["history"]["adapter_health_relevant_errors"], 1)

    def test_current_status_is_stale_without_recent_e2e(self) -> None:
        module = load_report_module()
        old = datetime.now(timezone.utc) - timedelta(hours=2)

        with tempfile.TemporaryDirectory() as temp_dir:
            temp = Path(temp_dir)
            module.ROUTER_LOG = temp / "router.jsonl"
            module.ADAPTER_LOG = temp / "adapter.jsonl"
            module.AGY_LOG = temp / "agy.jsonl"
            module.BRIDGE_LOG = temp / "bridge.jsonl"
            module.HANDOFF = temp / "handoff.json"

            write_jsonl(module.ROUTER_LOG, [{"timestamp": iso(old), "caller": "moai-system-check"}])
            write_jsonl(module.ADAPTER_LOG, [])
            write_jsonl(module.AGY_LOG, [])
            write_jsonl(module.BRIDGE_LOG, [])

            report = module.build_report(7, 60)

        self.assertEqual(report["status"], "stale")
        self.assertFalse(report["current"]["e2e_evidence"]["complete"])


if __name__ == "__main__":
    unittest.main()
