#!/usr/bin/env python3
"""End-to-end MoAI router, bridge, telemetry, and project workflow check."""

from __future__ import annotations

import argparse
import json
import subprocess
import sys
from dataclasses import dataclass
from pathlib import Path


HOME = Path.home()
ROOT = HOME / ".claude"
WORKSPACE = HOME / "Workspace"
ROUTER = ROOT / "scripts" / "llm-router.sh"
SYSTEM_CHECK = HOME / "bin" / "moai-system-check"
TELEMETRY_REPORT = HOME / "bin" / "moai-telemetry-report"
HANDOFF = ROOT / "cache" / "llm-handoff" / "current.json"


@dataclass
class StepResult:
    name: str
    ok: bool
    detail: str


def run_command(
    name: str,
    args: list[str],
    *,
    cwd: Path,
    timeout: int = 180,
    allow_failure: bool = False,
) -> StepResult:
    process = subprocess.run(
        args,
        cwd=str(cwd),
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=timeout,
        check=False,
    )
    ok = process.returncode == 0
    output = (process.stdout.strip() or process.stderr.strip() or f"exit={process.returncode}")
    if allow_failure:
        ok = True
    return StepResult(name, ok, output.splitlines()[0] if output else f"exit={process.returncode}")


def find_default_project() -> Path:
    preferred = [
        WORKSPACE / "identity-hub-frontend",
        WORKSPACE / "query-canvas",
        WORKSPACE / "ai-playground",
    ]
    for project in preferred:
        if (project / ".git").exists():
            return project
    for git_dir in sorted(WORKSPACE.glob("*/.git")):
        if git_dir.is_dir():
            return git_dir.parent
    return ROOT


def read_handoff() -> dict:
    try:
        value = json.loads(HANDOFF.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError):
        return {}
    return value if isinstance(value, dict) else {}


def verify_handoff(*, project: Path, task: str, caller: str, require_active_provider: bool) -> StepResult:
    record = read_handoff()
    active_providers = record.get("active_providers") or []
    ok = (
        record.get("cwd") == str(project)
        and record.get("task") == task
        and record.get("caller") == caller
        and (not require_active_provider or bool(active_providers))
    )
    detail = (
        f"cwd={record.get('cwd')} task={record.get('task')} "
        f"caller={record.get('caller')} active={active_providers}"
    )
    return StepResult("project-handoff", ok, detail)


def print_results(results: list[StepResult]) -> None:
    status = "PASS" if all(item.ok for item in results) else "FAIL"
    print(f"MoAI E2E check: {status}")
    for item in results:
        prefix = "PASS" if item.ok else "FAIL"
        print(f"[{prefix}] {item.name}: {item.detail}")


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description="Run full MoAI E2E regression checks.")
    parser.add_argument("--project", type=Path, default=find_default_project(), help="Workspace project used for project-flow verification")
    parser.add_argument("--current-minutes", type=int, default=60, help="freshness window for telemetry current status")
    parser.add_argument("--live-timeout", type=int, default=60, help="live provider timeout seconds")
    parser.add_argument("--skip-live", action="store_true", help="skip live provider and bridge smoke checks")
    parser.add_argument("--skip-project-live", action="store_true", help="skip read-only provider call in the project cwd")
    return parser


def main() -> int:
    args = build_parser().parse_args()
    project = args.project.expanduser().resolve()
    results: list[StepResult] = []

    results.append(
        run_command(
            "unit-tests",
            ["python3", "-m", "unittest", "discover", "-s", str(ROOT / "tests")],
            cwd=ROOT,
            timeout=60,
        )
    )
    results.append(run_command("system-check", [str(SYSTEM_CHECK)], cwd=HOME, timeout=120))

    if not args.skip_live:
        results.append(
            run_command(
                "system-check-live",
                [str(SYSTEM_CHECK), "--live", "--live-timeout", str(args.live_timeout)],
                cwd=HOME,
                timeout=max(90, args.live_timeout * 4),
            )
        )

    forced_private = subprocess.run(
        [str(ROUTER), "private", "--caller", "moai-e2e-policy", "--provider", "codex", "--prompt", "x", "--dry-run"],
        cwd=str(HOME),
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=30,
        check=False,
    )
    results.append(
        StepResult(
            "private-external-block",
            forced_private.returncode != 0 and "forbids external providers" in forced_private.stderr,
            forced_private.stderr.strip().splitlines()[0] if forced_private.stderr.strip() else f"exit={forced_private.returncode}",
        )
    )

    project_exists = project.exists() and (project / ".git").exists()
    results.append(StepResult("project-selected", project_exists, str(project)))
    if project_exists:
        results.append(
            run_command(
                "project-router-dry-run",
                [str(ROUTER), "scan", "--caller", "moai-e2e-project-dry-run", "--prompt", "Project route dry-run", "--dry-run"],
                cwd=project,
                timeout=60,
            )
        )
        results.append(
            verify_handoff(
                project=project,
                task="scan",
                caller="moai-e2e-project-dry-run",
                require_active_provider=False,
            )
        )
        if not args.skip_project_live:
            results.append(
                run_command(
                    "project-provider-live",
                    [
                        str(ROUTER),
                        "implement",
                        "--caller",
                        "moai-e2e-project",
                        "--provider",
                        "codex",
                        "--timeout",
                        "90",
                        "--prompt",
                        "Read-only MoAI project workflow smoke. Reply with only: project-ok. Do not edit files.",
                    ],
                    cwd=project,
                    timeout=120,
                )
            )
            results.append(
                verify_handoff(
                    project=project,
                    task="implement",
                    caller="moai-e2e-project",
                    require_active_provider=True,
                )
            )

    results.append(
        run_command(
            "telemetry-current-e2e",
            [
                str(TELEMETRY_REPORT),
                "--days",
                "7",
                "--current-minutes",
                str(args.current_minutes),
                "--write",
                "--require-e2e",
            ],
            cwd=HOME,
            timeout=60,
        )
    )

    print_results(results)
    return 0 if all(item.ok for item in results) else 1


if __name__ == "__main__":
    raise SystemExit(main())
