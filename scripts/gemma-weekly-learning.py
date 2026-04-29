#!/usr/bin/env python3
"""
주간 학습 리포트 — 지난 7일 zsh_history + git log 분석 → Gemma가 학습 패턴 추출.

사용:
  ./gemma-weekly-learning.py               # 지난 7일
  ./gemma-weekly-learning.py --days 14     # 지난 14일
  ./gemma-weekly-learning.py --save        # Obsidian에 저장

출력:
  - 새로 배운 명령어 Top N
  - 자주 반복하는 실수 패턴
  - 이번 주 워크플로우 특징
  - 성장 포인트 제안
"""
import argparse
import json
import os
import re
import subprocess
import sys
import time
import urllib.request
from collections import Counter
from datetime import datetime, timedelta
from pathlib import Path

OLLAMA = os.environ.get("OLLAMA_HOST_LAN", "leonard.local:11434")
MODEL = os.environ.get("GEMMA_MODEL", "gemma4:e4b")
HIST_FILE = Path.home() / ".zsh_history"
OBSIDIAN_VAULT = Path.home() / "Workspace" / "weaversbrain" / "weaversbrain"


def parse_history(days: int):
    """zsh_history에서 최근 N일 명령어 파싱."""
    if not HIST_FILE.exists():
        return []

    cutoff = int(time.time()) - (days * 86400)
    pattern = re.compile(r"^: (\d+):\d+;(.+)$")
    commands = []

    # zsh_history는 latin-1로 저장됨 (특수문자 깨짐 방지)
    with HIST_FILE.open("r", encoding="latin-1", errors="ignore") as f:
        for line in f:
            m = pattern.match(line.strip())
            if not m:
                continue
            ts = int(m.group(1))
            if ts < cutoff:
                continue
            cmd = m.group(2).strip()
            if cmd and not cmd.startswith("#"):
                commands.append((ts, cmd))

    return commands


def get_history_all_time():
    """전체 zsh_history에서 명령어만 추출 (신규 명령 판정용)."""
    if not HIST_FILE.exists():
        return set()

    pattern = re.compile(r"^: (\d+):\d+;(.+)$")
    cmds = set()

    with HIST_FILE.open("r", encoding="latin-1", errors="ignore") as f:
        for line in f:
            m = pattern.match(line.strip())
            if not m:
                continue
            # 첫 토큰만 (명령어 이름)
            first = m.group(2).strip().split()
            if first:
                cmds.add((int(m.group(1)), first[0]))

    return cmds


def extract_first_tokens(commands):
    """명령어 첫 토큰 빈도."""
    first_tokens = []
    for ts, cmd in commands:
        parts = cmd.split()
        if parts:
            # sudo, env 접두사 제거
            tok = parts[0]
            if tok in ("sudo", "env") and len(parts) > 1:
                tok = parts[1]
            first_tokens.append(tok)
    return Counter(first_tokens)


def detect_new_commands(recent_cmds, days: int):
    """이번 주 처음 나온 명령어 감지."""
    cutoff = int(time.time()) - (days * 86400)
    all_cmds = get_history_all_time()

    # 이번 주 명령어
    recent_first = set()
    for ts, cmd in recent_cmds:
        parts = cmd.split()
        if parts:
            tok = parts[0]
            if tok in ("sudo", "env") and len(parts) > 1:
                tok = parts[1]
            recent_first.add(tok)

    # 과거(cutoff 이전) 명령어
    past_first = set()
    for ts, tok in all_cmds:
        if ts < cutoff:
            past_first.add(tok)

    new_cmds = recent_first - past_first
    return sorted(new_cmds)


