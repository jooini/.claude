#!/usr/bin/env python3
"""
시간차 증언대 — 작업 시작 시 과거의 같은 문제가 어떻게 오판됐는지 소환.

자료원:
1. ~/.claude/projects/-*/*.jsonl 세션 로그 (claude-mem이 아닌 raw jsonl)
2. ~/Workspace/weaversbrain/weaversbrain/**/*.md 옵시디언 (결정/회의/분석)
3. git log (현재 프로젝트 cwd 기준, revert 커밋만 추출)

핵심: "관련 문서"가 아닌 "과거의 나쁜 판단"만 추출.

사용:
  python3 past-failure-witness.py "현재 작업 한 줄 설명" [--project NAME] [--top N]
"""

import json
import re
import sys
import argparse
import subprocess
from pathlib import Path
from collections import defaultdict
from datetime import datetime, timezone

PROJECTS_DIR = Path.home() / ".claude/projects"
OBSIDIAN = Path.home() / "Workspace/weaversbrain/weaversbrain"
REVERT_RE = re.compile(r'^(?:revert|fix|hotfix|버그|장애|롤백)', re.IGNORECASE)

USER_CORRECTION_RE = re.compile(
    r"(아니|틀렸|잘못|그게 아니|다시 해|다시해|수정해|wrong|incorrect|nope)"
)


def extract_text(content):
    if isinstance(content, str):
        return content
    if isinstance(content, list):
        parts = []
        for item in content:
            if isinstance(item, dict):
                t = item.get("type")
                if t == "text":
                    parts.append(item.get("text", ""))
                elif t == "thinking":
                    parts.append(item.get("thinking", ""))
        return "\n".join(parts)
    return ""


def keyword_score(query_kws, target_text):
    if not target_text:
        return 0.0
    text_lower = target_text.lower()
    hits = sum(1 for kw in query_kws if kw and kw.lower() in text_lower)
    return hits / max(len(query_kws), 1)


def extract_keywords(query):
    words = re.findall(r"[가-힣A-Za-z0-9_-]{2,}", query)
    stop = {"the", "and", "for", "with", "this", "that", "을", "를", "이", "가", "에", "는", "은"}
    return [w for w in words if w.lower() not in stop][:8]


def find_session_failures(query_kws, project_filter=None, max_per_project=20):
    """과거 세션에서 사용자 정정 직전 답변 추출 + query 매칭."""
    findings = []

    if not PROJECTS_DIR.exists():
        return findings

    for proj_dir in PROJECTS_DIR.iterdir():
        if not proj_dir.is_dir():
            continue
        proj = proj_dir.name.replace("-Users-leonard-Workspace-", "").replace("-Users-leonard-", "")
        if project_filter and project_filter not in proj:
            continue

        jsonls = sorted(proj_dir.glob("*.jsonl"), key=lambda p: p.stat().st_mtime, reverse=True)[:max_per_project]
        for jp in jsonls:
            try:
                lines = jp.read_text(encoding="utf-8", errors="ignore").splitlines()
            except Exception:
                continue

            msgs = []
            for line in lines:
                line = line.strip()
                if not line:
                    continue
                try:
                    d = json.loads(line)
                except Exception:
                    continue
                t = d.get("type")
                if t not in ("user", "assistant"):
                    continue
                msg = d.get("message", {}) or {}
                msgs.append({
                    "role": msg.get("role") or t,
                    "text": extract_text(msg.get("content", "")),
                    "ts": d.get("timestamp") or "",
                })

            for i, m in enumerate(msgs):
                user_text = m["text"] or ""
                # skill invoke 결과/시스템 reminder/긴 붙여넣기는 정정 아님
                is_paste = bool(re.match(r"^(Base directory for this skill|<system-reminder|---\nname:)", user_text, re.MULTILINE)) or user_text.count("\n") > 10
                if m["role"] == "user" and not is_paste and USER_CORRECTION_RE.search(user_text):
                    prev = i - 1
                    while prev >= 0 and msgs[prev]["role"] != "assistant":
                        prev -= 1
                    if prev < 0:
                        continue
                    prev_text = msgs[prev]["text"] or ""
                    # 직전이 tool_use 메타면 제외
                    if re.match(r"^\s*\[tool_(use|result):", prev_text):
                        continue
                    combined = prev_text + " " + user_text
                    score = keyword_score(query_kws, combined)
                    if score > 0:
                        findings.append({
                            "source": "session",
                            "project": proj,
                            "ts": m["ts"][:16],
                            "score": score,
                            "assistant_excerpt": (prev_text[:300]).replace("\n", " "),
                            "user_correction": (user_text[:200]).replace("\n", " "),
                            "session_file": str(jp),
                        })
    return findings


