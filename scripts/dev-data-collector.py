#!/usr/bin/env python3
"""dev-data-collector — 주관 0, 재현 가능한 기간별 개발 활동 스냅샷 생성기.

사용법:
    python3 dev-data-collector.py quarter            # 지난 분기
    python3 dev-data-collector.py year               # 지난 1년
    python3 dev-data-collector.py range 2026-04-01 2026-06-30
    python3 dev-data-collector.py custom --from 2026-01-01 --to 2026-03-31 --scope "sso-*,identity-hub*"

출력:
    ~/Workspace/weaversbrain/weaversbrain/Reports/snapshots/YYYY-QN-portrait.md (quarter)
    ~/Workspace/weaversbrain/weaversbrain/Reports/snapshots/YYYY-portrait.md (year)
    ~/Workspace/weaversbrain/weaversbrain/Reports/snapshots/YYYY-MM-DD_YYYY-MM-DD-portrait.md (range)

규칙:
    - 판단 문구 금지. 숫자와 표만.
    - 수집에 사용된 git 명령과 범위를 §10에 기록 (재현 가능성).
    - 저자 필터: git config user.email 기준.
"""

from __future__ import annotations

import argparse
import fnmatch
import json
import os
import re
import shutil
import subprocess
import sys
from collections import Counter, defaultdict
from dataclasses import dataclass, field
from datetime import date, datetime, timedelta
from pathlib import Path
from typing import Iterable

WORKSPACE = Path(os.path.expanduser("~/Workspace"))
VAULT = Path(os.path.expanduser("~/Workspace/weaversbrain/weaversbrain"))
SNAPSHOT_DIR = VAULT / "Reports" / "snapshots"
DAILY_DIR = VAULT / "Daily"

COMMIT_TYPE_PATTERN = re.compile(
    r"^(feat|fix|refactor|chore|docs|test|build|ci|perf|style|revert)(\(|:|!)",
    re.IGNORECASE,
)

TEST_FILE_PATTERNS = [
    "*test*.py",
    "*Test.kt",
    "*Tests.kt",
    "*.test.ts",
    "*.test.tsx",
    "*.test.js",
    "*.spec.ts",
    "*.spec.tsx",
    "*.spec.js",
    "*_test.go",
]

DOC_FILE_PATTERNS = ["*.md", "*.mdx", "*.rst", "*.adoc"]

DEPS_FILES = {
    "package.json",
    "package-lock.json",
    "pnpm-lock.yaml",
    "yarn.lock",
    "requirements.txt",
    "pyproject.toml",
    "Pipfile",
    "Pipfile.lock",
    "build.gradle",
    "build.gradle.kts",
    "pom.xml",
    "go.mod",
    "go.sum",
    "Cargo.toml",
    "Cargo.lock",
}

CI_PATH_PREFIXES = (
    ".github/workflows/",
    ".gitlab-ci.yml",
    ".circleci/",
    "Jenkinsfile",
    ".buildkite/",
)

PROJECT_GROUPS = [
    ("identity-hub", ["identity-hub*"]),
    ("identity-keycloak", ["identity-keycloak*", "keycloak-*", "apple-identity-provider-keycloak"]),
    ("maxai", ["maxai*"]),
    ("sso", ["sso-*", "sso_*"]),
    ("speakingmax", ["speakingmax*", "speech-*"]),
    ("weaversbrain-infra", ["weaversbrain*", "terracore-infra", "*-infra*", "*-docker"]),
    ("b2c", ["b2c-*", "*-b2c-*"]),
    ("tools-and-scripts", ["tools", "scripts", "*-sdk*", "sso-log-viewer", "sso-trace-visualizer", "sso-fallback-monitor"]),
]


@dataclass
class CommitStat:
    sha: str
    author_email: str
    ts: datetime
    subject: str
    insertions: int = 0
    deletions: int = 0
    files: list[str] = field(default_factory=list)


@dataclass
class RepoStats:
    repo: str
    path: Path
    commits: list[CommitStat] = field(default_factory=list)

    @property
    def total_commits(self) -> int:
        return len(self.commits)

    @property
    def total_insertions(self) -> int:
        return sum(c.insertions for c in self.commits)

    @property
    def total_deletions(self) -> int:
        return sum(c.deletions for c in self.commits)


