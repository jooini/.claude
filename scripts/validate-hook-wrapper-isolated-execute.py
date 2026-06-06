#!/usr/bin/env python3
"""Run selected planned hook wrappers in an isolated execute harness."""

from __future__ import annotations

import argparse
import json
import os
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path
from typing import Any


ROOT = Path(__file__).resolve().parents[1]
OUTPUT_PATH = ROOT / "registry" / "hook-wrapper-isolated-execute-report.json"


def load_json(relative_path: str) -> dict[str, Any]:
    return json.loads((ROOT / relative_path).read_text(encoding="utf-8"))


def write_executable(path: Path, content: str) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(content, encoding="utf-8")
    path.chmod(0o755)


def run_command(args: list[str], cwd: Path) -> None:
    subprocess.check_call(args, cwd=cwd, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)


def setup_home(home: Path, stub_bin: Path) -> None:
    write_executable(
        home / ".claude" / "scripts" / "llm-call.sh",
        """#!/bin/zsh
mkdir -p "$HOME/.claude/cache"
printf '%s\\n' "$*" >> "$HOME/.claude/cache/llm-call-stub.log"
echo "[stub llm-call] $1"
exit 0
""",
    )
    write_executable(
        home / ".claude" / "hooks" / "_lib" / "ollama-available.sh",
        """#!/bin/zsh
ollama_available() {
  return 1
}
""",
    )
    write_executable(
        home / ".claude" / "hooks" / "_lib" / "outcome-log.sh",
        """#!/bin/zsh
outcome_log() {
  mkdir -p "$HOME/.claude/cache"
  printf '%s\\n' "$*" >> "$HOME/.claude/cache/outcome-log-stub.log"
}
""",
    )
    (home / ".claude" / "agents" / "knowledge").mkdir(parents=True, exist_ok=True)
    (home / ".claude" / "cache").mkdir(parents=True, exist_ok=True)

    write_executable(
        stub_bin / "say",
        """#!/bin/zsh
mkdir -p "$HOME/.claude/cache"
printf 'say %s\\n' "$*" >> "$HOME/.claude/cache/audio-stub.log"
exit 0
""",
    )
    write_executable(
        stub_bin / "afplay",
        """#!/bin/zsh
mkdir -p "$HOME/.claude/cache"
printf 'afplay %s\\n' "$*" >> "$HOME/.claude/cache/audio-stub.log"
exit 0
""",
    )
    write_executable(
        stub_bin / "osascript",
        """#!/bin/zsh
mkdir -p "$HOME/.claude/cache"
printf 'osascript %s\\n' "$*" >> "$HOME/.claude/cache/notification-stub.log"
exit 0
""",
    )
    write_executable(
        stub_bin / "curl",
        """#!/bin/zsh
mkdir -p "$HOME/.claude/cache"
printf 'curl %s\\n' "$*" >> "$HOME/.claude/cache/network-stub.log"
printf '[]\\n'
exit 0
""",
    )


def setup_project(project: Path) -> None:
    project.mkdir(parents=True, exist_ok=True)
    run_command(["git", "init"], project)
    run_command(["git", "config", "user.email", "fixture@example.com"], project)
    run_command(["git", "config", "user.name", "Fixture User"], project)
    (project / "pyproject.toml").write_text("[project]\nname = \"fixture\"\nversion = \"0.0.0\"\n", encoding="utf-8")
    source_dir = project / "src"
    source_dir.mkdir(exist_ok=True)
    (source_dir / "fixture.py").write_text("print('fixture')\n", encoding="utf-8")
    run_command(["git", "add", "."], project)
    run_command(["git", "commit", "-m", "초기 커밋"], project)