def find_obsidian_evidence(query_kws, max_files=200):
    """옵시디언에서 결정/실패/롤백 관련 노트 검색."""
    findings = []
    if not OBSIDIAN.exists():
        return findings

    failure_signals = re.compile(
        r"(실패|롤백|revert|틀렸|잘못|버그|장애|deprecated|deprecat|incident|hotfix)",
        re.IGNORECASE,
    )

    md_files = []
    for sub in ["Projects", "Plans", "Learning", "Sessions"]:
        d = OBSIDIAN / sub
        if d.exists():
            md_files.extend(d.rglob("*.md"))
    md_files = sorted(md_files, key=lambda p: p.stat().st_mtime, reverse=True)[:max_files]

    for fp in md_files:
        try:
            text = fp.read_text(encoding="utf-8", errors="ignore")
        except Exception:
            continue
        if not failure_signals.search(text):
            continue
        score = keyword_score(query_kws, text)
        if score > 0.2:
            failure_lines = [l for l in text.splitlines() if failure_signals.search(l)][:3]
            findings.append({
                "source": "obsidian",
                "file": str(fp.relative_to(OBSIDIAN)),
                "score": score,
                "failure_lines": failure_lines,
                "ts": datetime.fromtimestamp(fp.stat().st_mtime).isoformat()[:16],
            })
    return findings


def find_git_reverts(query_kws, cwd):
    """현재 cwd의 git log에서 revert/fix 커밋 추출."""
    findings = []
    try:
        out = subprocess.run(
            ["git", "-C", cwd, "log", "--oneline", "--max-count=200"],
            capture_output=True, text=True, timeout=10
        )
        if out.returncode != 0:
            return findings
        for line in out.stdout.splitlines():
            parts = line.split(" ", 1)
            if len(parts) < 2:
                continue
            sha, subject = parts
            if not REVERT_RE.match(subject):
                continue
            score = keyword_score(query_kws, subject)
            if score > 0:
                findings.append({
                    "source": "git",
                    "sha": sha,
                    "subject": subject[:200],
                    "score": score,
                })
    except Exception:
        pass
    return findings


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("query", help="현재 작업 한 줄 설명")
    ap.add_argument("--project", help="프로젝트 필터 (부분 매칭)")
    ap.add_argument("--cwd", default=".", help="git log 대상 디렉토리")
    ap.add_argument("--top", type=int, default=8, help="상위 N개")
    ap.add_argument("--json", action="store_true", help="JSON 출력")
    args = ap.parse_args()

    query_kws = extract_keywords(args.query)
    if not query_kws:
        print("키워드 추출 실패", file=sys.stderr)
        sys.exit(1)

    print(f"[witness] 키워드: {query_kws}", file=sys.stderr)

    sess = find_session_failures(query_kws, project_filter=args.project)
    obs = find_obsidian_evidence(query_kws)
    git_findings = find_git_reverts(query_kws, args.cwd)

    sess.sort(key=lambda x: -x["score"])
    obs.sort(key=lambda x: -x["score"])
    git_findings.sort(key=lambda x: -x["score"])

    sess_top = sess[:args.top]
    obs_top = obs[:args.top]
    git_top = git_findings[:args.top]

    if args.json:
        print(json.dumps({
            "query": args.query,
            "keywords": query_kws,
            "sessions": sess_top,
            "obsidian": obs_top,
            "git_reverts": git_top,
        }, indent=2, ensure_ascii=False))
        return

    print()
    print(f"# 시간차 증언대 — 「{args.query}」")
    print()
    print(f"키워드: `{', '.join(query_kws)}`")
    print()

    if sess_top:
        print("## 과거 세션 — 사용자 정정 패턴")
        print()
        for s in sess_top:
            print(f"- **{s['ts']}** · `{s['project']}` (score {s['score']:.2f})")
            print(f"  - 답변: {s['assistant_excerpt']}")
            print(f"  - 정정: {s['user_correction']}")
            print()
    else:
        print("## 과거 세션\n\n(매칭 없음)\n")

    if obs_top:
        print("## 옵시디언 — 실패/롤백 기록")
        print()
        for o in obs_top:
            print(f"- **{o['ts']}** · `{o['file']}` (score {o['score']:.2f})")
            for fl in o["failure_lines"][:2]:
                print(f"  - {fl[:200]}")
            print()
    else:
        print("## 옵시디언\n\n(매칭 없음)\n")

    if git_top:
        print("## Git Revert/Fix 커밋")
        print()
        for g in git_top:
            print(f"- `{g['sha']}` — {g['subject']}")
        print()
    else:
        print("## Git\n\n(매칭 없음 또는 git 디렉토리 아님)\n")

    print("---")
    print(f"⚠️ 위 항목은 **관련 문서가 아니라 과거의 나쁜 판단**입니다. 현재 작업에서 같은 함정에 빠지지 않도록 점검하세요.")


if __name__ == "__main__":
    main()