def run(cmd: list[str], cwd: Path | None = None, check: bool = False) -> str:
    try:
        out = subprocess.check_output(
            cmd,
            cwd=str(cwd) if cwd else None,
            stderr=subprocess.DEVNULL,
            text=True,
        )
        return out
    except subprocess.CalledProcessError as exc:
        if check:
            raise
        return ""
    except FileNotFoundError:
        return ""


# leonard의 커밋 저자 이메일. 회사/계정 바뀌면 여기 수정 or `--email` 사용.
DEFAULT_LEONARD_EMAILS = [
    "is.joo@weaversbrain.com",
    "is.joo@speakingmaxapp.com",
    "joo.leonard@gmail.com",
]


def get_user_emails() -> list[str]:
    """사용자가 `--email` 으로 오버라이드하지 않았을 때 자동 탐지할 이메일 목록.

    우선순위:
    1. 환경 변수 `DEV_COLLECTOR_EMAILS` (콤마 구분)
    2. git config global user.email
    3. 환경 변수 GIT_AUTHOR_EMAIL
    4. 하드코딩 기본값 (`DEFAULT_LEONARD_EMAILS`)
    """
    env_list = os.environ.get("DEV_COLLECTOR_EMAILS", "")
    if env_list:
        return [e.strip() for e in env_list.split(",") if e.strip()]

    results: list[str] = []
    cfg = run(["git", "config", "--global", "user.email"]).strip()
    if cfg:
        results.append(cfg)
    env_single = os.environ.get("GIT_AUTHOR_EMAIL", "")
    if env_single and env_single not in results:
        results.append(env_single)

    # 기본값 추가 (기존 탐지값에 없는 것만)
    for e in DEFAULT_LEONARD_EMAILS:
        if e not in results:
            results.append(e)
    return results


def discover_repos(scope_patterns: list[str] | None) -> list[Path]:
    if not WORKSPACE.exists():
        return []
    results: list[Path] = []
    for entry in sorted(WORKSPACE.iterdir()):
        if not entry.is_dir():
            continue
        if not (entry / ".git").exists():
            continue
        name = entry.name
        if scope_patterns:
            if not any(fnmatch.fnmatch(name, p) for p in scope_patterns):
                continue
        results.append(entry)
    return results


def classify_group(repo_name: str) -> str:
    for group, patterns in PROJECT_GROUPS:
        if any(fnmatch.fnmatch(repo_name, p) for p in patterns):
            return group
    return "other"


def quarter_range(today: date) -> tuple[date, date, str]:
    """지난 분기 범위 반환."""
    current_q = (today.month - 1) // 3 + 1
    prev_q = current_q - 1
    year = today.year
    if prev_q == 0:
        prev_q = 4
        year -= 1
    start_month = (prev_q - 1) * 3 + 1
    start = date(year, start_month, 1)
    if prev_q == 4:
        end = date(year, 12, 31)
    else:
        end = date(year, start_month + 3, 1) - timedelta(days=1)
    return start, end, f"{year}-Q{prev_q}"


def year_range(today: date) -> tuple[date, date, str]:
    year = today.year - 1
    return date(year, 1, 1), date(year, 12, 31), f"{year}"


def parse_commits(repo: Path, since: date, until: date, author_emails: list[str]) -> list[CommitStat]:
    sep = "\x1f"  # unit separator
    record_sep = "\x1e"  # record separator
    fmt = sep.join(["%H", "%aI", "%ae", "%s"])
    log_args = [
        "git",
        "log",
        f"--since={since.isoformat()}",
        f"--until={(until + timedelta(days=1)).isoformat()}",
        "--no-merges",
        "--numstat",
        f"--pretty=format:{record_sep}{fmt}",
    ]
    # 여러 이메일 OR 필터: --author 여러 번 + --regexp-ignore-case 로 각각 붙일 수 없음.
    # 대신 정규식 OR로 전달 (git --author는 POSIX ERE).
    if author_emails:
        pattern = "|".join(re.escape(e) for e in author_emails)
        log_args.insert(2, f"--author={pattern}")
        log_args.insert(3, "--perl-regexp")
    out = run(log_args, cwd=repo)
    commits: list[CommitStat] = []
    if not out:
        return commits

    records = out.split(record_sep)
    for raw in records:
        raw = raw.strip("\n")
        if not raw:
            continue
        lines = raw.split("\n")
        head = lines[0]
        parts = head.split(sep)
        if len(parts) < 4:
            continue
        sha, ts_iso, email, subject = parts[0], parts[1], parts[2], parts[3]
        try:
            ts = datetime.fromisoformat(ts_iso)
        except ValueError:
            continue
        cs = CommitStat(sha=sha, author_email=email, ts=ts, subject=subject)
        for nline in lines[1:]:
            if not nline.strip():
                continue
            nparts = nline.split("\t")
            if len(nparts) != 3:
                continue
            ins, dele, path = nparts
            try:
                cs.insertions += int(ins) if ins != "-" else 0
                cs.deletions += int(dele) if dele != "-" else 0
            except ValueError:
                pass
            cs.files.append(path)
        commits.append(cs)
    return commits


