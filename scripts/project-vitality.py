#!/usr/bin/env python3
"""
프로젝트 사망 감지기 — vitality score 기반 멀티 프로젝트 건강도 분석.

vitality score 신호:
- 최근 N일 커밋 수 (긍정)
- 최근 N일 acceptance criteria 완료 수 (긍정, backlog/active 디렉토리에서 추출)
- 같은 파일 반복 수정률 (부정 — 진전 없음)
- "정리/조사/리팩터" 커밋 비율 (부정 — 가짜 진전)
- 테스트 실패 고착 (부정)
- 백로그 증가 vs 완료율 (부정 시 사망 신호)

사용:
  python3 project-vitality.py [--days 14] [--all] [--project NAME]

출력: ~/.claude/cache/vitality-report.md
"""

import os
import re
import sys
import json
import argparse
import subprocess
from pathlib import Path
from datetime import datetime, timedelta, timezone
from collections import Counter, defaultdict

WORKSPACE = Path.home() / "Workspace"
OUT_MD = Path.home() / ".claude/cache/vitality-report.md"
OUT_JSON = Path.home() / ".claude/cache/vitality-report.json"

FAKE_PROGRESS_RE = re.compile(
    r"(정리|청소|cleanup|chore|refactor|리팩터|investigate|조사|format|lint)",
    re.IGNORECASE,
)
USER_VISIBLE_RE = re.compile(
    r"(feat|fix|add|implement|구현|기능|버그|hotfix|user|response|api|endpoint|"
    r"추가|수정|개선|적용|연동|반영|동작|지원|배포|복구|핫픽스|기획|디자인|"
    r"login|logout|signup|auth|payment|결제|로그인|로그아웃|회원|"
    r"BUG-|FEAT-|EPIC-|IH-|KC-|SSO-|FE-|BE-)",
    re.IGNORECASE,
)
INFRA_HINT_RE = re.compile(
    r"(terraform|terracore|infra-docker|aws-lambda|weaversbrain-(infra|terraform))",
    re.IGNORECASE,
)


def list_projects():
    if not WORKSPACE.exists():
        return []
    return sorted([
        p for p in WORKSPACE.iterdir()
        if p.is_dir() and (p / ".git").exists()
    ])


def git_log(repo, days, fmt="%H|%s|%aI"):
    since = (datetime.now(timezone.utc) - timedelta(days=days)).strftime("%Y-%m-%d")
    try:
        out = subprocess.run(
            ["git", "-C", str(repo), "log", f"--since={since}", f"--pretty={fmt}", "--no-merges"],
            capture_output=True, text=True, timeout=15,
        )
        if out.returncode != 0:
            return []
        lines = [l for l in out.stdout.splitlines() if l.strip()]
        return lines
    except Exception:
        return []


def files_changed_per_commit(repo, days):
    since = (datetime.now(timezone.utc) - timedelta(days=days)).strftime("%Y-%m-%d")
    try:
        out = subprocess.run(
            ["git", "-C", str(repo), "log", f"--since={since}", "--name-only", "--pretty=format:__COMMIT__"],
            capture_output=True, text=True, timeout=15,
        )
        if out.returncode != 0:
            return Counter()
        files = []
        for line in out.stdout.splitlines():
            line = line.strip()
            if not line or line == "__COMMIT__":
                continue
            files.append(line)
        return Counter(files)
    except Exception:
        return Counter()


def count_backlog_active(repo):
    backlog_dir = repo / "backlog"
    active_dir = repo / "active"
    backlog_files = []
    active_files = []
    if backlog_dir.exists():
        backlog_files = list(backlog_dir.glob("*.md"))
    if active_dir.exists():
        active_files = list(active_dir.glob("*.md"))

    completed_active = 0
    for af in active_files:
        try:
            text = af.read_text(encoding="utf-8", errors="ignore")
            if re.search(r"(status:\s*completed|^# DONE|✅\s*완료|done:\s*true)", text, re.IGNORECASE | re.MULTILINE):
                completed_active += 1
        except Exception:
            pass

    return {
        "backlog_count": len(backlog_files),
        "active_count": len(active_files),
        "completed_active": completed_active,
    }


def session_count_for(project_name, days):
    proj_dir = Path.home() / ".claude/projects" / f"-Users-leonard-Workspace-{project_name}"
    if not proj_dir.exists():
        return 0
    cutoff = datetime.now().timestamp() - days * 86400
    return sum(1 for p in proj_dir.glob("*.jsonl") if p.stat().st_mtime > cutoff)