def payload(event: str, tool_name: str, cwd: Path, tool_input: dict[str, Any]) -> bytes:
    return (
        json.dumps(
            {
                "session_id": "isolated-execute-fixture",
                "transcript_path": "/tmp/claude-isolated-execute-transcript.jsonl",
                "cwd": str(cwd),
                "hook_event_name": event,
                "tool_name": tool_name,
                "tool_input": tool_input,
            },
            ensure_ascii=False,
        )
        + "\n"
    ).encode()


def stop_payload(cwd: Path) -> bytes:
    return (
        json.dumps(
            {
                "session_id": "isolated-stop-composite",
                "transcript_path": "/tmp/claude-isolated-stop-transcript.jsonl",
                "cwd": str(cwd),
                "hook_event_name": "Stop",
            },
            ensure_ascii=False,
        )
        + "\n"
    ).encode()


def scenario_payload(scenario_id: str, project: Path) -> tuple[str, bytes]:
    if scenario_id == "git-commit-non-korean-block":
        return (
            "pretooluse-git-commit-pipeline",
            payload("PreToolUse", "Bash", project, {"command": "git commit -m \"fix\""}),
        )
    if scenario_id == "git-commit-coauthor-block":
        return (
            "pretooluse-git-commit-pipeline",
            payload(
                "PreToolUse",
                "Bash",
                project,
                {
                    "command": (
                        "git commit -m \"작업 정리\" "
                        "-m \"Co-Authored-By: Other <other@example.com>\""
                    )
                },
            ),
        )
    if scenario_id == "gh-pr-create-safe-skip":
        return (
            "pretooluse-gh-pr-pipeline",
            payload(
                "PreToolUse",
                "Bash",
                project,
                {"command": "gh pr create --title \"작업 정리\" --body \"변경 내용을 정리합니다.\""},
            ),
        )
    if scenario_id == "edit-write-large-direct-block":
        content = "\n".join(f"line {number:02d}" for number in range(1, 52)) + "\n"
        return (
            "pretooluse-edit-write-event-matcher",
            payload(
                "PreToolUse",
                "Write",
                project,
                {
                    "file_path": str(project / "src" / "large_direct.py"),
                    "content": content,
                },
            ),
        )
    if scenario_id == "agent-reviewer-safe-stubbed":
        return (
            "pretooluse-agent-event-matcher",
            payload(
                "PreToolUse",
                "Agent",
                project,
                {
                    "subagent_type": "code-reviewer",
                    "description": "fixture review task",
                    "prompt": "Review the current diff.",
                },
            ),
        )
    if scenario_id == "stop-composite-safe-stubbed":
        return (
            "stop-composite-notification-output-router",
            stop_payload(project),
        )
    raise KeyError(scenario_id)


SCENARIOS = [
    {
        "id": "git-commit-non-korean-block",
        "expected_exit_code": 2,
        "expected_executed_step_count": 3,
        "expected_blocked_hook_id": "PreToolUse:1:2",
    },
    {
        "id": "git-commit-coauthor-block",
        "expected_exit_code": 2,
        "expected_executed_step_count": 4,
        "expected_blocked_hook_id": "PreToolUse:1:3",
    },
    {
        "id": "gh-pr-create-safe-skip",
        "expected_exit_code": 0,
        "expected_executed_step_count": 2,
        "expected_blocked_hook_id": None,
    },
    {
        "id": "edit-write-large-direct-block",
        "expected_exit_code": 2,
        "expected_executed_step_count": 2,
        "expected_blocked_hook_id": "PreToolUse:3:1",
    },
    {
        "id": "agent-reviewer-safe-stubbed",
        "expected_exit_code": 0,
        "expected_executed_step_count": 4,
        "expected_blocked_hook_id": None,
    },
    {
        "id": "stop-composite-safe-stubbed",
        "expected_exit_code": 0,
        "expected_executed_step_count": 11,
        "expected_blocked_hook_id": None,
    },
]


