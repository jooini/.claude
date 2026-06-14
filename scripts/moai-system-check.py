#!/usr/bin/env python3
"""MoAI/Codex/Agy structural and smoke checker."""

from __future__ import annotations

import argparse
import json
import os
import shutil
import subprocess
import sys
import time
from dataclasses import dataclass
from pathlib import Path
from typing import Any


HOME = Path.home()
ROOT = HOME / ".claude"
CODEX_HOME = HOME / ".codex"
ROUTER = ROOT / "scripts" / "llm-router.sh"
LLM_CALL = ROOT / "scripts" / "llm-call.sh"
GEMINI_WRAPPER = ROOT / "scripts" / "gemini-wrapped.sh"
MOAI_ADK = ROOT / "bin" / "moai-adk"
MOAI_BRIDGE = ROOT / "moai-adk-bridge"
CACHE = ROOT / "cache"
REGISTRY = ROOT / "registry" / "llm-routing.json"
TELEMETRY_REPORT = ROOT / "scripts" / "moai-telemetry-report.py"
E2E_CHECK = ROOT / "scripts" / "moai-e2e-check.py"
REGRESSION_CHECK = ROOT / "scripts" / "moai-regression-check.py"
BRIDGE_LIVE_LOG = CACHE / "moai-bridge-live.jsonl"

EXPECTED_AVAILABLE_PROVIDERS = {
    "codex",
    "gemini",
    "antigravity",
}

EXPECTED_ROUTE_CONFIG = {
    "default": ["codex", "gemini", "gemma"],
    "scan": ["gemini", "codex", "gemma"],
    "implement": ["codex", "gemini"],
    "review": ["codex", "gemini", "gemma"],
    "rescue": ["codex", "gemini", "gemma"],
    "summarize": ["gemma", "codex", "gemini"],
}

EXPECTED_HOOK_FILES = [
    ROOT / "hooks" / "user-prompt-router.sh",
    ROOT / "hooks" / "bash-postproc-sync.sh",
    ROOT / "hooks" / "bash-postproc-async.sh",
    ROOT / "hooks" / "gemini-prescan-enforcer.sh",
    ROOT / "hooks" / "error-codex-remind.sh",
    ROOT / "hooks" / "moai-regression-session-warn.sh",
    ROOT / "hooks" / "codex-silent-json-adapter.sh",
]

BRIDGE_SAMPLE_FILES = [
    MOAI_BRIDGE / "samples" / "sample-auto-scan.json",
    MOAI_BRIDGE / "samples" / "sample-agy-investigate.json",
    MOAI_BRIDGE / "samples" / "sample-codex-implement.json",
]


@dataclass
class Check:
    name: str
    status: str
    detail: str


class CheckRunner:
    def __init__(self, *, strict: bool, verbose: bool) -> None:
        self.strict = strict
        self.verbose = verbose
        self.checks: list[Check] = []

    def pass_(self, name: str, detail: str) -> None:
        self.checks.append(Check(name, "PASS", detail))

    def warn(self, name: str, detail: str) -> None:
        self.checks.append(Check(name, "WARN", detail))

    def fail(self, name: str, detail: str) -> None:
        self.checks.append(Check(name, "FAIL", detail))

    def add_bool(self, name: str, ok: bool, detail: str, *, warning: bool = False) -> None:
        if ok:
            self.pass_(name, detail)
        elif warning:
            self.warn(name, detail)
        else:
            self.fail(name, detail)

    def exit_code(self) -> int:
        return 1 if any(check.status == "FAIL" for check in self.checks) else 0

    def status(self) -> str:
        if any(check.status == "FAIL" for check in self.checks):
            return "FAIL"
        if any(check.status == "WARN" for check in self.checks):
            return "WARN"
        return "PASS"

    def print_text(self) -> None:
        print(f"MoAI system check: {self.status()}")
        for check in self.checks:
            if check.status == "PASS" and not self.verbose:
                continue
            print(f"[{check.status}] {check.name}: {check.detail}")
        if not self.verbose:
            passed = sum(1 for check in self.checks if check.status == "PASS")
            warned = sum(1 for check in self.checks if check.status == "WARN")
            failed = sum(1 for check in self.checks if check.status == "FAIL")
            print(f"summary: pass={passed} warn={warned} fail={failed}")

    def as_json(self) -> dict[str, Any]:
        return {
            "status": self.status(),
            "checks": [check.__dict__ for check in self.checks],
            "summary": {
                "pass": sum(1 for check in self.checks if check.status == "PASS"),
                "warn": sum(1 for check in self.checks if check.status == "WARN"),
                "fail": sum(1 for check in self.checks if check.status == "FAIL"),
            },
        }


