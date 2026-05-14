#!/usr/bin/env python3
"""
Weekly Retrospective Generator

2026-04-28 옵시디언 진단의 Codex 처방. 매주 자동으로 push되는 1페이지 회고.

입력:
- 최근 7일 git commit (Workspace 전체 레포)
- Vault 7일 내 작성/수정된 .md 파일
- type: decision frontmatter 가진 문서
- Daily 노트 미완료 체크박스

출력:
- ~/Workspace/weaversbrain/weaversbrain/Reports/weekly/YYYY/YYYY-WNN-retro.md

사용:
    python3 weekly-retro.py                # 이번 주
    python3 weekly-retro.py --week 18      # 18주차
    python3 weekly-retro.py --dry-run      # 출력만 (저장 안 함)
"""
from __future__ import annotations

import argparse
import json
import re
import subprocess
import sys
from collections import defaultdict
from datetime import datetime, timedelta
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent))
try:
    from _lib_ini_call import call_ollama, is_ollama_reachable
    _LLM_AVAILABLE = True
except ImportError:
    _LLM_AVAILABLE = False

VAULT = Path.home() / "Workspace" / "weaversbrain" / "weaversbrain"
WORKSPACE = Path.home() / "Workspace"
REPORTS_WEEKLY = VAULT / "Reports" / "weekly"

DECISION_TYPES = {"decision", "meta-decision", "adr"}
LEDGER_PATH = Path.home() / ".claude" / "scripts" / ".weekly-retro-ledger.json"


def get_iso_week(dt: datetime) -> tuple[int, int]:
    """Return (iso_year, iso_week)."""
    iso = dt.isocalendar()
    return iso.year, iso.week


def week_range(year: int, week: int) -> tuple[datetime, datetime]:
    """Return (monday_00:00, sunday_23:59) for given ISO year/week."""
    first = datetime.fromisocalendar(year, week, 1)
    last = datetime.fromisocalendar(year, week, 7).replace(hour=23, minute=59, second=59)
    return first, last


def collect_git_commits(since: datetime, until: datetime) -> dict[str, list[dict]]:
    """Collect commits from all git repos under Workspace."""
    commits: dict[str, list[dict]] = defaultdict(list)
    for git_dir in WORKSPACE.glob("*/.git"):
        repo = git_dir.parent
        try:
            result = subprocess.run(
                [
                    "git",
                    "-C",
                    str(repo),
                    "log",
                    f"--since={since.isoformat()}",
                    f"--until={until.isoformat()}",
                    "--pretty=format:%h\t%ad\t%an\t%s",
                    "--date=iso",
                    "--all",
                ],
                capture_output=True,
                text=True,
                timeout=15,
            )
            if result.returncode != 0:
                continue
            for line in result.stdout.strip().split("\n"):
                if not line:
                    continue
                parts = line.split("\t", 3)
                if len(parts) < 4:
                    continue
                sha, date, author, msg = parts
                commits[repo.name].append(
                    {"sha": sha, "date": date, "author": author, "msg": msg}
                )
        except (subprocess.TimeoutExpired, OSError):
            continue
    return commits


def collect_vault_documents(since: datetime, until: datetime) -> list[dict]:
    """Collect .md files modified within range, excluding system folders."""
    excluded = {".venv", ".obsidian", "Archive", "00-inbox", ".git"}
    docs = []
    for md in VAULT.rglob("*.md"):
        if any(part in excluded for part in md.parts):
            continue
        try:
            mtime = datetime.fromtimestamp(md.stat().st_mtime)
            if not (since <= mtime <= until):
                continue
            rel = md.relative_to(VAULT)
            docs.append(
                {
                    "path": str(rel),
                    "name": md.name,
                    "mtime": mtime.isoformat(),
                    "size": md.stat().st_size,
                }
            )
        except OSError:
            continue
    docs.sort(key=lambda d: d["mtime"], reverse=True)
    return docs


FRONTMATTER_RE = re.compile(r"^---\s*\n(.*?)\n---\s*\n", re.DOTALL)


def parse_frontmatter(path: Path) -> dict:
    """Light YAML frontmatter parser (no external deps). Returns flat dict."""
    try:
        text = path.read_text(encoding="utf-8", errors="replace")[:3000]
    except OSError:
        return {}
    m = FRONTMATTER_RE.match(text)
    if not m:
        return {}
    fm = {}
    for line in m.group(1).split("\n"):
        line = line.strip()
        if not line or ":" not in line:
            continue
        if line.startswith("- "):
            continue
        key, _, val = line.partition(":")
        fm[key.strip()] = val.strip().strip('"').strip("'")
    return fm


