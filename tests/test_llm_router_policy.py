#!/usr/bin/env python3
"""Regression tests for LLM router office-only and local-only policy."""

from __future__ import annotations

import contextlib
import importlib.util
import io
import json
import unittest
from pathlib import Path


ROOT = Path.home() / ".claude"
ROUTER_PATH = ROOT / "scripts" / "llm-router.py"


def load_router_module():
    spec = importlib.util.spec_from_file_location("llm_router_under_test", ROUTER_PATH)
    if spec is None or spec.loader is None:
        raise RuntimeError(f"cannot import {ROUTER_PATH}")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


class RouterPolicyTest(unittest.TestCase):
    def setUp(self) -> None:
        self.router = load_router_module()
        self.registry = {
            "providers": {
                "codex": {"privacy_tier": "external"},
                "gemini": {"privacy_tier": "external"},
                "gemma": {"privacy_tier": "local"},
            },
            "tasks": {
                "private": {
                    "strategy": "first_success",
                    "providers": ["gemma"],
                    "privacy_tier": "local_only",
                    "external_fallback_allowed": False,
                },
                "implement": {
                    "strategy": "first_success",
                    "providers": ["codex", "gemini"],
                    "privacy_tier": "external_ok",
                },
            },
        }

    def test_office_only_policy_requires_explicit_lock_fields(self) -> None:
        valid = {
            "mode": "office_only_remote",
            "policy": "office_only_locked",
            "expected_offline_status": "expected_offline",
            "offsite_status_is_normal": True,
        }
        self.assertTrue(self.router.is_office_only_expected_offline_policy(valid))

        missing_lock = dict(valid)
        missing_lock.pop("policy")
        self.assertFalse(self.router.is_office_only_expected_offline_policy(missing_lock))

    def test_local_only_route_blocks_forced_external_provider(self) -> None:
        policy = self.registry["tasks"]["private"]
        violation = self.router.route_policy_violation(self.registry, policy, ["codex"])
        self.assertEqual(violation, "local_only route forbids external providers: codex")

    def test_local_only_route_allows_local_provider(self) -> None:
        policy = self.registry["tasks"]["private"]
        self.assertIsNone(self.router.route_policy_violation(self.registry, policy, ["gemma"]))

    def test_route_health_marks_office_only_private_as_nonfatal(self) -> None:
        original_detect = self.router.detect_providers
        self.router.detect_providers = lambda _registry: {
            "codex": {"status": "available", "detail": "test"},
            "gemini": {"status": "available", "detail": "test"},
            "gemma": {"status": "expected_offline", "detail": "office-only test"},
        }
        try:
            output = io.StringIO()
            with contextlib.redirect_stdout(output):
                exit_code = self.router.route_health(self.registry, True)
        finally:
            self.router.detect_providers = original_detect

        record = json.loads(output.getvalue())
        self.assertEqual(exit_code, 0)
        self.assertEqual(record["overall_status"], "ok")
        private = record["routes"]["private"]
        self.assertEqual(private["status"], "expected_offline")
        self.assertIsNone(private["policy_violation"])

    def test_route_health_reports_private_external_leakage(self) -> None:
        registry = json.loads(json.dumps(self.registry))
        registry["tasks"]["private"]["providers"] = ["gemma", "codex"]
        original_detect = self.router.detect_providers
        self.router.detect_providers = lambda _registry: {
            "codex": {"status": "available", "detail": "test"},
            "gemini": {"status": "available", "detail": "test"},
            "gemma": {"status": "available", "detail": "test"},
        }
        try:
            output = io.StringIO()
            with contextlib.redirect_stdout(output):
                exit_code = self.router.route_health(registry, True)
        finally:
            self.router.detect_providers = original_detect

        record = json.loads(output.getvalue())
        self.assertEqual(exit_code, 1)
        private = record["routes"]["private"]
        self.assertEqual(private["status"], "unavailable")
        self.assertEqual(private["policy_violation"], "local_only route forbids external providers: codex")


if __name__ == "__main__":
    unittest.main()
