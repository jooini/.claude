#!/usr/bin/env python3
"""backlog.md v1 → v2 마이그레이션.

사용:
    python3 backlog-migrate.py --dry-run          # 프로젝트별 변환 미리보기
    python3 backlog-migrate.py                    # 실제 변환 (백업 .bak 자동 생성)
    python3 backlog-migrate.py identity-hub       # 단일 프로젝트만
"""
from __future__ import annotations

import argparse
import shutil
import sys
from datetime import date
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent))
from backlog_lib import (  # type: ignore
    PROJECT_PREFIX,
    PROJECT_NAMES,
    Task,
    WORKSPACE,
    iter_project_backlogs,
    read_backlog,
    render_v2,
)


def assign_ids(tasks: list[Task], prefix: str, start: int = 1) -> None:
    n = start
    for t in tasks:
        if not t.id:
            t.id = f"{prefix}-{n:02d}"
            n += 1


def migrate_project(project: str, prefix: str, dry_run: bool) -> tuple[str, int]:
    path = WORKSPACE / project / "docs" / "backlog.md"
    if not path.exists():
        return "no-file", 0

    tasks, schema = read_backlog(path)
    if schema == "v2":
        return "already-v2", len(tasks)

    today = date.today().isoformat()
    for t in tasks:
        if not t.added:
            t.added = today
    assign_ids(tasks, prefix)

    rendered = render_v2(tasks, project)
    if dry_run:
        print(f"\n===== [DRY-RUN] {project} ({len(tasks)}건) =====")
        print(rendered[:800] + ("\n..." if len(rendered) > 800 else ""))
        return "dry-run", len(tasks)

    backup = path.with_suffix(".md.v1.bak")
    shutil.copy2(path, backup)
    path.write_text(rendered, encoding="utf-8")
    return "migrated", len(tasks)


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("project", nargs="?", help="단일 프로젝트만 (생략 시 전체)")
    ap.add_argument("--dry-run", action="store_true", help="변경 없이 미리보기")
    args = ap.parse_args()

    targets = [args.project] if args.project else PROJECT_NAMES

    print(f"마이그레이션 {'(DRY-RUN)' if args.dry_run else ''}")
    summary = []
    for project in targets:
        prefix = PROJECT_PREFIX.get(project)
        if not prefix:
            print(f"  {project}: prefix 미정의 스킵")
            continue
        status, n = migrate_project(project, prefix, args.dry_run)
        summary.append((project, status, n))
        marker = {
            "migrated": "✅",
            "dry-run": "📋",
            "already-v2": "⏭️",
            "no-file": "⚠️",
        }.get(status, "?")
        print(f"  {marker} {project:35s} {status:12s} {n}건")

    migrated = sum(1 for _, s, _ in summary if s == "migrated")
    print(f"\n완료: {migrated}개 프로젝트 마이그레이션")
    if not args.dry_run and migrated:
        print("백업: 각 backlog.md.v1.bak 에 원본 저장됨")
    return 0


if __name__ == "__main__":
    sys.exit(main())