def classify_commit_type(subject: str) -> str:
    m = COMMIT_TYPE_PATTERN.match(subject.strip())
    if m:
        return m.group(1).lower()
    return "other"


def detect_language(subject: str) -> str:
    has_hangul = bool(re.search(r"[\uac00-\ud7a3]", subject))
    has_latin = bool(re.search(r"[a-zA-Z]", subject))
    if has_hangul and has_latin:
        return "mixed"
    if has_hangul:
        return "ko"
    if has_latin:
        return "en"
    return "other"


def file_matches_any(path: str, patterns: list[str]) -> bool:
    base = os.path.basename(path)
    return any(fnmatch.fnmatch(base, p) for p in patterns)


def is_ci_file(path: str) -> bool:
    return any(path.startswith(prefix) for prefix in CI_PATH_PREFIXES)


def is_deps_file(path: str) -> bool:
    return os.path.basename(path) in DEPS_FILES


def count_obsidian_activity(since: date, until: date) -> dict[str, int]:
    result = {"daily_notes": 0, "total_words": 0, "reports_weekly": 0}
    if not DAILY_DIR.exists():
        return result
    # Daily/YYYY-MM/YYYY-MM-DD.md
    for month_dir in DAILY_DIR.iterdir():
        if not month_dir.is_dir():
            continue
        for md in month_dir.glob("*.md"):
            stem = md.stem
            try:
                note_date = datetime.strptime(stem[:10], "%Y-%m-%d").date()
            except ValueError:
                continue
            if since <= note_date <= until:
                result["daily_notes"] += 1
                try:
                    text = md.read_text(errors="ignore")
                    result["total_words"] += len(text.split())
                except OSError:
                    pass
            if "weekly" in stem:
                if since <= note_date <= until:
                    result["reports_weekly"] += 1
    return result


def collect_repo_stats(repo: Path, since: date, until: date, author_emails: list[str]) -> RepoStats:
    stats = RepoStats(repo=repo.name, path=repo)
    stats.commits = parse_commits(repo, since, until, author_emails)
    return stats


def aggregate(all_stats: list[RepoStats]) -> dict:
    by_group: dict[str, dict] = defaultdict(lambda: {"commits": 0, "ins": 0, "del": 0, "repos": []})
    total_commits = 0
    total_ins = 0
    total_del = 0
    type_counter: Counter = Counter()
    lang_counter: Counter = Counter()
    hour_counter: Counter = Counter()
    weekday_counter: Counter = Counter()
    month_counter: Counter = Counter()
    file_change_counter: Counter = Counter()
    test_file_changes = 0
    doc_file_changes = 0
    ci_file_changes = 0
    deps_file_changes = 0

    for rs in all_stats:
        group = classify_group(rs.repo)
        by_group[group]["commits"] += rs.total_commits
        by_group[group]["ins"] += rs.total_insertions
        by_group[group]["del"] += rs.total_deletions
        by_group[group]["repos"].append(rs.repo)
        total_commits += rs.total_commits
        total_ins += rs.total_insertions
        total_del += rs.total_deletions
        for c in rs.commits:
            type_counter[classify_commit_type(c.subject)] += 1
            lang_counter[detect_language(c.subject)] += 1
            hour_counter[c.ts.hour] += 1
            weekday_counter[c.ts.weekday()] += 1
            month_counter[c.ts.strftime("%Y-%m")] += 1
            for f in c.files:
                file_change_counter[f"{rs.repo}::{f}"] += 1
                if file_matches_any(f, TEST_FILE_PATTERNS):
                    test_file_changes += 1
                if file_matches_any(f, DOC_FILE_PATTERNS):
                    doc_file_changes += 1
                if is_ci_file(f):
                    ci_file_changes += 1
                if is_deps_file(f):
                    deps_file_changes += 1

    return {
        "total_commits": total_commits,
        "total_ins": total_ins,
        "total_del": total_del,
        "by_group": dict(by_group),
        "type_counter": type_counter,
        "lang_counter": lang_counter,
        "hour_counter": hour_counter,
        "weekday_counter": weekday_counter,
        "month_counter": month_counter,
        "file_change_counter": file_change_counter,
        "test_file_changes": test_file_changes,
        "doc_file_changes": doc_file_changes,
        "ci_file_changes": ci_file_changes,
        "deps_file_changes": deps_file_changes,
    }