def detect_patterns(commands):
    """반복 패턴/실수 감지."""
    patterns = {
        "git_push_fail": 0,       # git push 실패 후 재시도
        "cd_oscillation": 0,      # cd 왔다갔다
        "rm_rf": 0,               # rm -rf 사용
        "docker_restart": 0,      # docker restart 반복
        "typo_fix": 0,            # 방금 한 명령 바로 재실행 (오타)
    }

    prev = None
    prev_dir = None
    dirs_seen = []

    for ts, cmd in commands:
        # git push 후 곧바로 pull/rebase
        if cmd.startswith("git push") and prev and ("pull" in prev or "rebase" in prev):
            patterns["git_push_fail"] += 1

        if cmd.startswith("rm -rf") or cmd.startswith("rm -fr"):
            patterns["rm_rf"] += 1

        if "docker restart" in cmd or "docker-compose restart" in cmd:
            patterns["docker_restart"] += 1

        if cmd.startswith("cd "):
            target = cmd[3:].strip()
            dirs_seen.append(target)

        # 바로 직전 명령과 유사 (오타 수정 가능성)
        if prev and cmd != prev and len(cmd) > 3 and len(prev) > 3:
            # 편집 거리 간단 추정 (공통 prefix 길이)
            common = 0
            for a, b in zip(cmd, prev):
                if a == b:
                    common += 1
                else:
                    break
            if common > len(cmd) * 0.7 and common > len(prev) * 0.7:
                patterns["typo_fix"] += 1

        prev = cmd

    # cd 왔다갔다
    if dirs_seen:
        dir_counter = Counter(dirs_seen)
        oscillation = sum(c for c in dir_counter.values() if c >= 3)
        patterns["cd_oscillation"] = oscillation

    return patterns


def get_git_activity(days: int):
    """지난 N일 Git 활동 요약."""
    workspace = Path.home() / "Workspace"
    if not workspace.exists():
        return ""

    projects_active = []
    since = (datetime.now() - timedelta(days=days)).strftime("%Y-%m-%d")

    for d in workspace.iterdir():
        if not (d / ".git").exists():
            continue
        try:
            r = subprocess.run(
                ["git", "-C", str(d), "log", f"--since={since}", "--oneline"],
                capture_output=True, text=True, timeout=5
            )
            lines = [l for l in r.stdout.strip().split("\n") if l]
            if lines:
                projects_active.append(f"{d.name}: {len(lines)}커밋")
        except Exception:
            continue

    return "\n".join(projects_active[:20])


def call_gemma(prompt: str, num_predict: int = 2000):
    """Gemma 호출 (로거 경유)."""
    import subprocess
    logger = Path.home() / ".claude" / "scripts" / "gemma-logger.sh"
    try:
        r = subprocess.run(
            [str(logger), "weekly-learning", MODEL, prompt, str(num_predict), "0.4"],
            capture_output=True, text=True, timeout=120
        )
        return r.stdout.strip()
    except Exception as e:
        return f"[Gemma 호출 실패: {e}]"


def build_report_prompt(days, total_cmds, top_commands, new_cmds, patterns, git_activity):
    lines = [
        f"# 주간 개발 학습 리포트 생성 ({days}일)",
        "",
        f"총 명령어 실행: {total_cmds}회",
        "",
        "## 가장 많이 쓴 명령어 Top 15",
    ]
    for cmd, cnt in top_commands[:15]:
        lines.append(f"- {cmd}: {cnt}회")

    lines += [
        "",
        "## 이번 주 처음 쓴 명령어 (신규)",
    ]
    if new_cmds:
        for c in new_cmds[:20]:
            lines.append(f"- {c}")
    else:
        lines.append("- 없음")

    lines += [
        "",
        "## 감지된 패턴",
        f"- git push 후 pull/rebase 재시도: {patterns['git_push_fail']}회",
        f"- cd 왕복(같은 디렉토리 3회+): {patterns['cd_oscillation']}회",
        f"- rm -rf 사용: {patterns['rm_rf']}회",
        f"- docker restart 반복: {patterns['docker_restart']}회",
        f"- 오타 수정 추정: {patterns['typo_fix']}회",
        "",
        "## Git 활동 (프로젝트별 커밋)",
        git_activity or "데이터 없음",
        "",
        "---",
        "",
        "위 데이터를 분석해서 다음 항목으로 한글 리포트 작성해줘:",
        "",
        "1. **이번 주 새로 배운 것** — 신규 명령어 중 흥미로운 것 2~3개 뽑아서 뭐하는 도구인지 한 줄 설명",
        "2. **반복되는 패턴 진단** — 감지된 패턴 중 개선이 필요해 보이는 것 지적 (없으면 '특이사항 없음')",
        "3. **이번 주 주요 작업 테마** — Top 명령어와 Git 활동으로 추정. 어떤 유형 작업을 많이 했는지 2~3문장",
        "4. **다음 주 개선 제안** — 구체적이고 실행 가능한 1~2개",
        "",
        "톤: 간결, 실용적, 잔소리 금지. 데이터 없으면 억지로 쓰지 말 것.",
        "형식: 각 섹션 markdown heading (##)으로 구분.",
    ]
    return "\n".join(lines)


