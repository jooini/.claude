#!/usr/bin/env python3
"""Append mcp-local-rag query result chunk ids to ~/.claude/cache/rag-usage.jsonl."""

from __future__ import annotations

import argparse
import json
import os
import sys
from datetime import datetime, timezone
from pathlib import Path
from typing import Any, Iterable


HOME = Path.home()
DEFAULT_USAGE_LOG = Path(os.environ.get("RAG_USAGE_LOG", HOME / ".claude/cache/rag-usage.jsonl"))


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="stdin으로 받은 mcp-local-rag query JSON에서 chunk_id를 추출해 사용 로그에 기록합니다.",
        epilog=(
            "수동 호출 예: RESULT=$(node ~/Workspace/mcp-local-rag/dist/index.js "
            "--db-path ~/Workspace/lancedb --cache-dir ~/.claude/cache/rag-models "
            "--model-name Xenova/multilingual-e5-small query \"BFF timeout\"); "
            "printf '%s' \"$RESULT\" | python3 ~/.claude/scripts/rag-usage-logger.py; "
            "printf '%s\\n' \"$RESULT\""
        ),
    )
    parser.add_argument("--usage-log", default=str(DEFAULT_USAGE_LOG), help="사용 로그 JSONL 경로")
    parser.add_argument("--session-id", default=session_id(), help="세션 ID")
    parser.add_argument("--dry-run", action="store_true", help="파일에 쓰지 않고 추출 결과만 출력")
    parser.add_argument(
        "--hook-point",
        action="store_true",
        help="mcp-local-rag 소스에 붙일 수 있는 hook point 제안만 출력",
    )
    return parser.parse_args()


def session_id() -> str:
    return (
        os.environ.get("CLAUDE_SESSION_ID")
        or os.environ.get("CODEX_SESSION_ID")
        or os.environ.get("SESSION_ID")
        or "manual"
    )


def stable_chunk_id(item: dict[str, Any]) -> str:
    explicit = item.get("chunk_id") or item.get("chunkId")
    if explicit is not None:
        return str(explicit)

    file_path = item.get("filePath") or item.get("file_path")
    chunk_index = item.get("chunkIndex")
    if chunk_index is None:
        chunk_index = item.get("chunk_index")
    if file_path is not None and chunk_index is not None:
        try:
            chunk_index = int(chunk_index)
        except (TypeError, ValueError):
            pass
        return f"{file_path}#{chunk_index}"

    raw_id = item.get("id")
    return str(raw_id) if raw_id is not None else ""


def maybe_json(value: str) -> Any | None:
    stripped = value.strip()
    if not stripped or stripped[0] not in "[{":
        return None
    try:
        return json.loads(stripped)
    except json.JSONDecodeError:
        return None


def iter_result_items(value: Any) -> Iterable[dict[str, Any]]:
    if isinstance(value, list):
        for item in value:
            yield from iter_result_items(item)
        return

    if not isinstance(value, dict):
        if isinstance(value, str):
            parsed = maybe_json(value)
            if parsed is not None:
                yield from iter_result_items(parsed)
        return

    if (
        "chunk_id" in value
        or "chunkId" in value
        or ("filePath" in value and "chunkIndex" in value)
        or ("file_path" in value and "chunk_index" in value)
    ):
        yield value
        return

    content = value.get("content")
    if isinstance(content, list):
        for block in content:
            if isinstance(block, dict) and isinstance(block.get("text"), str):
                parsed = maybe_json(block["text"])
                if parsed is not None:
                    yield from iter_result_items(parsed)

    for key in ("results", "chunks", "data"):
        if key in value:
            yield from iter_result_items(value[key])


def parse_input(stdin_text: str) -> list[str]:
    parsed = maybe_json(stdin_text)
    if parsed is None:
        items: list[dict[str, Any]] = []
        for line in stdin_text.splitlines():
            line_parsed = maybe_json(line)
            if line_parsed is not None:
                items.extend(iter_result_items(line_parsed))
    else:
        items = list(iter_result_items(parsed))

    seen: set[str] = set()
    ordered: list[str] = []
    for item in items:
        chunk_id = stable_chunk_id(item)
        if chunk_id and chunk_id not in seen:
            seen.add(chunk_id)
            ordered.append(chunk_id)
    return ordered


def hook_point_text() -> str:
    return """mcp-local-rag hook point 제안(직접 수정 금지):
- MCP 서버: src/server/index.ts 의 handleQueryDocuments()에서 results 배열을 만든 직후
  외부 명령으로 JSON.stringify(results)를 넘기면 된다.
- CLI: src/cli/query.ts 의 process.stdout.write(JSON.stringify(results, null, 2)) 직전
  동일한 JSON을 ~/.claude/scripts/rag-usage-logger.py stdin으로 전달하면 된다.
- 현재 도구는 외부 프로젝트를 패치하지 않고, 수동 pipe/tee 호출을 전제로 한다."""


def main() -> int:
    args = parse_args()
    if args.hook_point:
        print(hook_point_text())
        return 0

    stdin_text = sys.stdin.read()
    chunk_ids = parse_input(stdin_text)
    now = datetime.now(timezone.utc).isoformat()
    rows = [
        {"chunk_id": chunk_id, "query_at": now, "session_id": args.session_id}
        for chunk_id in chunk_ids
    ]

    usage_log = Path(args.usage_log).expanduser()
    if rows and not args.dry_run:
        usage_log.parent.mkdir(parents=True, exist_ok=True)
        with usage_log.open("a", encoding="utf-8") as handle:
            for row in rows:
                handle.write(json.dumps(row, ensure_ascii=False) + "\n")

    print(
        json.dumps(
            {
                "usage_log": str(usage_log),
                "session_id": args.session_id,
                "logged": len(rows),
                "chunk_ids": chunk_ids,
                "dry_run": args.dry_run,
            },
            ensure_ascii=False,
            indent=2,
        )
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