def run_scenario(
    scenario: dict[str, Any],
    *,
    home: Path,
    stub_bin: Path,
    project: Path,
) -> dict[str, Any]:
    plan_id, scenario_input = scenario_payload(str(scenario["id"]), project)
    result_file = project.parent / f"{scenario['id']}.result.json"
    env_path = f"{stub_bin}{os.pathsep}{os.environ.get('PATH', '')}"
    completed = subprocess.run(
        [
            sys.executable,
            str(ROOT / "scripts" / "hook-wrapper-runner.py"),
            plan_id,
            "--execute",
            "--allow-side-effects",
            "--cwd",
            str(project),
            "--env",
            f"HOME={home}",
            "--env",
            f"PATH={env_path}",
            "--env",
            "CLAUDE_SESSION_ID=isolated-execute-fixture",
            "--result-file",
            str(result_file),
        ],
        input=scenario_input,
        cwd=ROOT,
        capture_output=True,
    )
    result = json.loads(result_file.read_text(encoding="utf-8"))
    steps = result.get("steps", [])
    blocked_steps = [step for step in steps if step.get("blocked")]
    blocked_hook_id = blocked_steps[0].get("hook_id") if blocked_steps else None

    failures: list[str] = []
    if completed.returncode != scenario["expected_exit_code"]:
        failures.append("runner exit code mismatch")
    if result.get("exit_code") != scenario["expected_exit_code"]:
        failures.append("result exit code mismatch")
    if len(steps) != scenario["expected_executed_step_count"]:
        failures.append("executed step count mismatch")
    if blocked_hook_id != scenario.get("expected_blocked_hook_id"):
        failures.append("blocked hook mismatch")
    if any(step.get("timed_out") for step in steps):
        failures.append("step timed out")

    return {
        "id": scenario["id"],
        "plan_id": plan_id,
        "status": "pass" if not failures else "fail",
        "expected_exit_code": scenario["expected_exit_code"],
        "actual_exit_code": result.get("exit_code"),
        "runner_returncode": completed.returncode,
        "expected_executed_step_count": scenario["expected_executed_step_count"],
        "actual_executed_step_count": len(steps),
        "expected_blocked_hook_id": scenario.get("expected_blocked_hook_id"),
        "actual_blocked_hook_id": blocked_hook_id,
        "stdout_bytes": len(completed.stdout or b""),
        "stderr_bytes": len(completed.stderr or b""),
        "steps": [
            {
                "order": step.get("order"),
                "hook_id": step.get("hook_id"),
                "exit_code": step.get("exit_code"),
                "blocked": step.get("blocked"),
                "timed_out": step.get("timed_out"),
            }
            for step in steps
        ],
        "failures": failures,
    }


def generate() -> dict[str, Any]:
    with tempfile.TemporaryDirectory(prefix="claude-wrapper-isolated-") as temp_dir:
        temp_root = Path(temp_dir)
        home = temp_root / "home"
        stub_bin = temp_root / "bin"
        project = temp_root / "Workspace" / "fixture-project"
        setup_home(home, stub_bin)
        setup_project(project)

        results = [
            run_scenario(scenario, home=home, stub_bin=stub_bin, project=project)
            for scenario in SCENARIOS
        ]

    failed = sum(1 for result in results if result["status"] != "pass")
    return {
        "version": 1,
        "description": "Isolated execute validation for selected planned hook wrapper activation scenarios.",
        "generated_from": [
            "scripts/hook-wrapper-runner.py",
            "registry/hook-wrapper-plan.json",
            "registry/hook-wrapper-activation-gates.json",
        ],
        "runner": "scripts/hook-wrapper-runner.py",
        "scenario_count": len(results),
        "failed_scenario_count": failed,
        "status": "pass" if failed == 0 else "fail",
        "side_effect_boundary": {
            "home": "temporary",
            "cwd": "temporary git repository under temporary Workspace",
            "path": "stub say/osascript before system PATH",
            "llm": "temporary HOME stub llm-call.sh; ollama_available returns false",
        },
        "scenarios": results,
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