def gh_activity(since: date, until: date, author_emails: list[str]) -> dict:
    """GitHub CLI 있으면 PR/리뷰 활동 집계. 없으면 빈 값."""
    if not shutil.which("gh"):
        return {"available": False}
    user_out = run(["gh", "api", "user", "-q", ".login"]).strip()
    if not user_out:
        return {"available": False}
    login = user_out
    since_q = since.isoformat()
    until_q = until.isoformat()

    def gh_search(query: str) -> int:
        out = run([
            "gh",
            "api",
            "-X",
            "GET",
            "search/issues",
            "-f",
            f"q={query}",
            "-q",
            ".total_count",
        ])
        try:
            return int(out.strip() or "0")
        except ValueError:
            return 0

    base = f"created:{since_q}..{until_q}"
    prs_opened = gh_search(f"author:{login} is:pr {base}")
    prs_merged = gh_search(f"author:{login} is:pr is:merged merged:{since_q}..{until_q}")
    prs_reviewed = gh_search(f"reviewed-by:{login} is:pr {base}")
    issues_opened = gh_search(f"author:{login} is:issue {base}")
    return {
        "available": True,
        "login": login,
        "prs_opened": prs_opened,
        "prs_merged": prs_merged,
        "prs_reviewed": prs_reviewed,
        "issues_opened": issues_opened,
    }


def render_table(headers: list[str], rows: list[list[str]]) -> str:
    lines = ["| " + " | ".join(headers) + " |"]
    lines.append("|" + "|".join(["---"] * len(headers)) + "|")
    for r in rows:
        lines.append("| " + " | ".join(r) + " |")
    return "\n".join(lines)