def collect_decisions(docs: list[dict]) -> list[dict]:
    """Filter docs whose frontmatter type is decision-like."""
    decisions = []
    for d in docs:
        fm = parse_frontmatter(VAULT / d["path"])
        doc_type = fm.get("type", "").lower()
        if doc_type in DECISION_TYPES:
            decisions.append(
                {
                    "path": d["path"],
                    "title": fm.get("title", d["name"].replace(".md", "")),
                    "date": fm.get("date", d["mtime"][:10]),
                    "type": doc_type,
                    "status": fm.get("status", ""),
                }
            )
    return decisions


CHECKBOX_RE = re.compile(r"^[\s>]*-\s*\[\s\]\s+(.+?)$", re.MULTILINE)


def collect_open_todos(since: datetime) -> list[dict]:
    """Open checkboxes from Daily notes within range."""
    todos = []
    daily_dir = VAULT / "Daily"
    if not daily_dir.exists():
        return todos
    for md in daily_dir.rglob("*.md"):
        try:
            mtime = datetime.fromtimestamp(md.stat().st_mtime)
            if mtime < since:
                continue
            text = md.read_text(encoding="utf-8", errors="replace")
        except OSError:
            continue
        for match in CHECKBOX_RE.finditer(text):
            todos.append(
                {
                    "source": str(md.relative_to(VAULT)),
                    "task": match.group(1).strip(),
                }
            )
    return todos


def load_ledger() -> dict:
    if LEDGER_PATH.exists():
        try:
            return json.loads(LEDGER_PATH.read_text(encoding="utf-8"))
        except (json.JSONDecodeError, OSError):
            return {}
    return {}


def save_ledger(data: dict) -> None:
    LEDGER_PATH.parent.mkdir(parents=True, exist_ok=True)
    LEDGER_PATH.write_text(json.dumps(data, indent=2, ensure_ascii=False), encoding="utf-8")


def find_dead_docs(since: datetime) -> list[dict]:
    """Docs older than 90 days that haven't been opened in last 30 days.

    Uses ledger (manual access tracking) + mtime. atime intentionally avoided
    (macOS APFS doesn't reliably update atime).
    """
    threshold_old = since - timedelta(days=90)
    threshold_dead = since - timedelta(days=30)
    ledger = load_ledger()
    last_seen_map = ledger.get("last_seen", {})
    excluded = {".venv", ".obsidian", "Archive", "00-inbox", ".git", "Templates"}
    dead = []
    for md in VAULT.rglob("*.md"):
        if any(part in excluded for part in md.parts):
            continue
        try:
            mtime = datetime.fromtimestamp(md.stat().st_mtime)
        except OSError:
            continue
        if mtime > threshold_old:
            continue
        rel = str(md.relative_to(VAULT))
        last_seen_str = last_seen_map.get(rel)
        if last_seen_str:
            try:
                last_seen = datetime.fromisoformat(last_seen_str)
                if last_seen > threshold_dead:
                    continue
            except ValueError:
                pass
        dead.append(
            {
                "path": rel,
                "mtime": mtime.isoformat()[:10],
                "age_days": (since - mtime).days,
            }
        )
    dead.sort(key=lambda d: d["age_days"], reverse=True)
    return dead


