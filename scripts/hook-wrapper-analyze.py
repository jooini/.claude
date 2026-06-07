#!/usr/bin/env python3
"""Analyze ~/.claude/cache/hook-wrapper-runs.jsonl.

Successor to the legacy hook-timing.sh TSV analyzer.
Schema (per record): ts, mode, plan_id, event, matcher, payload_bytes, cwd,
exit_code, execution_contract, steps[{order, hook_id, command, timeout_seconds,
exit_code, timed_out, stdout_bytes, stderr_bytes, blocked}].

Usage:
  hook-wrapper-analyze.py                 # last 7 days summary
  hook-wrapper-analyze.py --days 14
  hook-wrapper-analyze.py --hook NAME     # filter by hook basename
  hook-wrapper-analyze.py --slow          # only slow/timed-out/blocked steps
  hook-wrapper-analyze.py --json          # machine output for dashboards
"""

from __future__ import annotations

import argparse
import json
import os
import re
import sys
from collections import defaultdict
from datetime import datetime, timedelta, timezone
from pathlib import Path

LOG_PATH = Path.home() / ".claude" / "cache" / "hook-wrapper-runs.jsonl"
HOOK_RE = re.compile(r"hooks/([a-z][a-z0-9_-]+)\.sh")
WRAPPER_RE = re.compile(r"hook-wrapper-runner\.py\s+([a-z0-9_-]+)")


def hook_name(command: str) -> str:
    m = HOOK_RE.search(command)
    if m:
        return m.group(1)
    m = WRAPPER_RE.search(command)
    if m:
        return f"wrapper:{m.group(1)}"
    return command.split()[-1].rsplit("/", 1)[-1]


def parse_ts(ts: str) -> datetime:
    return datetime.fromisoformat(ts.replace("Z", "+00:00"))


def load_records(days: int):
    if not LOG_PATH.exists():
        sys.stderr.write(f"missing: {LOG_PATH}\n")
        sys.exit(1)
    cutoff = datetime.now(timezone.utc) - timedelta(days=days)
    with LOG_PATH.open() as f:
        for line in f:
            try:
                rec = json.loads(line)
            except json.JSONDecodeError:
                continue
            try:
                if parse_ts(rec["ts"]) < cutoff:
                    continue
            except (KeyError, ValueError):
                continue
            yield rec


def aggregate(records, hook_filter: str | None):
    per_hook = defaultdict(
        lambda: {
            "fires": 0,
            "errors": 0,
            "timeouts": 0,
            "blocked": 0,
            "stdout_bytes": 0,
            "stderr_bytes": 0,
            "last_ts": "",
            "events": defaultdict(int),
        }
    )
    per_plan = defaultdict(lambda: {"fires": 0, "errors": 0, "blocked": 0})
    total = 0
    for rec in records:
        total += 1
        plan = rec.get("plan_id", "?")
        per_plan[plan]["fires"] += 1
        if rec.get("exit_code", 0) != 0:
            per_plan[plan]["errors"] += 1
        for step in rec.get("steps", []):
            name = hook_name(step.get("command", ""))
            if hook_filter and hook_filter not in name:
                continue
            row = per_hook[name]
            row["fires"] += 1
            if step.get("exit_code", 0) != 0:
                row["errors"] += 1
            if step.get("timed_out"):
                row["timeouts"] += 1
            if step.get("blocked"):
                row["blocked"] += 1
                per_plan[plan]["blocked"] += 1
            row["stdout_bytes"] += step.get("stdout_bytes", 0) or 0
            row["stderr_bytes"] += step.get("stderr_bytes", 0) or 0
            row["events"][rec.get("event", "?")] += 1
            if rec["ts"] > row["last_ts"]:
                row["last_ts"] = rec["ts"]
    return total, per_hook, per_plan


def fmt_bytes(n: int) -> str:
    for unit in ("B", "K", "M", "G"):
        if n < 1024:
            return f"{n:.0f}{unit}"
        n /= 1024
    return f"{n:.1f}T"


def report(args):
    records = list(load_records(args.days))
    if args.slow:
        slow_records = []
        for rec in records:
            interesting_steps = [
                s
                for s in rec.get("steps", [])
                if s.get("timed_out") or s.get("blocked") or s.get("exit_code", 0) != 0
            ]
            if interesting_steps:
                rec = dict(rec)
                rec["steps"] = interesting_steps
                slow_records.append(rec)
        records = slow_records

    total, per_hook, per_plan = aggregate(records, args.hook)

    if args.json:
        json.dump(
            {
                "window_days": args.days,
                "total_invocations": total,
                "hooks": {
                    k: {**v, "events": dict(v["events"])}
                    for k, v in per_hook.items()
                },
                "plans": dict(per_plan),
            },
            sys.stdout,
            ensure_ascii=False,
            indent=2,
            default=str,
        )
        sys.stdout.write("\n")
        return

    print(f"# hook-wrapper-analyze (window={args.days}d)")
    print(f"source: {LOG_PATH}")
    print(f"invocations: {total}")
    print()

    print("## hooks (top 40 by fires)")
    print(f"{'fires':>7} {'err':>5} {'tmo':>4} {'blk':>4} {'stderr':>8} {'last':<20} hook")
    sorted_hooks = sorted(per_hook.items(), key=lambda kv: kv[1]["fires"], reverse=True)
    for name, row in sorted_hooks[:40]:
        print(
            f"{row['fires']:>7} {row['errors']:>5} {row['timeouts']:>4} {row['blocked']:>4} "
            f"{fmt_bytes(row['stderr_bytes']):>8} {row['last_ts'][:19]:<20} {name}"
        )

    print()
    print("## composite plans (wrapper plan_id)")
    print(f"{'fires':>7} {'err':>5} {'blk':>4} plan_id")
    for plan, row in sorted(per_plan.items(), key=lambda kv: kv[1]["fires"], reverse=True):
        print(f"{row['fires']:>7} {row['errors']:>5} {row['blocked']:>4} {plan}")

    silent = [n for n, r in per_hook.items() if r["fires"] == 0]
    if silent:
        print()
        print(f"## never fired in window: {len(silent)}")
        for n in silent:
            print(f"  - {n}")


def main():
    p = argparse.ArgumentParser()
    p.add_argument("--days", type=int, default=7)
    p.add_argument("--hook", help="filter by hook name substring")
    p.add_argument("--slow", action="store_true", help="only timed-out/blocked/errored steps")
    p.add_argument("--json", action="store_true")
    report(p.parse_args())


if __name__ == "__main__":
    main()