def main():
    parser = argparse.ArgumentParser(description="주간 학습 리포트")
    parser.add_argument("--days", type=int, default=7, help="분석 기간 (일)")
    parser.add_argument("--save", action="store_true", help="Obsidian에 저장")
    parser.add_argument("--raw", action="store_true", help="Gemma 호출 없이 데이터만")
    args = parser.parse_args()

    print(f"📊 지난 {args.days}일 터미널 히스토리 분석 중...", file=sys.stderr)

    commands = parse_history(args.days)
    if not commands:
        print("❌ 히스토리 비어있음")
        return

    first_counter = extract_first_tokens(commands)
    top_commands = first_counter.most_common(30)
    new_cmds = detect_new_commands(commands, args.days)
    patterns = detect_patterns(commands)
    git_activity = get_git_activity(args.days)

    print(f"  총 {len(commands)}개 명령 수집", file=sys.stderr)
    print(f"  신규 명령어 {len(new_cmds)}개", file=sys.stderr)

    prompt = build_report_prompt(
        args.days, len(commands), top_commands, new_cmds, patterns, git_activity
    )

    if args.raw:
        print(prompt)
        return

    print(f"🤖 Gemma 분석 중... ({MODEL})", file=sys.stderr)
    report = call_gemma(prompt, num_predict=2000)

    # 출력 헤더
    today = datetime.now().strftime("%Y-%m-%d")
    header = f"""# 주간 학습 리포트 — {today}

- 기간: 지난 {args.days}일
- 명령어 실행: {len(commands)}회
- 신규 명령어: {len(new_cmds)}개
- 활성 프로젝트: {len(git_activity.split(chr(10))) if git_activity else 0}개

---

"""
    full_report = header + report

    # 원본 데이터 섹션
    raw_section = f"""

---

## 부록: 원본 데이터

### Top 15 명령어
""" + "\n".join(f"- `{c}`: {n}회" for c, n in top_commands[:15]) + """

### 신규 명령어 (전체)
""" + "\n".join(f"- `{c}`" for c in new_cmds[:30]) + f"""

### 패턴 카운트
- git push 재시도: {patterns['git_push_fail']}
- cd 왕복: {patterns['cd_oscillation']}
- rm -rf: {patterns['rm_rf']}
- docker restart: {patterns['docker_restart']}
- 오타 수정 추정: {patterns['typo_fix']}
"""
    full_report += raw_section

    print(full_report)

    if args.save:
        ts = datetime.now().strftime("%Y-%m-%d-%H%M")
        fname = f"{ts}-weekly-learning.md"
        save_path = OBSIDIAN_VAULT / "00-inbox" / fname

        frontmatter = f"""---
title: 주간 학습 리포트 {today}
date: {today}
type: weekly-learning
tags: [learning, terminal, gemma]
---

"""
        save_path.parent.mkdir(parents=True, exist_ok=True)
        save_path.write_text(frontmatter + full_report, encoding="utf-8")
        print(f"\n💾 저장됨: {save_path}", file=sys.stderr)


if __name__ == "__main__":
    main()