def render_markdown(
    label: str,
    since: date,
    until: date,
    author_emails: list[str],
    all_stats: list[RepoStats],
    agg: dict,
    gh: dict,
    obsidian: dict,
    scope_patterns: list[str] | None,
) -> str:
    author_email = ", ".join(author_emails) if author_emails else ""
    now = datetime.now().astimezone().isoformat()
    total_commits = agg["total_commits"]
    total_ins = agg["total_ins"]
    total_del = agg["total_del"]

    # 1. 레포별 커밋 볼륨
    repo_rows = []
    for rs in sorted(all_stats, key=lambda r: r.total_commits, reverse=True):
        if rs.total_commits == 0:
            continue
        ratio = (rs.total_commits / total_commits * 100) if total_commits else 0
        repo_rows.append(
            [
                rs.repo,
                classify_group(rs.repo),
                str(rs.total_commits),
                str(rs.total_insertions),
                str(rs.total_deletions),
                f"{ratio:.1f}%",
            ]
        )
    repo_table = render_table(
        ["repo", "group", "commits", "insertions", "deletions", "share"],
        repo_rows or [["(none)", "-", "0", "0", "0", "0%"]],
    )

    # 2. 작업 유형 분포
    type_rows = []
    for t, c in sorted(agg["type_counter"].items(), key=lambda kv: kv[1], reverse=True):
        ratio = (c / total_commits * 100) if total_commits else 0
        type_rows.append([t, str(c), f"{ratio:.1f}%"])
    type_table = render_table(["type", "commits", "share"], type_rows or [["-", "0", "0%"]])

    # 커밋 메시지 언어 분포
    lang_rows = []
    for t, c in sorted(agg["lang_counter"].items(), key=lambda kv: kv[1], reverse=True):
        ratio = (c / total_commits * 100) if total_commits else 0
        lang_rows.append([t, str(c), f"{ratio:.1f}%"])
    lang_table = render_table(["language", "commits", "share"], lang_rows or [["-", "0", "0%"]])

    # 3. PR & 리뷰
    if gh.get("available"):
        pr_lines = [
            f"- GitHub 계정: `{gh['login']}`",
            f"- PR opened: {gh['prs_opened']}",
            f"- PR merged: {gh['prs_merged']}",
            f"- PR reviewed-by me: {gh['prs_reviewed']}",
            f"- Issues opened: {gh['issues_opened']}",
        ]
    else:
        pr_lines = ["- `gh` CLI 없음 또는 인증 안 됨 — PR 활동 수집 스킵"]

    # 4. 협업 시그널 (파일 오버랩은 타인 커밋이 필요하므로 간이 구현: 동일 파일 내 타인 커밋 존재 여부)
    overlap_rows = _compute_overlaps(all_stats, author_emails, since, until)
    if overlap_rows:
        overlap_table = render_table(
            ["repo", "file", "my_commits", "others_commits", "others_authors"],
            overlap_rows[:20],
        )
    else:
        overlap_table = "- 오버랩 없음 또는 수집 실패"

    # 5. 파일 TOP-20
    top_files = sorted(agg["file_change_counter"].items(), key=lambda kv: kv[1], reverse=True)[:20]
    file_rows = [[k.split("::", 1)[0], k.split("::", 1)[1], str(v)] for k, v in top_files]
    file_table = render_table(
        ["repo", "file", "touches"],
        file_rows or [["-", "-", "0"]],
    )

    # 6. 리듬
    weekday_names = ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"]
    weekday_rows = []
    for i in range(7):
        c = agg["weekday_counter"].get(i, 0)
        weekday_rows.append([weekday_names[i], str(c)])
    weekday_table = render_table(["weekday", "commits"], weekday_rows)

    hour_rows = [[f"{h:02d}", str(agg["hour_counter"].get(h, 0))] for h in range(24)]
    hour_table = render_table(["hour", "commits"], hour_rows)

    month_rows = [[m, str(c)] for m, c in sorted(agg["month_counter"].items())]
    month_table = render_table(["month", "commits"], month_rows or [["-", "0"]])

    # 7. 메타 자산
    meta_lines = [
        f"- 문서 파일 변경: {agg['doc_file_changes']}",
        f"- 테스트 파일 변경: {agg['test_file_changes']}",
        f"- CI 파일 변경: {agg['ci_file_changes']}",
        f"- 의존성 파일 변경: {agg['deps_file_changes']}",
    ]

    # 8. Obsidian
    obsidian_lines = [
        f"- Daily 노트 수: {obsidian['daily_notes']}",
        f"- Daily 노트 총 단어 수: {obsidian['total_words']}",
        f"- Weekly 보고서 수: {obsidian['reports_weekly']}",
    ]

    # 9. 프로젝트 그룹별 요약
    group_rows = []
    for group, info in sorted(agg["by_group"].items(), key=lambda kv: kv[1]["commits"], reverse=True):
        share = (info["commits"] / total_commits * 100) if total_commits else 0
        group_rows.append(
            [
                group,
                str(info["commits"]),
                str(info["ins"]),
                str(info["del"]),
                f"{share:.1f}%",
                str(len(info["repos"])),
            ]
        )
    group_table = render_table(
        ["group", "commits", "ins", "del", "share", "repos"],
        group_rows or [["-", "0", "0", "0", "0%", "0"]],
    )

    # 10. 재현 가능성
    scope_str = ",".join(scope_patterns) if scope_patterns else "ALL (~/Workspace/*/.git)"
    author_pattern = "|".join(re.escape(e) for e in author_emails) if author_emails else "<email>"
    repro_lines = [
        f"- Author filter: `{author_email or '(unfiltered)'}`",
        f"- Scope patterns: `{scope_str}`",
        f"- Range: `{since.isoformat()} .. {until.isoformat()}`",
        f"- Repos scanned: {len(all_stats)} / with commits: {sum(1 for s in all_stats if s.total_commits)}",
        "- Core command per repo:",
        "  ```",
        f"  git -C <repo> log --since={since.isoformat()} --until={(until + timedelta(days=1)).isoformat()} \\",
        f"      --perl-regexp --author='{author_pattern}' --no-merges --numstat --pretty=format:...",
        "  ```",
    ]

    # 헤더
    tag_list = ["portrait", "retrospective", "dev-data-collector"]
    frontmatter = [
        "---",
        f'date: "{date.today().isoformat()}"',
        "type: portrait",
        f'period: "{label}"',
        f'range: "{since.isoformat()}..{until.isoformat()}"',
        f'generated_at: "{now}"',
        'generated_by: "dev-data-collector v0.1"',
        f'tags: [{", ".join(tag_list)}]',
        "---",
    ]

    body = [
        "",
        f"# Developer Portrait — {label}",
        "",
        f"**기간**: {since.isoformat()} ~ {until.isoformat()}",
        f"**저자 필터**: `{author_email or '(없음)'}`",
        f"**총 커밋**: {total_commits} / insertions {total_ins} / deletions {total_del}",
        "",
        "> 이 문서는 객관 수치만 담는다. 해석·판단 문구는 `career-analyzer`로 별도 생성.",
        "",
        "---",
        "",
        "## 1. 레포별 커밋 볼륨",
        "",
        repo_table,
        "",
        "## 2. 작업 유형 분포 (conventional commit prefix)",
        "",
        type_table,
        "",
        "### 2.1 커밋 메시지 언어 분포",
        "",
        lang_table,
        "",
        "## 3. PR & 리뷰 활동",
        "",
        "\n".join(pr_lines),
        "",
        "## 4. 파일 오버랩 (협업 시그널, 상위 20)",
        "",
        overlap_table,
        "",
        "## 5. 파일 TOP-20 (변경 횟수 기준)",
        "",
        file_table,
        "",
        "## 6. 리듬",
        "",
        "### 6.1 요일별",
        "",
        weekday_table,
        "",
        "### 6.2 시간대별",
        "",
        hour_table,
        "",
        "### 6.3 월별",
        "",
        month_table,
        "",
        "## 7. 메타 자산 (파일 변경 카운트)",
        "",
        "\n".join(meta_lines),
        "",
        "## 8. Obsidian 활동",
        "",
        "\n".join(obsidian_lines),
        "",
        "## 9. 프로젝트 그룹별 요약",
        "",
        group_table,
        "",
        "## 10. 원본 데이터 출처 (재현 가능성)",
        "",
        "\n".join(repro_lines),
        "",
    ]

    return "\n".join(frontmatter) + "\n" + "\n".join(body)