def is_executable(path: Path) -> bool:
    return path.exists() and os.access(path, os.X_OK)


def _existing(path: Path) -> str | None:
    return str(path) if path.exists() else None


def read_text(path: Path) -> str:
    try:
        return path.read_text(encoding="utf-8", errors="replace")
    except OSError:
        return ""


def run_command(args: list[str], *, input_text: str | None = None, timeout: int = 180) -> subprocess.CompletedProcess[str]:
    return subprocess.run(
        args,
        input=input_text,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=timeout,
        check=False,
    )


def parse_json_output(process: subprocess.CompletedProcess[str]) -> dict[str, Any] | None:
    try:
        return json.loads(process.stdout)
    except json.JSONDecodeError:
        return None


def read_json_file(path: Path) -> dict[str, Any]:
    try:
        return json.loads(path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError):
        return {}


def append_jsonl(path: Path, record: dict[str, Any]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("a", encoding="utf-8") as handle:
        handle.write(json.dumps(record, ensure_ascii=False) + "\n")


def check_static_files(runner: CheckRunner) -> None:
    required = [
        ROOT / "registry" / "llm-routing.json",
        ROOT / "registry" / "llm-route-health-schema.json",
        ROUTER,
        ROOT / "scripts" / "llm-router.py",
        LLM_CALL,
        GEMINI_WRAPPER,
        TELEMETRY_REPORT,
        E2E_CHECK,
        REGRESSION_CHECK,
        MOAI_ADK,
        MOAI_BRIDGE / "contracts" / "task-envelope.json",
        MOAI_BRIDGE / "bin" / "translate.js",
        MOAI_BRIDGE / "bin" / "run.js",
    ]
    for path in required:
        runner.add_bool("required-file", path.exists(), str(path))

    for path in [ROUTER, LLM_CALL, GEMINI_WRAPPER, TELEMETRY_REPORT, E2E_CHECK, REGRESSION_CHECK, MOAI_ADK]:
        runner.add_bool("executable", is_executable(path), str(path))


def check_cli_paths(runner: CheckRunner) -> None:
    local_bin = HOME / ".local" / "bin"
    agy_path = shutil.which("agy") or _existing(local_bin / "agy")
    codex_path = shutil.which("codex") or str(HOME / ".nvm" / "versions" / "node" / "v22.22.0" / "bin" / "codex")
    gemini_path = shutil.which("gemini") or _existing(local_bin / "gemini")
    node_path = shutil.which("node")

    runner.add_bool("agy-cli", bool(agy_path), agy_path or "missing")
    runner.add_bool("codex-cli", bool(codex_path and Path(codex_path).exists()), codex_path or "missing")
    runner.add_bool("node-cli", bool(node_path), node_path or "missing")
    runner.add_bool("gemini-cli", bool(gemini_path), gemini_path or "missing", warning=True)


def check_hook_wiring(runner: CheckRunner) -> None:
    settings = read_text(ROOT / "settings.json")
    codex_hooks = read_text(CODEX_HOME / "hooks.json")

    expected_settings_fragments = [
        '"GEMINI_CLI": "agy"',
        "Skill(ask-codex)",
        "Skill(ask-gemini)",
        "Bash(~/.agents/scripts/llm-router.sh *)",
        "Bash(/Users/leonard/.agents/scripts/llm-router.sh *)",
        "user-prompt-router.sh",
    ]
    for fragment in expected_settings_fragments:
        runner.add_bool("claude-settings", fragment in settings, fragment)

    expected_codex_fragments = [
        "sync-external.sh --quiet",
        "user-prompt-router.sh",
        "codex-silent-json-adapter.sh",
        "hook-wrapper-runner.py stop-composite",
    ]
    for fragment in expected_codex_fragments:
        runner.add_bool("codex-hooks", fragment in codex_hooks, fragment)

    for path in EXPECTED_HOOK_FILES:
        runner.add_bool("hook-file", is_executable(path), str(path))


def check_office_only_policy(runner: CheckRunner) -> None:
    registry = read_json_file(REGISTRY)
    gemma = ((registry.get("providers") or {}).get("gemma") or {})
    availability = gemma.get("availability") or {}
    private = ((registry.get("tasks") or {}).get("private") or {})

    expected_availability = {
        "mode": "office_only_remote",
        "policy": "office_only_locked",
        "expected_offline_status": "expected_offline",
        "offsite_status_is_normal": True,
        "strict_required_for_office_check": True,
        "external_fallback_allowed": False,
    }
    for key, expected in expected_availability.items():
        actual = availability.get(key)
        runner.add_bool(f"office-only:gemma:{key}", actual == expected, f"{actual!r}")

    runner.add_bool("office-only:private:providers", private.get("providers") == ["gemma"], str(private.get("providers")))
    runner.add_bool("office-only:private:privacy", private.get("privacy_tier") == "local_only", str(private.get("privacy_tier")))
    runner.add_bool(
        "office-only:private:no-external-fallback",
        private.get("external_fallback_allowed") is False,
        str(private.get("external_fallback_allowed")),
    )

    process = run_command(
        [str(ROUTER), "private", "--caller", "moai-system-check-policy", "--provider", "codex", "--prompt", "x", "--dry-run"],
        timeout=30,
    )
    detail = process.stderr.strip().splitlines()[0] if process.stderr.strip() else f"exit={process.returncode}"
    runner.add_bool(
        "office-only:private:forced-external-blocked",
        process.returncode != 0 and "forbids external providers" in process.stderr,
        detail,
    )


def check_doctor(runner: CheckRunner, *, live: bool, live_timeout: int) -> dict[str, Any] | None:
    args = [str(ROUTER), "doctor", "--json"]
    if live:
        args.extend(["--live", "--provider", "codex", "--provider", "gemini", "--live-timeout", str(live_timeout)])

    process = run_command(args, timeout=max(60, live_timeout * 3))
    record = parse_json_output(process)
    runner.add_bool("doctor-json", record is not None, f"exit={process.returncode}")
    if record is None:
        if process.stderr:
            runner.fail("doctor-stderr", process.stderr.strip().splitlines()[0])
        return None

    runner.add_bool("doctor-status", record.get("overall_status") == "ok", str(record.get("overall_status")))
    providers = record.get("providers") or {}
    for provider in sorted(EXPECTED_AVAILABLE_PROVIDERS):
        status = (providers.get(provider) or {}).get("status")
        runner.add_bool(f"provider:{provider}", status == "available", str(status))

    gemma_status = (providers.get("gemma") or {}).get("status")
    if gemma_status == "expected_offline" and not runner.strict:
        runner.pass_("provider:gemma", "expected_offline accepted by office-only policy")
    else:
        runner.add_bool("provider:gemma", gemma_status == "available", str(gemma_status), warning=not runner.strict)

    if live:
        results = ((record.get("live_smoke") or {}).get("results") or [])
        for item in results:
            provider = item.get("provider")
            status = item.get("status")
            detail = f"status={status} duration={item.get('duration_ms')}ms stdout={item.get('stdout_preview')!r}"
            runner.add_bool(f"live:{provider}", status == "ok", detail)

    return record


def check_route_health(runner: CheckRunner) -> dict[str, Any] | None:
    process = run_command([str(ROUTER), "route-health", "--json"])
    record = parse_json_output(process)
    runner.add_bool("route-health-json", record is not None, f"exit={process.returncode}")
    if record is None:
        if process.stderr:
            runner.fail("route-health-stderr", process.stderr.strip().splitlines()[0])
        return None

    runner.add_bool("route-health-status", record.get("overall_status") == "ok", str(record.get("overall_status")))
    cache = record.get("health_cache") or {}
    runner.add_bool("health-cache-fresh", not bool(cache.get("is_stale")), f"age={cache.get('age_seconds')}s")

    routes = record.get("routes") or {}
    for route_name, expected_config in EXPECTED_ROUTE_CONFIG.items():
        route = routes.get(route_name) or {}
        configured = route.get("configured_providers") or []
        status = route.get("status")
        runner.add_bool(f"route-config:{route_name}", configured == expected_config, f"{configured}")
        runner.add_bool(f"route-status:{route_name}", status == "ok", str(status))

    private_status = (routes.get("private") or {}).get("status")
    if private_status == "expected_offline" and not runner.strict:
        runner.pass_("route-status:private", "expected_offline accepted; private route is office-only")
    else:
        runner.add_bool("route-status:private", private_status == "ok", str(private_status), warning=not runner.strict)

    return record


def check_dry_routes(runner: CheckRunner, route_health: dict[str, Any] | None) -> None:
    routes = (route_health or {}).get("routes") or {}
    route_names = ["default", "scan", "implement", "review", "rescue", "summarize", "private", "default"]

    for route_name in route_names:
        process = run_command(
            [str(ROUTER), route_name, "--caller", "moai-system-check", "--prompt", "x", "--dry-run"],
            timeout=30,
        )
        route_status = (routes.get(route_name) or {}).get("status")
        if route_status == "expected_offline":
            ok = process.returncode != 0 and "local_only" in process.stderr
            if ok and not runner.strict:
                runner.pass_(f"dry-run:{route_name}", process.stderr.strip() or "expected_offline accepted by office-only policy")
            else:
                runner.add_bool(f"dry-run:{route_name}", ok, process.stderr.strip() or f"exit={process.returncode}", warning=not runner.strict)
            continue

        record = parse_json_output(process)
        if process.returncode != 0 or record is None:
            detail = process.stderr.strip().splitlines()[0] if process.stderr.strip() else f"exit={process.returncode}"
            runner.fail(f"dry-run:{route_name}", detail)
            continue

        expected = (routes.get(route_name) or {}).get("available_providers") or []
        actual = record.get("providers") or []
        runner.add_bool(f"dry-run:{route_name}", actual == expected, f"providers={actual}, expected={expected}")


def check_bridge_samples(runner: CheckRunner) -> None:
    for sample in BRIDGE_SAMPLE_FILES:
        runner.add_bool("bridge-sample-file", sample.exists(), str(sample))
        if not sample.exists():
            continue

        process = run_command([str(MOAI_ADK), "--task", str(sample)], timeout=30)
        try:
            result = json.loads(process.stdout)
        except json.JSONDecodeError:
            detail = process.stderr.strip().splitlines()[0] if process.stderr.strip() else "invalid json"
            runner.fail(f"bridge-sample:{sample.name}", detail)
            continue

        required_keys = {"status", "artifacts", "next_step", "state"}
        missing = sorted(required_keys - set(result))
        ok = process.returncode == 0 and result.get("status") == "succeeded" and not missing
        runner.add_bool(
            f"bridge-sample:{sample.name}",
            ok,
            f"status={result.get('status')} missing={missing}",
        )


def bridge_live_task(*, runner_name: str, phase: str, timeout_ms: int) -> str:
    return json.dumps(
        {
            "task_id": f"moai-live-{runner_name}-{phase}",
            "runner": runner_name,
            "phase": phase,
            "input": "Smoke test. Reply with only: ok. Do not edit files.",
            "instructions": "This is a read-only MoAI bridge live check. Do not modify files.",
            "cwd": str(ROOT),
            "retry": 0,
            "dry_run": False,
            "timeout_ms": timeout_ms,
            "labels": ["moai-system-check", "live", runner_name],
            "preferred_runners": [runner_name],
            "next_action": "handoff",
        },
        ensure_ascii=False,
    )


def check_bridge_live(runner: CheckRunner, *, live_timeout: int) -> None:
    timeout_ms = max(1000, live_timeout * 1000)
    tasks = [
        ("agy", "investigate"),
        ("codex", "handoff"),
    ]

    for runner_name, phase in tasks:
        started = time.time()
        process = run_command(
            [str(MOAI_ADK)],
            input_text=bridge_live_task(runner_name=runner_name, phase=phase, timeout_ms=timeout_ms),
            timeout=max(30, live_timeout + 15),
        )
        try:
            result = json.loads(process.stdout)
        except json.JSONDecodeError:
            detail = process.stderr.strip().splitlines()[0] if process.stderr.strip() else "invalid json"
            runner.fail(f"bridge-live:{runner_name}", detail)
            append_jsonl(
                BRIDGE_LIVE_LOG,
                {
                    "schema_version": 1,
                    "timestamp": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()),
                    "caller": "moai-system-check",
                    "runner": runner_name,
                    "phase": phase,
                    "status": "invalid_json",
                    "exit_code": process.returncode,
                    "duration_ms": int((time.time() - started) * 1000),
                    "stderr_preview": detail,
                },
            )
            continue

        logs = result.get("logs") or []
        artifacts = result.get("artifacts") or []
        log_runner = logs[0].get("runner") if logs and isinstance(logs[0], dict) else None
        artifact_source = artifacts[0].get("source") if artifacts and isinstance(artifacts[0], dict) else None
        command = artifacts[0].get("command") if artifacts and isinstance(artifacts[0], dict) else ""
        ok = (
            process.returncode == 0
            and result.get("status") == "succeeded"
            and log_runner == runner_name
            and artifact_source == runner_name
        )
        detail = (
            f"status={result.get('status')} runner={log_runner} "
            f"artifact_source={artifact_source} command={command}"
        )
        runner.add_bool(f"bridge-live:{runner_name}", ok, detail)
        append_jsonl(
            BRIDGE_LIVE_LOG,
            {
                "schema_version": 1,
                "timestamp": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()),
                "caller": "moai-system-check",
                "runner": runner_name,
                "phase": phase,
                "status": result.get("status"),
                "exit_code": process.returncode,
                "duration_ms": int((time.time() - started) * 1000),
                "log_runner": log_runner,
                "artifact_source": artifact_source,
                "command": command,
            },
        )