def generate_llm_summary(year: int, week: int, commits: dict, docs: list,
                         decisions: list, todos: list, dead: list) -> str:
    """ini로 이번 주 핵심 패턴 + 다음 주 우선순위 1단락 요약 생성.

    ini/Ollama 미가용 시 빈 문자열 반환 (raw data만으로 보고서 완성).
    """
    if not _LLM_AVAILABLE or not is_ollama_reachable(timeout=2):
        return ""

    total_commits = sum(len(v) for v in commits.values())
    active_repos = sum(1 for v in commits.values() if v)

    # Top repos
    repo_lines = []
    for repo, cs in sorted(commits.items(), key=lambda kv: len(kv[1]), reverse=True)[:5]:
        if not cs:
            continue
        msgs = "; ".join(c["msg"][:60] for c in cs[:3])
        repo_lines.append(f"- {repo} ({len(cs)} commits): {msgs}")

    # Decisions
    dec_lines = [f"- {d['title']}" for d in decisions[:5]]

    # TODO 샘플
    todo_seen = set()
    todo_lines = []
    for t in todos:
        if t["task"] in todo_seen:
            continue
        todo_seen.add(t["task"])
        todo_lines.append(f"- {t['task'][:80]}")
        if len(todo_lines) >= 8:
            break

    prompt = f"""너는 leonard의 주간 회고를 분석하는 한국어 요약 도우미다.

데이터:
- 활동 레포 {active_repos}개, 총 커밋 {total_commits}개, Vault 신규 노트 {len(docs)}개, 결정 {len(decisions)}건, 미완료 TODO {len(todos)}건, 죽은 문서 {len(dead)}개

가장 바쁜 레포 Top 5:
{chr(10).join(repo_lines) if repo_lines else "(없음)"}

새 결정 문서:
{chr(10).join(dec_lines) if dec_lines else "(없음)"}

미완료 TODO 샘플:
{chr(10).join(todo_lines) if todo_lines else "(없음)"}

다음 형식으로 정확히 응답 (과장/이모지/장식 금지):

## 이번 주 핵심 패턴 (3줄 이내)
- (관찰 1: 가장 큰 활동 영역과 의미)
- (관찰 2: 결정/방향 전환)
- (관찰 3: 위험 신호 또는 누락)

## 다음 주 우선순위 (3개)
1. (구체적 행동 1)
2. (구체적 행동 2)
3. (구체적 행동 3)
"""

    try:
        response = call_ollama(
            prompt,
            model="qwen3.5:9b",
            num_predict=600,
            temperature=0.3,
            timeout=60,
            caller="weekly-retro",
        )
        return response.strip() if response else ""
    except Exception:
        return ""


def render_report(year: int, week: int, since: datetime, until: datetime,
                  commits: dict, docs: list, decisions: list,
                  todos: list, dead: list, llm_summary: str = "") -> str:
    total_commits = sum(len(v) for v in commits.values())
    active_repos = sum(1 for v in commits.values() if v)
    lines = []
    lines.append(f"---")
    lines.append(f"date: {since.date().isoformat()}")
    lines.append(f"week: {year}-W{week:02d}")
    lines.append(f"type: weekly-retro")
    lines.append(f"generated: {datetime.now().isoformat(timespec='seconds')}")
    lines.append(f"generator: weekly-retro.py")
    lines.append(f"---")
    lines.append("")
    lines.append(f"# 주간 회고 — {year}-W{week:02d} ({since.date()} ~ {until.date()})")
    lines.append("")
    lines.append("## 한눈에")
    lines.append(f"- 활동 레포: **{active_repos}** / 총 커밋: **{total_commits}**")
    lines.append(f"- Vault 신규/수정 노트: **{len(docs)}**")
    lines.append(f"- 새 결정 문서: **{len(decisions)}**")
    lines.append(f"- 미완료 TODO (Daily): **{len(todos)}**")
    lines.append(f"- 죽은 문서 (90일+ 미수정 + 30일+ 미열람): **{len(dead)}**")
    lines.append("")

    # LLM summary (ini/Ollama 가용 시)
    if llm_summary:
        lines.append("## AI 분석 (qwen3.5:9b via ini)")
        lines.append(llm_summary)
        lines.append("")

    # Top active repos
    lines.append("## 활동 Top — 이번 주 가장 바쁜 레포")
    repo_sorted = sorted(commits.items(), key=lambda kv: len(kv[1]), reverse=True)
    for repo, cs in repo_sorted[:10]:
        if not cs:
            continue
        lines.append(f"- **{repo}** ({len(cs)} commits)")
        for c in cs[:3]:
            short_msg = c["msg"][:80]
            lines.append(f"  - `{c['sha']}` {short_msg}")
    if len(repo_sorted) > 10 or sum(1 for _, cs in repo_sorted if cs) > 10:
        lines.append(f"- _... and {max(0, active_repos - 10)} more repos_")
    lines.append("")

    # New decisions
    if decisions:
        lines.append("## 새 결정 문서 — 다시 봐야 할 것")
        for d in decisions[:15]:
            uri = f"obsidian://open?vault=weaversbrain&file={d['path'].replace('.md', '').replace(' ', '%20')}"
            lines.append(f"- [{d['title']}]({uri}) ({d['type']}, {d['date']})")
        lines.append("")
    else:
        lines.append("## 새 결정 문서 — 없음")
        lines.append("")

    # Open TODOs sample
    if todos:
        lines.append(f"## 미완료 TODO (이번 주 Daily) — 샘플")
        # Dedupe by task text
        seen = set()
        unique_todos = []
        for t in todos:
            if t["task"] in seen:
                continue
            seen.add(t["task"])
            unique_todos.append(t)
        for t in unique_todos[:20]:
            lines.append(f"- [ ] {t['task']}  _<sub>({t['source']})</sub>_")
        if len(unique_todos) > 20:
            lines.append(f"- _... and {len(unique_todos) - 20} more_")
        lines.append("")

    # Notes worth re-reading (top 10 by recency, in Plans/Reports/Projects)
    important_paths = [d for d in docs if d["path"].startswith(("Plans/", "Reports/", "Projects/"))]
    if important_paths:
        lines.append("## 다시 읽어볼 노트 — Plans/Reports/Projects 신규")
        for d in important_paths[:10]:
            uri = f"obsidian://open?vault=weaversbrain&file={d['path'].replace('.md', '').replace(' ', '%20')}"
            lines.append(f"- [{d['name'].replace('.md', '')}]({uri})")
        if len(important_paths) > 10:
            lines.append(f"- _... and {len(important_paths) - 10} more_")
        lines.append("")

    # Dead docs
    if dead:
        lines.append(f"## 죽은 문서 후보 (90일+ 미수정) — 정리 검토")
        for d in dead[:20]:
            lines.append(f"- {d['path']} _<sub>(age: {d['age_days']}d, mtime: {d['mtime']})</sub>_")
        if len(dead) > 20:
            lines.append(f"- _... and {len(dead) - 20} more_")
        lines.append("")
        lines.append("> 이 중 1개라도 archive 또는 삭제하면 \"지우는 근육\" 훈련 (2026-04-28 진단 Gemma 처방)")
        lines.append("")

    lines.append("---")
    lines.append("")
    lines.append("> 본 보고서는 `~/.claude/scripts/weekly-retro.py`로 자동 생성. ledger: `~/.claude/scripts/.weekly-retro-ledger.json`")
    lines.append("> 다음 액션: 위 결정/노트 중 1개를 다시 열고 5분 읽기. 죽은 문서 1개 archive.")
    lines.append("")
    return "\n".join(lines)