def _compute_overlaps(
    all_stats: list[RepoStats],
    author_emails: list[str],
    since: date,
    until: date,
) -> list[list[str]]:
    """내가 건드린 파일 중 동기간 타인 커밋이 있는 파일을 찾음.
    레포당 추가 git log 1회 (타인 전체). 비용 감수."""
    rows: list[list[str]] = []
    if not author_emails:
        return rows
    my_emails = set(author_emails)
    since_q = since.isoformat()
    until_q = (until + timedelta(days=1)).isoformat()
    for rs in all_stats:
        my_files: Counter = Counter()
        for c in rs.commits:
            for f in c.files:
                my_files[f] += 1
        if not my_files:
            continue
        # 타인 커밋 수집
        sep = "\x1f"
        record_sep = "\x1e"
        fmt = sep.join(["%H", "%ae"])
        out = run(
            [
                "git",
                "log",
                f"--since={since_q}",
                f"--until={until_q}",
                "--no-merges",
                "--numstat",
                f"--pretty=format:{record_sep}{fmt}",
            ],
            cwd=rs.path,
        )
        if not out:
            continue
        others: dict[str, set[str]] = defaultdict(set)
        for raw in out.split(record_sep):
            raw = raw.strip("\n")
            if not raw:
                continue
            lines = raw.split("\n")
            parts = lines[0].split(sep)
            if len(parts) < 2:
                continue
            sha, email = parts[0], parts[1]
            if email in my_emails:
                continue
            for nline in lines[1:]:
                if not nline.strip():
                    continue
                np = nline.split("\t")
                if len(np) != 3:
                    continue
                path = np[2]
                others[path].add(email)
        for f, my_count in my_files.most_common():
            if f in others:
                rows.append(
                    [
                        rs.repo,
                        f,
                        str(my_count),
                        str(sum(1 for _ in others[f])),
                        ",".join(sorted(others[f])),
                    ]
                )
    rows.sort(key=lambda r: int(r[2]), reverse=True)
    return rows


def decide_output_path(label: str) -> Path:
    SNAPSHOT_DIR.mkdir(parents=True, exist_ok=True)
    return SNAPSHOT_DIR / f"{label}-portrait.md"


