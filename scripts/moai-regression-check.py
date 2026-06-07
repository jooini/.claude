#!/usr/bin/env python3
"""Rate-limited MoAI regression check for sync hooks and session warnings."""

from __future__ import annotations

import argparse
import json
import subprocess
import time
from pathlib import Path
from typing import Any


HOME = Path.home()
ROOT = HOME / ".claude"
CACHE = ROOT / "cache"
STATE_PATH = CACHE / "moai-regression-check.json"
LOG_PATH = CACHE / "moai-regression-check.log"
E2E_CHECK = HOME / "bin" / "moai-e2e-check"


def utc_now() -> str:
    return time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime())


def read_state() -> dict[str, Any]:
    try:
        value = json.loads(STATE_PATH.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError):
        return {}
    return value if isinstance(value, dict) else {}


def write_state(record: dict[str, Any]) -> None:
    CACHE.mkdir(parents=True, exist_ok=True)
    STATE_PATH.write_text(json.dumps(record, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    with LOG_PATH.open("a", encoding="utf-8") as handle:
        handle.write(json.dumps(record, ensure_ascii=False) + "\n")


def output_tail(stdout: str, stderr: str) -> str:
    lines = (stdout + "\n" + stderr).strip().splitlines()
    return "\n".join(lines[-30:])


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description="Run rate-limited MoAI regression checks.")
    parser.add_argument("--force", action="store_true", help="ignore min interval")
    parser.add_argument("--live", action="store_true", help="include live provider checks")
    parser.add_argument("--quiet", action="store_true", help="suppress stdout on success")
    parser.add_argument("--min-interval", type=int, default=900, help="minimum seconds between automatic runs")
    return parser


def main() -> int:
    args = build_parser().parse_args()
    previous = read_state()
    now_epoch = int(time.time())
    previous_epoch = int(previous.get("epoch") or 0)
    if not args.force and previous_epoch and now_epoch - previous_epoch < max(0, args.min_interval):
        if not args.quiet:
            print(f"MoAI regression check: SKIP recent={now_epoch - previous_epoch}s")
        return 0

    command = [str(E2E_CHECK)]
    if not args.live:
        command.extend(["--skip-live", "--skip-project-live"])

    started = time.time()
    process = subprocess.run(
        command,
        cwd=str(HOME),
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=300,
        check=False,
    )
    status = "pass" if process.returncode == 0 else "fail"
    record = {
        "schema_version": 1,
        "timestamp": utc_now(),
        "epoch": now_epoch,
        "status": status,
        "exit_code": process.returncode,
        "duration_ms": int((time.time() - started) * 1000),
        "live": bool(args.live),
        "command": command,
        "output_tail": output_tail(process.stdout, process.stderr),
    }
    write_state(record)

    if not args.quiet or status != "pass":
        print(f"MoAI regression check: {status.upper()}")
        if record["output_tail"]:
            print(record["output_tail"])
    return process.returncode


if __name__ == "__main__":
    raise SystemExit(main())
