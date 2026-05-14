#!/usr/bin/env python3
"""
인터럽트 큐레이터 (MVP).

백그라운드/주기적으로 호출되어 "지금 끼어들 가치"를 점수화한 발견을 보고.

발견 카테고리:
1. 동일 파일/심볼이 다른 active 작업과 겹침
2. 최근 24h 내 사용자가 손댄 파일 중 테스트 미실행 파일
3. backlog의 보안/HIGH 우선순위 미처리
4. 멀티 프로젝트 cross-check 위험 (SSO 변경 시)

interrupt score = 가치 / (현재 작업과의 거리 + 1) × 집중시간 보정

이 MVP는 1회성 분석. launchd/cron 통합은 별도.
"""

import os
import re
import sys
import json
import argparse
import subprocess
from pathlib import Path
from datetime import datetime, timedelta, timezone
from collections import defaultdict


def get_recent_edits(cwd, hours=24):
    try:
        since = (datetime.now(timezone.utc) - timedelta(hours=hours)).strftime("%Y-%m-%dT%H:%M:%S")
        out = subprocess.run(
            ["git", "-C", cwd, "log", f"--since={since}", "--name-only", "--pretty=format:__SHA__%H"],
            capture_output=True, text=True, timeout=10,
        )
        files = set()
        for line in out.stdout.splitlines():
            if line.startswith("__SHA__") or not line.strip():
                continue
            files.add(line.strip())
        return files
    except Exception:
        return set()


def find_active_tasks(workspace=Path.home() / "Workspace"):
    findings = []
    for proj in workspace.iterdir():
        if not proj.is_dir():
            continue
        active_dir = proj / "active"
        if not active_dir.exists():
            continue
        for af in active_dir.glob("*.md"):
            try:
                text = af.read_text(encoding="utf-8", errors="ignore")
                if re.search(r"(status:\s*completed|✅\s*완료|done:\s*true)", text, re.IGNORECASE):
                    continue
                findings.append({
                    "project": proj.name,
                    "task_file": str(af),
                    "title": af.stem,
                    "summary": text[:300],
                })
            except Exception:
                pass
    return findings


def find_security_backlog(workspace=Path.home() / "Workspace"):
    findings = []
    sec_re = re.compile(r"(보안|security|🔒|HIGH|CRITICAL|RCE|XSS|SQL injection|secret leak)", re.IGNORECASE)
    for proj in workspace.iterdir():
        if not proj.is_dir():
            continue
        bl = proj / "backlog"
        if not bl.exists():
            continue
        for bf in bl.glob("*.md"):
            try:
                text = bf.read_text(encoding="utf-8", errors="ignore")
                if sec_re.search(text):
                    findings.append({
                        "project": proj.name,
                        "file": str(bf),
                        "title": bf.stem,
                    })
            except Exception:
                pass
    return findings


def find_cross_project_overlap(current_files, workspace=Path.home() / "Workspace"):
    """현재 변경된 파일과 다른 프로젝트의 active 작업이 같은 모듈을 다루는지."""
    if not current_files:
        return []
    keywords = set()
    for f in current_files:
        parts = re.findall(r"[A-Z][a-zA-Z]+|[a-z]{4,}", os.path.basename(f))
        keywords.update(parts)
    if not keywords:
        return []

    findings = []
    for proj in workspace.iterdir():
        if not proj.is_dir():
            continue
        active = proj / "active"
        if not active.exists():
            continue
        for af in active.glob("*.md"):
            try:
                text = af.read_text(encoding="utf-8", errors="ignore")
                hits = sum(1 for kw in keywords if kw in text)
                if hits >= 2:
                    findings.append({
                        "project": proj.name,
                        "task": af.stem,
                        "shared_keywords": [kw for kw in keywords if kw in text][:5],
                        "score": hits,
                    })
            except Exception:
                pass
    return findings


def score_interrupts(items, current_focus=""):
    """interrupt score 계산. 0-100."""
    scored = []
    for it in items:
        base_value = it.get("base_value", 30)
        category = it.get("category", "info")
        urgency_boost = {
            "security": 50,
            "active_overlap": 30,
            "cross_project": 25,
            "test_missing": 15,
            "info": 0,
        }.get(category, 0)
        distance_penalty = 0
        if current_focus and current_focus.lower() in (it.get("text") or "").lower():
            distance_penalty -= 15
        score = min(100, max(0, base_value + urgency_boost + distance_penalty))
        it2 = {**it, "interrupt_score": score}
        scored.append(it2)
    scored.sort(key=lambda x: -x["interrupt_score"])
    return scored


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--cwd", default=".")
    ap.add_argument("--focus", default="", help="현재 작업 한 줄 (점수 보정)")
    ap.add_argument("--threshold", type=int, default=40, help="이 점수 이상만 보고")
    ap.add_argument("--json", action="store_true")
    args = ap.parse_args()

    cwd = os.path.abspath(args.cwd)
    recent = get_recent_edits(cwd)

    interrupts = []

    sec = find_security_backlog()
    for s in sec:
        interrupts.append({
            "category": "security",
            "title": f"보안 백로그 미처리: {s['project']} / {s['title']}",
            "text": s["title"],
            "file": s["file"],
            "base_value": 50,
        })

    if recent:
        cross = find_cross_project_overlap(recent)
        for c in cross:
            interrupts.append({
                "category": "cross_project",
                "title": f"크로스 프로젝트 영향 가능: {c['project']} / {c['task']}",
                "text": " ".join(c["shared_keywords"]),
                "shared_keywords": c["shared_keywords"],
                "base_value": 40,
            })

    actives = find_active_tasks()
    if len(actives) > 5:
        interrupts.append({
            "category": "info",
            "title": f"active/ 작업 누적: {len(actives)}건 — 핸드오프 또는 종료 검토",
            "text": f"{len(actives)} active tasks",
            "base_value": 20,
        })

    scored = score_interrupts(interrupts, args.focus)
    visible = [s for s in scored if s["interrupt_score"] >= args.threshold]

    if args.json:
        print(json.dumps({
            "cwd": cwd,
            "focus": args.focus,
            "threshold": args.threshold,
            "all": scored,
            "visible": visible,
        }, indent=2, ensure_ascii=False))
        return

    print()
    print(f"# 인터럽트 큐레이터 (cwd: `{Path(cwd).name}`)")
    print()
    print(f"분석 결과: {len(scored)}건 발견, 임계값({args.threshold}) 이상 {len(visible)}건")
    print()

    if not visible:
        print("(끼어들 가치가 큰 발견 없음 — 집중 유지 권장)")
        return

    for v in visible:
        cat_icon = {
            "security": "🔒",
            "active_overlap": "🔁",
            "cross_project": "🌐",
            "test_missing": "🧪",
            "info": "📌",
        }.get(v["category"], "•")
        print(f"## {cat_icon} {v['title']} (score {v['interrupt_score']})")
        if v.get("file"):
            print(f"- 위치: `{v['file']}`")
        if v.get("shared_keywords"):
            print(f"- 공유 키워드: `{', '.join(v['shared_keywords'])}`")
        print()


if __name__ == "__main__":
    main()