def analyze_project(repo, days):
    name = repo.name
    log_lines = git_log(repo, days)
    commits = []
    for l in log_lines:
        parts = l.split("|", 2)
        if len(parts) >= 2:
            commits.append({"sha": parts[0], "subject": parts[1], "date": parts[2] if len(parts) > 2 else ""})

    fake_progress = sum(1 for c in commits if FAKE_PROGRESS_RE.search(c["subject"]))
    user_visible = sum(1 for c in commits if USER_VISIBLE_RE.search(c["subject"]))

    files = files_changed_per_commit(repo, days)
    repeated_files = sum(1 for cnt in files.values() if cnt >= 3)
    total_files_touched = len(files)

    bl = count_backlog_active(repo)
    sessions_recent = session_count_for(name, days)

    n_commits = len(commits)
    if n_commits == 0:
        vitality = 0
    else:
        v = 50
        v += min(n_commits, 30)
        v += user_visible * 3
        v -= fake_progress * 2
        v -= repeated_files * 4
        v += min(bl["completed_active"] * 5, 20)
        v -= max(0, bl["backlog_count"] - bl["completed_active"] * 2) * 0.5
        if user_visible == 0 and n_commits > 5:
            v -= 25
        vitality = max(0, min(100, int(v)))

    is_infra = bool(INFRA_HINT_RE.search(name))

    if is_infra and n_commits == 0:
        status = "🔵 인프라 (안정 휴면)"
    elif is_infra and vitality < 40:
        status = "🔵 인프라 (정상)"
        vitality = max(vitality, 50)  # 인프라는 vitality 보정
    elif vitality >= 70:
        status = "🟢 활기"
    elif vitality >= 40:
        status = "🟡 보통"
    elif vitality >= 20:
        status = "🟠 위태로움"
    elif n_commits == 0 and sessions_recent == 0:
        status = "⚫ 휴면 (활동 없음)"
    else:
        status = "🔴 가짜 진전 (사망 의심)"

    flags = []
    if user_visible == 0 and n_commits > 5:
        flags.append("사용자-visible 산출물 0건")
    if fake_progress > n_commits * 0.5:
        flags.append("정리/리팩터 커밋이 절반 이상")
    if repeated_files > 3:
        flags.append(f"같은 파일 반복 수정 {repeated_files}건")
    if bl["backlog_count"] > 10 and bl["completed_active"] == 0:
        flags.append(f"백로그 {bl['backlog_count']}건, 완료 0건")

    recommendation = ""
    if status.startswith("🔴"):
        recommendation = "다음 작업은 리팩터/정리 금지, 사용자-visible 결과 1개만 강제"
    elif status.startswith("⚫"):
        recommendation = "프로젝트 archive 또는 명시적 종료 결정 필요"
    elif status.startswith("🟠"):
        recommendation = "백로그 정리 + 가장 작은 사용자-visible 작업 1개 우선"

    return {
        "project": name,
        "vitality": vitality,
        "status": status,
        "days": days,
        "commits": n_commits,
        "user_visible_commits": user_visible,
        "fake_progress_commits": fake_progress,
        "files_touched": total_files_touched,
        "repeated_files": repeated_files,
        "sessions_recent": sessions_recent,
        "backlog_count": bl["backlog_count"],
        "active_count": bl["active_count"],
        "completed_active": bl["completed_active"],
        "flags": flags,
        "recommendation": recommendation,
    }


def write_report(rows, days):
    rows = sorted(rows, key=lambda x: (x["vitality"], -x["commits"]))

    OUT_MD.parent.mkdir(parents=True, exist_ok=True)

    lines = []
    lines.append(f"# Project Vitality Report ({days}일 윈도우)")
    lines.append("")
    lines.append(f"생성: {datetime.now().isoformat()[:16]}")
    lines.append(f"분석 프로젝트: {len(rows)}개")
    lines.append("")
    lines.append("## 한눈에 보기")
    lines.append("")
    lines.append("| 프로젝트 | 상태 | Vitality | 커밋 | 사용자-visible | 가짜진전 | 백로그/완료 | 세션 |")
    lines.append("|---|---|---|---|---|---|---|---|")
    for r in rows:
        lines.append(
            f"| {r['project']} | {r['status']} | {r['vitality']} "
            f"| {r['commits']} | {r['user_visible_commits']} "
            f"| {r['fake_progress_commits']} "
            f"| {r['backlog_count']}/{r['completed_active']} "
            f"| {r['sessions_recent']} |"
        )
    lines.append("")

    danger = [r for r in rows if r["status"].startswith(("🔴", "⚫"))]
    if danger:
        lines.append("## 위험 신호 상세")
        lines.append("")
        for r in danger:
            lines.append(f"### {r['project']} ({r['status']}, vitality {r['vitality']})")
            for f in r["flags"]:
                lines.append(f"- ⚠️ {f}")
            if r["recommendation"]:
                lines.append(f"- 💡 권고: **{r['recommendation']}**")
            lines.append("")

    OUT_MD.write_text("\n".join(lines), encoding="utf-8")
    OUT_JSON.write_text(json.dumps({"days": days, "rows": rows}, indent=2, ensure_ascii=False), encoding="utf-8")


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--days", type=int, default=14)
    ap.add_argument("--project", help="단일 프로젝트만")
    ap.add_argument("--show", action="store_true")
    args = ap.parse_args()

    projects = list_projects()
    if args.project:
        projects = [p for p in projects if args.project in p.name]

    if not projects:
        print("프로젝트 없음", file=sys.stderr)
        sys.exit(1)

    print(f"분석: {len(projects)}개 프로젝트, {args.days}일 윈도우", file=sys.stderr)

    rows = []
    for p in projects:
        r = analyze_project(p, args.days)
        rows.append(r)
        print(f"  {r['project']}: {r['status']} (vitality {r['vitality']}, commits {r['commits']})", file=sys.stderr)

    write_report(rows, args.days)
    print(f"\n리포트: {OUT_MD}", file=sys.stderr)

    if args.show:
        print(OUT_MD.read_text())


if __name__ == "__main__":
    main()
