#!/usr/bin/env python3
"""프로젝트 백로그 대시보드.

사용:
    python3 backlog-dashboard.py                  # 전체 요약
    python3 backlog-dashboard.py --detail         # 항목별 상세
    python3 backlog-dashboard.py --stale 30       # 30일+ active 없는 프로젝트
    python3 backlog-dashboard.py --project identity-hub
"""
from __future__ import annotations

import argparse
import sys
import time
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent))
from backlog_lib import (  # type: ignore
    PROJECTS,
    Task,
    count_active,
    iter_project_backlogs,
    latest_active_mtime,
    read_backlog,
)


def age_days(mtime: float | None) -> int | None:
    if mtime is None:
        return None
    return int((time.time() - mtime) / 86400)


def fmt_age(days: int | None) -> str:
    if days is None:
        return "없음"
    if days == 0:
        return "오늘"
    return f"{days}일 전"


def priority_counts(tasks: list[Task]) -> tuple[int, int, int]:
    h = sum(1 for t in tasks if t.priority == "H" and t.status != "done")
    m = sum(1 for t in tasks if t.priority == "M" and t.status != "done")
    l = sum(1 for t in tasks if t.priority == "L" and t.status != "done")
    return h, m, l


def print_summary(stale_days: int) -> None:
    print("📊 프로젝트 백로그 현황")
    print("=" * 88)
    header = f"{'프로젝트':35s} | High | Med | Low | Active | 마지막 active"
    print(header)
    print("-" * 88)

    total_h = total_m = total_l = total_active = 0
    stale_list: list[str] = []
    missing: list[str] = []

    for project, path in iter_project_backlogs():
        if not path.exists():
            missing.append(project)
            continue
        tasks, _schema = read_backlog(path)
        h, m, l = priority_counts(tasks)
        active = count_active(project)
        age = age_days(latest_active_mtime(project))

        total_h += h
        total_m += m
        total_l += l
        total_active += active

        warn = ""
        if age is None:
            warn = " ❌"
            stale_list.append(project)
        elif age >= stale_days:
            warn = " ⚠"
            stale_list.append(project)

        print(
            f"{project:35s} | {h:4d} | {m:3d} | {l:3d} | {active:6d} | "
            f"{fmt_age(age)}{warn}"
        )

    print("-" * 88)
    print(
        f"{'합계':35s} | {total_h:4d} | {total_m:3d} | {total_l:3d} | {total_active:6d} |"
    )
    print("=" * 88)

    if missing:
        print(f"\n⚠ backlog.md 없음: {', '.join(missing)}")

    if stale_list:
        print(f"\n🔥 방치된 프로젝트 (active {stale_days}일+): {', '.join(stale_list)}")

    # 다음 추천 태스크
    print("\n🎯 다음 추천 (우선순위 High, backlog 상태):")
    recos = 0
    for project, path in iter_project_backlogs():
        if not path.exists() or recos >= 5:
            continue
        tasks, _schema = read_backlog(path)
        for t in tasks:
            if t.priority == "H" and t.status == "backlog":
                tid = t.id if t.id else "-"
                print(f"  · [{project}] {tid}: {t.title[:70]}")
                recos += 1
                break
    if recos == 0:
        print("  (High 우선순위 backlog 항목 없음)")


def print_project(project: str) -> None:
    path = Path.home() / "Workspace" / project / "docs" / "backlog.md"
    if not path.exists():
        print(f"backlog.md 없음: {project}")
        return
    tasks, schema = read_backlog(path)
    print(f"📋 {project} (schema={schema}, {len(tasks)}건)")
    print("=" * 88)
    for t in tasks:
        if t.status == "done":
            continue
        tid = t.id or "-"
        print(f"  [{t.priority}] {tid:10s} {t.status:8s}  {t.title[:70]}")


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--project", help="단일 프로젝트 상세")
    ap.add_argument("--stale", type=int, default=14, help="방치 기준 일수 (기본 14)")
    args = ap.parse_args()

    if args.project:
        print_project(args.project)
    else:
        print_summary(args.stale)
    return 0


if __name__ == "__main__":
    sys.exit(main())