def check_logs_and_handoff(runner: CheckRunner, *, started_at: float, live: bool) -> None:
    router_log = CACHE / "llm-router-calls.jsonl"
    adapter_log = CACHE / "llm-adapter-calls.jsonl"
    agy_log = CACHE / "agy-calls.jsonl"
    handoff = CACHE / "llm-handoff" / "current.json"

    for path in [router_log, adapter_log, handoff]:
        runner.add_bool("cache-file", path.exists(), str(path))

    if BRIDGE_LIVE_LOG.exists():
        runner.pass_("cache-file", str(BRIDGE_LIVE_LOG))
    elif live:
        runner.fail("cache-file", f"{BRIDGE_LIVE_LOG} missing after live bridge check")
    else:
        runner.warn("cache-file", f"{BRIDGE_LIVE_LOG} missing until first live bridge check")

    if agy_log.exists():
        runner.pass_("cache-file", str(agy_log))
    else:
        runner.warn("cache-file", f"{agy_log} missing until first agy call")

    if router_log.exists():
        runner.add_bool("router-log-updated", router_log.stat().st_mtime >= started_at - 2, str(router_log))

    if handoff.exists():
        try:
            record = json.loads(handoff.read_text(encoding="utf-8"))
        except json.JSONDecodeError:
            runner.fail("handoff-json", "invalid JSON")
        else:
            ok = record.get("caller") == "moai-system-check" and record.get("task") == "default"
            detail = f"caller={record.get('caller')} task={record.get('task')}"
            runner.add_bool("handoff-updated", ok, detail)

    if live:
        if adapter_log.exists():
            runner.add_bool("adapter-log-updated", adapter_log.stat().st_mtime >= started_at - 2, str(adapter_log))
        if agy_log.exists():
            runner.add_bool("agy-log-updated", agy_log.stat().st_mtime >= started_at - 2, str(agy_log))
        if BRIDGE_LIVE_LOG.exists():
            runner.add_bool("bridge-live-log-updated", BRIDGE_LIVE_LOG.stat().st_mtime >= started_at - 2, str(BRIDGE_LIVE_LOG))