def main() -> int:
    parser = argparse.ArgumentParser(description="Weekly retrospective generator")
    parser.add_argument("--week", type=int, help="ISO week number (default: current)")
    parser.add_argument("--year", type=int, help="ISO year (default: current)")
    parser.add_argument("--dry-run", action="store_true", help="Print without saving")
    parser.add_argument("--no-llm", action="store_true", help="Skip ini/Ollama LLM summary section")
    args = parser.parse_args()

    now = datetime.now()
    iso_year, iso_week = get_iso_week(now)
    year = args.year or iso_year
    week = args.week or iso_week

    since, until = week_range(year, week)
    print(f"[weekly-retro] generating: {year}-W{week:02d} ({since.date()} ~ {until.date()})", file=sys.stderr)

    print(f"[weekly-retro] collecting git commits...", file=sys.stderr)
    commits = collect_git_commits(since, until)

    print(f"[weekly-retro] collecting vault docs...", file=sys.stderr)
    docs = collect_vault_documents(since, until)

    print(f"[weekly-retro] parsing decisions...", file=sys.stderr)
    decisions = collect_decisions(docs)

    print(f"[weekly-retro] scanning daily TODOs...", file=sys.stderr)
    todos = collect_open_todos(since)

    print(f"[weekly-retro] finding dead docs...", file=sys.stderr)
    dead = find_dead_docs(now)

    llm_summary = ""
    if not args.no_llm:
        print(f"[weekly-retro] requesting LLM summary (ini)...", file=sys.stderr)
        llm_summary = generate_llm_summary(year, week, commits, docs, decisions, todos, dead)
        if llm_summary:
            print(f"[weekly-retro] LLM summary: {len(llm_summary)} chars", file=sys.stderr)
        else:
            print(f"[weekly-retro] LLM summary unavailable (Ollama unreachable or error)", file=sys.stderr)

    report = render_report(year, week, since, until, commits, docs, decisions, todos, dead, llm_summary)

    if args.dry_run:
        print(report)
        return 0

    out_dir = REPORTS_WEEKLY / str(year)
    out_dir.mkdir(parents=True, exist_ok=True)
    out_file = out_dir / f"{year}-W{week:02d}-retro.md"
    out_file.write_text(report, encoding="utf-8")
    print(f"[weekly-retro] DONE: {out_file}", file=sys.stderr)
    print(f"obsidian://open?vault=weaversbrain&file=Reports%2Fweekly%2F{year}%2F{year}-W{week:02d}-retro", file=sys.stderr)
    return 0


if __name__ == "__main__":
    sys.exit(main())
