#!/usr/bin/env python3
"""
vault-find — 인덱스(frontmatter) + ripgrep(풀텍스트) + 옵션 의미론 검색 통합.

기본: 인자 없으면 최근 14일 정리노트.
출력: 마크다운 표 (제목 / 날짜 / 프로젝트 / 태그 / obsidian:// URI).
"""

from __future__ import annotations

import argparse
import json
import os
import shutil
import subprocess
import sys
from datetime import datetime, timedelta
from pathlib import Path
from typing import Any

INDEX_PATH = Path("~/.cache/weaversbrain-vault-index.json").expanduser()
DEFAULT_VAULT = Path("~/Workspace/weaversbrain/weaversbrain").expanduser()


def load_index() -> dict[str, Any] | None:
    if not INDEX_PATH.exists():
        return None
    try:
        return json.loads(INDEX_PATH.read_text(encoding="utf-8"))
    except (json.JSONDecodeError, OSError):
        return None


def ensure_index_fresh() -> dict[str, Any]:
    payload = load_index()
    age_hours = 24
    if payload:
        generated = payload.get("generated_at", "")
        try:
            ts = datetime.fromisoformat(generated)
            age_hours = (datetime.now() - ts).total_seconds() / 3600
        except ValueError:
            age_hours = 999

    if not payload or age_hours > 6:
        print(f"# 인덱스 재생성 (age={age_hours:.1f}h)", file=sys.stderr)
        builder = DEFAULT_VAULT / "scripts" / "build_vault_index.py"
        if builder.exists():
            subprocess.run(["python3", str(builder), "--quiet"], check=False)
            payload = load_index()
    if not payload:
        print("인덱스를 생성할 수 없음", file=sys.stderr)
        sys.exit(1)
    return payload


def filter_recent(notes: list[dict], days: int) -> list[dict]:
    cutoff = (datetime.now() - timedelta(days=days)).strftime("%Y-%m-%d")
    return [n for n in notes if n.get("date", "") >= cutoff]


def filter_project(notes: list[dict], project: str) -> list[dict]:
    return [n for n in notes if (n.get("project") or "").lower() == project.lower()]


def filter_tag(notes: list[dict], tag: str) -> list[dict]:
    tag = tag.lstrip("#").lower()
    return [n for n in notes if tag in {(t or "").lower() for t in (n.get("tags") or [])}]


def filter_keyword_metadata(notes: list[dict], keyword: str) -> list[dict]:
    kw = keyword.lower()
    out = []
    for n in notes:
        haystack = " ".join(
            [
                n.get("title", "") or "",
                n.get("rel_path", "") or "",
                " ".join(n.get("tags") or []),
            ]
        ).lower()
        if kw in haystack:
            out.append(n)
    return out


def ripgrep_fulltext(keyword: str, vault: Path, limit: int = 60) -> list[str]:
    if not shutil.which("rg"):
        return []
    cmd = [
        "rg", "--files-with-matches", "--max-count", "1",
        "-i", "-g", "*.md",
        "--glob", "!.git/**", "--glob", "!.obsidian/**",
        "--glob", "!.venv/**", "--glob", "!Archive/**",
        "--glob", "!MOC.md",
        keyword, str(vault),
    ]
    try:
        out = subprocess.check_output(cmd, text=True, stderr=subprocess.DEVNULL)
    except subprocess.CalledProcessError:
        return []
    return out.strip().splitlines()[:limit]


def merge_fulltext_hits(notes: list[dict], hit_paths: list[str]) -> list[dict]:
    by_path = {n["path"]: n for n in notes}
    hits = [by_path[p] for p in hit_paths if p in by_path]
    return hits


def call_local_rag(keyword: str) -> list[str]:
    """local-rag MCP 호출 자리표시자.
    Claude Code 세션에서 mcp__local-rag__query_documents 를 직접 부르는 게 더 풍부.
    여기서는 fallback 으로 빈 리스트.
    """
    return []


def render_table(notes: list[dict], limit: int) -> str:
    if not notes:
        return "_검색 결과 없음._\n"
    lines = [
        "| 날짜 | 프로젝트 | 제목 | 태그 | 열기 |",
        "|------|----------|------|------|------|",
    ]
    for n in notes[:limit]:
        date = n.get("date", "")
        project = n.get("project") or "-"
        title = (n.get("title") or "").replace("|", "\\|")[:70]
        tags = " ".join(("#" + t) for t in (n.get("tags") or [])[:3])
        uri = n.get("obsidian_uri", "")
        link = f"[열기]({uri})"
        lines.append(f"| `{date}` | {project} | {title} | {tags} | {link} |")
    extra = ""
    if len(notes) > limit:
        extra = f"\n_... {len(notes) - limit}개 더 있음. `--limit N` 으로 늘리기._\n"
    return "\n".join(lines) + "\n" + extra


def render_paths(notes: list[dict], limit: int) -> str:
    return "\n".join(n["path"] for n in notes[:limit])


def main() -> int:
    parser = argparse.ArgumentParser(description="Vault 검색")
    parser.add_argument("keyword", nargs="?", default=None)
    parser.add_argument("--project", help="프로젝트명 필터")
    parser.add_argument("--tag", help="태그 필터")
    parser.add_argument("--recent", type=int, help="최근 N일")
    parser.add_argument("--semantic", action="store_true", help="local-rag 의미론 검색 힌트 출력")
    parser.add_argument("--limit", type=int, default=20)
    parser.add_argument("--paths-only", action="store_true", help="경로만 출력")
    args = parser.parse_args()

    payload = ensure_index_fresh()
    notes = payload["notes"]

    used_filter = False
    if args.recent is not None:
        notes = filter_recent(notes, args.recent)
        used_filter = True
    if args.project:
        notes = filter_project(notes, args.project)
        used_filter = True
    if args.tag:
        notes = filter_tag(notes, args.tag)
        used_filter = True
    if args.keyword:
        meta_hits = filter_keyword_metadata(notes, args.keyword)
        fulltext_hits = merge_fulltext_hits(notes, ripgrep_fulltext(args.keyword, DEFAULT_VAULT))
        seen = set()
        merged = []
        for n in meta_hits + fulltext_hits:
            if n["path"] in seen:
                continue
            seen.add(n["path"])
            merged.append(n)
        notes = merged
        used_filter = True

    if not used_filter:
        notes = filter_recent(notes, 14)
        header = "# 최근 14일 정리노트"
    else:
        parts = []
        if args.keyword:
            parts.append(f"keyword=`{args.keyword}`")
        if args.project:
            parts.append(f"project=`{args.project}`")
        if args.tag:
            parts.append(f"tag=`{args.tag}`")
        if args.recent is not None:
            parts.append(f"recent={args.recent}d")
        header = "# vault-find · " + " · ".join(parts)

    if args.paths_only:
        print(render_paths(notes, args.limit))
        return 0

    print(header)
    print()
    print(f"_총 {len(notes)}개 일치. 인덱스 생성: {payload.get('generated_at', 'unknown')}_")
    print()
    print(render_table(notes, args.limit))

    if args.semantic and args.keyword:
        print()
        print("**의미론 검색**:")
        print(f"`mcp__local-rag__query_documents(query=\"{args.keyword}\")` 를 직접 호출하세요.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