def check_telemetry_report(runner: CheckRunner, *, live: bool) -> None:
    process = run_command([str(TELEMETRY_REPORT), "--json", "--write", "--days", "7"], timeout=30)
    record = parse_json_output(process)
    runner.add_bool("telemetry-report-json", record is not None, f"exit={process.returncode}")
    if record is None:
        if process.stderr:
            runner.fail("telemetry-report-stderr", process.stderr.strip().splitlines()[0])
        return

    runner.add_bool("telemetry-report-status", record.get("status") in {"ok", "degraded"}, str(record.get("status")))
    e2e = record.get("e2e_evidence") or {}
    if live:
        runner.add_bool("telemetry-report:e2e", e2e.get("complete") is True, str(e2e))
    else:
        runner.add_bool("telemetry-report:e2e-shape", "complete" in e2e, str(e2e))


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description="Validate MoAI-ADK + Agy + Codex routing structure.")
    parser.add_argument("--live", action="store_true", help="run real router and MoAI bridge smoke calls")
    parser.add_argument("--live-timeout", type=int, default=60, help="seconds for live provider smoke calls")
    parser.add_argument("--strict", action="store_true", help="office network mode: require office-only Gemma/Ollama to be reachable")
    parser.add_argument("--json", action="store_true", help="print machine-readable result")
    parser.add_argument("--verbose", action="store_true", help="print passing checks too")
    return parser


def main() -> int:
    args = build_parser().parse_args()
    started_at = time.time()
    runner = CheckRunner(strict=args.strict, verbose=args.verbose)

    check_static_files(runner)
    check_cli_paths(runner)
    check_hook_wiring(runner)
    check_office_only_policy(runner)
    check_doctor(runner, live=args.live, live_timeout=args.live_timeout)
    route_health = check_route_health(runner)
    check_dry_routes(runner, route_health)
    check_bridge_samples(runner)
    if args.live:
        check_bridge_live(runner, live_timeout=args.live_timeout)
    check_logs_and_handoff(runner, started_at=started_at, live=args.live)
    check_telemetry_report(runner, live=args.live)

    if args.json:
        print(json.dumps(runner.as_json(), ensure_ascii=False, indent=2))
    else:
        runner.print_text()

    return runner.exit_code()


if __name__ == "__main__":
    raise SystemExit(main())