def parse_args() -> argparse.Namespace:
    # 공용 옵션을 각 subparser에 상속시키기 위해 parent parser 사용
    common = argparse.ArgumentParser(add_help=False)
    common.add_argument("--scope", default="", help="fnmatch 패턴 콤마 구분")
    common.add_argument("--email", default="", help="저자 이메일 오버라이드")
    common.add_argument("--out", default="", help="출력 경로 오버라이드")
    common.add_argument("--dry-run", action="store_true")

    p = argparse.ArgumentParser(parents=[common])
    sub = p.add_subparsers(dest="mode", required=True)
    sub.add_parser("quarter", parents=[common], help="지난 분기")
    sub.add_parser("year", parents=[common], help="지난 1년")
    rp = sub.add_parser("range", parents=[common], help="기간 직접 지정")
    rp.add_argument("since")
    rp.add_argument("until")
    cp = sub.add_parser("custom", parents=[common], help="상세 옵션")
    cp.add_argument("--from", dest="since", required=True)
    cp.add_argument("--to", dest="until", required=True)
    cp.add_argument("--label", default="")
    return p.parse_args()


def resolve_range(args: argparse.Namespace) -> tuple[date, date, str, list[str] | None]:
    today = date.today()
    scope_raw = args.scope
    if args.mode == "quarter":
        s, u, lab = quarter_range(today)
    elif args.mode == "year":
        s, u, lab = year_range(today)
    elif args.mode == "range":
        s = date.fromisoformat(args.since)
        u = date.fromisoformat(args.until)
        lab = f"{s.isoformat()}_{u.isoformat()}"
    elif args.mode == "custom":
        s = date.fromisoformat(args.since)
        u = date.fromisoformat(args.until)
        lab = args.label or f"{s.isoformat()}_{u.isoformat()}"
        scope_raw = scope_raw or args.scope
    else:
        raise SystemExit(f"unknown mode: {args.mode}")
    scope_patterns = [x.strip() for x in scope_raw.split(",") if x.strip()] or None
    return s, u, lab, scope_patterns


def main() -> int:
    args = parse_args()
    since, until, label, scope_patterns = resolve_range(args)
    if args.email:
        author_emails = [e.strip() for e in args.email.split(",") if e.strip()]
    else:
        author_emails = get_user_emails()

    print(f"[collector] range: {since} .. {until}", file=sys.stderr)
    print(f"[collector] label: {label}", file=sys.stderr)
    print(f"[collector] authors: {author_emails or '(unfiltered)'}", file=sys.stderr)
    print(f"[collector] scope: {scope_patterns or 'ALL'}", file=sys.stderr)

    repos = discover_repos(scope_patterns)
    print(f"[collector] repos discovered: {len(repos)}", file=sys.stderr)

    all_stats: list[RepoStats] = []
    for r in repos:
        rs = collect_repo_stats(r, since, until, author_emails)
        if rs.total_commits > 0:
            print(f"  {r.name}: {rs.total_commits}", file=sys.stderr)
        all_stats.append(rs)

    agg = aggregate(all_stats)
    gh = gh_activity(since, until, author_emails)
    obsidian = count_obsidian_activity(since, until)

    md = render_markdown(label, since, until, author_emails, all_stats, agg, gh, obsidian, scope_patterns)

    if args.out:
        out_path = Path(os.path.expanduser(args.out))
    else:
        out_path = decide_output_path(label)

    if args.dry_run:
        print(md)
        print(f"\n[collector] (dry-run) would write: {out_path}", file=sys.stderr)
        return 0

    out_path.parent.mkdir(parents=True, exist_ok=True)
    out_path.write_text(md)
    print(f"[collector] written: {out_path}", file=sys.stderr)
    # JSON sidecar for analyzer (optional but helpful)
    sidecar = out_path.with_suffix(".json")
    sidecar.write_text(
        json.dumps(
            {
                "label": label,
                "since": since.isoformat(),
                "until": until.isoformat(),
                "authors": author_emails,
                "scope": scope_patterns,
                "total_commits": agg["total_commits"],
                "by_group": agg["by_group"],
                "type_counter": dict(agg["type_counter"]),
                "lang_counter": dict(agg["lang_counter"]),
                "meta": {
                    "test_file_changes": agg["test_file_changes"],
                    "doc_file_changes": agg["doc_file_changes"],
                    "ci_file_changes": agg["ci_file_changes"],
                    "deps_file_changes": agg["deps_file_changes"],
                },
                "obsidian": obsidian,
                "github": gh,
            },
            ensure_ascii=False,
            indent=2,
        )
    )
    print(f"[collector] sidecar: {sidecar}", file=sys.stderr)
    return 0


if __name__ == "__main__":
    sys.exit(main())
