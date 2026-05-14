#!/usr/bin/env python3
"""Find relevant RAG chunks that have not been used in answers yet."""

from __future__ import annotations

import argparse
import json
import os
import re
import subprocess
import sys
from collections import Counter
from datetime import datetime, timezone
from pathlib import Path
from typing import Any
from urllib.parse import unquote, urlparse


HOME = Path.home()
DEFAULT_DB_PATH = Path(os.environ.get("DB_PATH", HOME / "Workspace/lancedb"))
DEFAULT_CACHE_DIR = Path(os.environ.get("CACHE_DIR", HOME / ".claude/cache/rag-models"))
DEFAULT_MODEL_NAME = os.environ.get("MODEL_NAME", "Xenova/multilingual-e5-small")
DEFAULT_USAGE_LOG = Path(os.environ.get("RAG_USAGE_LOG", HOME / ".claude/cache/rag-usage.jsonl"))
DEFAULT_MCP_CLI = Path(
    os.environ.get("MCP_LOCAL_RAG_CLI", HOME / "Workspace/mcp-local-rag/dist/index.js")
)
TABLE_NAME = "chunks"
MAX_MCP_CLI_LIMIT = 20


DEPENDENCY_HINT = (
    "Python LanceDB 직접 검색을 쓰려면 다음 패키지가 필요합니다: "
    "python3 -m pip install lancedb pyarrow sentence-transformers. "
    "현재 환경에서는 mcp-local-rag CLI fallback을 우선 사용합니다."
)


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="현재 쿼리와 관련 있지만 사용 로그에 없는 local-rag 휴면 청크를 찾습니다."
    )
    parser.add_argument("query_parts", nargs="*", help='검색 쿼리. 예: "BFF timeout"')
    parser.add_argument("--query", help="검색 쿼리. 위치 인자보다 우선합니다.")
    parser.add_argument("--top-k", type=int, default=20, help="검색 후보 수. CLI는 최대 20입니다.")
    parser.add_argument(
        "--format",
        choices=("json", "markdown", "both"),
        default="both",
        help="출력 형식",
    )
    parser.add_argument("--db-path", default=str(DEFAULT_DB_PATH), help="LanceDB database path")
    parser.add_argument("--cache-dir", default=str(DEFAULT_CACHE_DIR), help="모델 cache directory")
    parser.add_argument("--model-name", default=DEFAULT_MODEL_NAME, help="임베딩 모델명")
    parser.add_argument("--usage-log", default=str(DEFAULT_USAGE_LOG), help="RAG 사용 로그 JSONL")
    parser.add_argument("--mcp-cli", default=str(DEFAULT_MCP_CLI), help="mcp-local-rag dist/index.js")
    parser.add_argument("--stats", action="store_true", help="사용 로그와 DB 통계를 출력합니다.")
    return parser.parse_args()


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


def file_source_to_path(source: Any) -> str | None:
    if not isinstance(source, str) or not source.startswith("file://"):
        return None
    parsed = urlparse(source)
    if parsed.scheme != "file":
        return None
    return unquote(parsed.path)


def candidate_ids(item: dict[str, Any]) -> set[str]:
    ids = {stable_chunk_id(item)}
    for key in ("id", "db_id", "chunk_id", "chunkId"):
        value = item.get(key)
        if value is not None:
            ids.add(str(value))
    source_path = file_source_to_path(item.get("source"))
    chunk_index = item.get("chunkIndex")
    if chunk_index is None:
        chunk_index = item.get("chunk_index")
    if source_path and chunk_index is not None:
        try:
            chunk_index = int(chunk_index)
        except (TypeError, ValueError):
            pass
        ids.add(f"{source_path}#{chunk_index}")
    return {value for value in ids if value}


def dedupe_key(item: dict[str, Any]) -> str:
    source_path = file_source_to_path(item.get("source"))
    file_path = source_path or str(item.get("file_path") or "")
    chunk_index = item.get("chunk_index")
    if file_path and chunk_index is not None:
        return f"{file_path}#{chunk_index}"
    return str(item.get("chunk_id") or stable_chunk_id(item))


def read_usage_counts(path: Path) -> Counter[str]:
    counts: Counter[str] = Counter()
    if not path.exists():
        return counts

    with path.open("r", encoding="utf-8") as handle:
        for line in handle:
            line = line.strip()
            if not line:
                continue
            try:
                row = json.loads(line)
            except json.JSONDecodeError:
                continue
            chunk_id = row.get("chunk_id") or row.get("chunkId")
            if chunk_id:
                counts[str(chunk_id)] += 1
    return counts


def parse_iso_datetime(value: Any) -> datetime | None:
    if not isinstance(value, str) or not value:
        return None
    try:
        normalized = value.replace("Z", "+00:00")
        parsed = datetime.fromisoformat(normalized)
        return parsed if parsed.tzinfo else parsed.replace(tzinfo=timezone.utc)
    except ValueError:
        return None


def recency_factor(timestamp: Any) -> float:
    parsed = parse_iso_datetime(timestamp)
    if parsed is None:
        return 1.0

    age_days = max(0, (datetime.now(timezone.utc) - parsed).days)
    if age_days <= 30:
        return 1.0
    if age_days <= 180:
        return 0.85
    if age_days <= 365:
        return 0.75
    return 0.65


def relevance_from_distance(score: Any) -> float:
    try:
        distance = float(score)
    except (TypeError, ValueError):
        distance = 0.0
    return 1.0 / (1.0 + max(distance, 0.0))


def compact_text(text: Any, limit: int = 200) -> str:
    value = re.sub(r"\s+", " ", str(text or "")).strip()
    if len(value) <= limit:
        return value
    return value[: limit - 1].rstrip() + "..."


def query_tokens(query: str) -> set[str]:
    tokens = {
        token.lower()
        for token in re.findall(r"[A-Za-z0-9가-힣_./:-]{2,}", query)
        if len(token) >= 2
    }
    stopwords = {
        "the",
        "and",
        "for",
        "with",
        "from",
        "this",
        "that",
        "현재",
        "작업",
        "관련",
        "구현",
        "도구",
    }
    return tokens - stopwords


def explain_relevance(query: str, item: dict[str, Any]) -> str:
    haystack = " ".join(
        str(item.get(key) or "")
        for key in ("file_path", "file_title", "source", "text", "excerpt")
    ).lower()
    overlaps = sorted(token for token in query_tokens(query) if token.lower() in haystack)
    if overlaps:
        shown = ", ".join(overlaps[:5])
        return f"쿼리 핵심어({shown})가 파일 경로 또는 청크 내용과 겹칩니다."
    return "mcp-local-rag의 의미 검색 상위 결과라 현재 작업 맥락과 가깝습니다."


def normalize_candidate(raw: dict[str, Any], backend: str, query: str) -> dict[str, Any]:
    file_path = raw.get("filePath") or raw.get("file_path") or ""
    chunk_index = raw.get("chunkIndex")
    if chunk_index is None:
        chunk_index = raw.get("chunk_index")
    try:
        chunk_index = int(chunk_index)
    except (TypeError, ValueError):
        chunk_index = None

    normalized = {
        "chunk_id": stable_chunk_id(raw),
        "db_id": raw.get("id"),
        "file_path": file_path,
        "chunk_index": chunk_index,
        "file_title": raw.get("fileTitle") or raw.get("file_title"),
        "source": raw.get("source"),
        "text": raw.get("text") or "",
        "excerpt": compact_text(raw.get("text"), 200),
        "score": raw.get("score", raw.get("_distance", raw.get("_score"))),
        "timestamp": raw.get("timestamp"),
        "search_backend": backend,
    }
    normalized["relevance"] = relevance_from_distance(normalized["score"])
    normalized["recency_factor"] = recency_factor(normalized["timestamp"])
    normalized["why_now"] = explain_relevance(query, normalized)
    return normalized


def parse_json_stdout(stdout: str) -> Any:
    stripped = stdout.strip()
    if not stripped:
        raise ValueError("CLI stdout이 비어 있습니다.")
    try:
        return json.loads(stripped)
    except json.JSONDecodeError:
        start = stripped.find("[")
        end = stripped.rfind("]")
        if start >= 0 and end > start:
            return json.loads(stripped[start : end + 1])
        raise


def query_with_mcp_cli(
    query: str,
    top_k: int,
    db_path: Path,
    cache_dir: Path,
    model_name: str,
    mcp_cli: Path,
) -> list[dict[str, Any]]:
    if not mcp_cli.exists():
        raise RuntimeError(f"mcp-local-rag CLI를 찾을 수 없습니다: {mcp_cli}")

    limit = max(1, min(top_k, MAX_MCP_CLI_LIMIT))
    command = [
        "node",
        str(mcp_cli),
        "--db-path",
        str(db_path),
        "--cache-dir",
        str(cache_dir),
        "--model-name",
        model_name,
        "query",
        "--limit",
        str(limit),
        query,
    ]
    completed = subprocess.run(
        command,
        check=False,
        capture_output=True,
        text=True,
        timeout=180,
    )
    if completed.returncode != 0:
        reason = completed.stderr.strip() or completed.stdout.strip()
        raise RuntimeError(f"mcp-local-rag CLI query 실패: {reason}")

    data = parse_json_stdout(completed.stdout)
    if not isinstance(data, list):
        raise RuntimeError("mcp-local-rag CLI 출력이 JSON 배열이 아닙니다.")
    return [normalize_candidate(item, "mcp-local-rag-cli", query) for item in data]


def import_real_lancedb() -> Any:
    workspace_lancedb = (HOME / "Workspace/lancedb").resolve()
    cleaned_path: list[str] = []
    for entry in sys.path:
        if not entry:
            cleaned_path.append(entry)
            continue
        try:
            if Path(entry).resolve() == workspace_lancedb:
                continue
        except OSError:
            pass
        cleaned_path.append(entry)
    sys.path[:] = cleaned_path

    import lancedb  # type: ignore[import-not-found]

    if not hasattr(lancedb, "connect"):
        raise ImportError("현재 import된 lancedb는 Python 패키지가 아니라 로컬 DB 디렉터리입니다.")
    return lancedb


def query_with_python_lancedb(
    query: str,
    top_k: int,
    db_path: Path,
    cache_dir: Path,
    model_name: str,
) -> list[dict[str, Any]]:
    try:
        lancedb = import_real_lancedb()
        from sentence_transformers import SentenceTransformer  # type: ignore[import-not-found]
    except ImportError as exc:
        raise RuntimeError(f"{DEPENDENCY_HINT} 원인: {exc}") from exc

    model = SentenceTransformer(model_name, cache_folder=str(cache_dir))
    query_vector = model.encode(query, normalize_embeddings=True)
    if hasattr(query_vector, "tolist"):
        query_vector = query_vector.tolist()

    db = lancedb.connect(str(db_path))
    table = db.open_table(TABLE_NAME)
    rows = table.search(query_vector).limit(max(1, top_k)).to_list()
    return [normalize_candidate(item, "python-lancedb", query) for item in rows]


def query_candidates(args: argparse.Namespace, query: str) -> tuple[list[dict[str, Any]], list[str]]:
    warnings: list[str] = []
    db_path = Path(args.db_path).expanduser()
    cache_dir = Path(args.cache_dir).expanduser()
    mcp_cli = Path(args.mcp_cli).expanduser()

    try:
        return (
            query_with_mcp_cli(query, args.top_k, db_path, cache_dir, args.model_name, mcp_cli),
            warnings,
        )
    except Exception as cli_error:
        warnings.append(str(cli_error))

    try:
        return (
            query_with_python_lancedb(query, args.top_k, db_path, cache_dir, args.model_name),
            warnings,
        )
    except Exception as python_error:
        warnings.append(str(python_error))
        raise RuntimeError("모든 검색 backend가 실패했습니다.\n- " + "\n- ".join(warnings))


_NOISE_PATH_RE = re.compile(r"(?:/\.venv/|/node_modules/|/site-packages/|/dist/|/build/|/__pycache__/|/\.pnpm/|/\.git/|/_vendor/|/lib/python\d)")


def _is_noise_path(file_path: Any) -> bool:
    if not file_path:
        return False
    return bool(_NOISE_PATH_RE.search(str(file_path)))


def rank_dormant(
    candidates: list[dict[str, Any]],
    usage_counts: Counter[str],
) -> list[dict[str, Any]]:
    dormant: list[dict[str, Any]] = []
    for item in candidates:
        # 의존성/빌드 산출물 청크 제외 — 사용자 자산만 휴면으로 인정
        if _is_noise_path(item.get("file_path")) or _is_noise_path(item.get("chunk_id")):
            continue
        synthetic = {
            "filePath": item.get("file_path"),
            "chunkIndex": item.get("chunk_index"),
            "id": item.get("db_id"),
            "chunk_id": item.get("chunk_id"),
            "source": item.get("source"),
        }
        usage_count = max((usage_counts.get(value, 0) for value in candidate_ids(synthetic)), default=0)
        item["usage_count"] = usage_count
        usage_factor = max(0.0, 1.0 - (usage_count / 10.0))
        item["usage_factor"] = usage_factor
        item["dormant_score"] = item["relevance"] * usage_factor * item["recency_factor"]
        if usage_count == 0:
            dormant.append(item)

    dormant.sort(key=lambda row: row["dormant_score"], reverse=True)
    deduped: list[dict[str, Any]] = []
    seen: set[str] = set()
    for item in dormant:
        key = dedupe_key(item)
        if key in seen:
            continue
        seen.add(key)
        deduped.append(item)
    return deduped


def status_via_cli(args: argparse.Namespace) -> dict[str, Any]:
    mcp_cli = Path(args.mcp_cli).expanduser()
    if not mcp_cli.exists():
        return {"error": f"mcp-local-rag CLI를 찾을 수 없습니다: {mcp_cli}"}

    command = [
        "node",
        str(mcp_cli),
        "--db-path",
        str(Path(args.db_path).expanduser()),
        "status",
    ]
    completed = subprocess.run(command, check=False, capture_output=True, text=True, timeout=60)
    if completed.returncode != 0:
        return {"error": completed.stderr.strip() or completed.stdout.strip()}
    try:
        return json.loads(completed.stdout.strip())
    except json.JSONDecodeError:
        return {"raw": completed.stdout.strip()}


def build_payload(
    query: str,
    candidates: list[dict[str, Any]],
    dormant: list[dict[str, Any]],
    usage_log: Path,
    warnings: list[str],
) -> dict[str, Any]:
    return {
        "query": query,
        "generated_at": datetime.now(timezone.utc).isoformat(),
        "usage_log": str(usage_log),
        "total_candidates": len(candidates),
        "dormant_candidates": len(dormant),
        "chunks": dormant[:3],
        "warnings": warnings,
    }


def format_markdown(payload: dict[str, Any]) -> str:
    lines = [
        "## 휴면 RAG 청크 추천",
        "",
        f"- query: {payload['query']}",
        f"- usage_log: {payload['usage_log']}",
        f"- dormant_candidates: {payload['dormant_candidates']} / {payload['total_candidates']}",
        "",
    ]
    chunks = payload.get("chunks", [])
    if not chunks:
        lines.append("휴면 후보가 없습니다.")
    for index, chunk in enumerate(chunks, start=1):
        file_path = chunk.get("source") or chunk.get("file_path") or "(unknown)"
        chunk_index = chunk.get("chunk_index")
        lines.extend(
            [
                f"### {index}. {file_path}#chunk-{chunk_index}",
                f"- dormant_score: {chunk.get('dormant_score', 0):.4f}",
                f"- relevance: {chunk.get('relevance', 0):.4f}",
                f"- recency_factor: {chunk.get('recency_factor', 1):.2f}",
                f"- chunk_id: {chunk.get('chunk_id')}",
                f"- 왜 지금 관련 있는지: {chunk.get('why_now')}",
                f"- 발췌: {chunk.get('excerpt')}",
                "",
            ]
        )
    warnings = payload.get("warnings") or []
    if warnings:
        lines.append("### 경고")
        lines.extend(f"- {warning}" for warning in warnings)
    return "\n".join(lines).rstrip()


def build_stats(args: argparse.Namespace, usage_counts: Counter[str]) -> dict[str, Any]:
    status = status_via_cli(args)
    chunk_count = status.get("chunkCount")
    dormant_estimate = None
    if isinstance(chunk_count, int):
        dormant_estimate = max(0, chunk_count - len(usage_counts))
    return {
        "generated_at": datetime.now(timezone.utc).isoformat(),
        "usage_log": str(Path(args.usage_log).expanduser()),
        "usage_events": sum(usage_counts.values()),
        "used_unique_chunks": len(usage_counts),
        "db_status": status,
        "estimated_dormant_chunks": dormant_estimate,
    }


def emit(payload: dict[str, Any], output_format: str, markdown_builder=format_markdown) -> None:
    if output_format in ("json", "both"):
        print(json.dumps(payload, ensure_ascii=False, indent=2))
    if output_format == "both":
        print("\n---\n")
    if output_format in ("markdown", "both"):
        print(markdown_builder(payload))


def format_stats_markdown(payload: dict[str, Any]) -> str:
    status = payload.get("db_status", {})
    return "\n".join(
        [
            "## dormant-chunks stats",
            "",
            f"- usage_log: {payload['usage_log']}",
            f"- usage_events: {payload['usage_events']}",
            f"- used_unique_chunks: {payload['used_unique_chunks']}",
            f"- db_chunk_count: {status.get('chunkCount', 'unknown')}",
            f"- db_document_count: {status.get('documentCount', 'unknown')}",
            f"- estimated_dormant_chunks: {payload.get('estimated_dormant_chunks')}",
        ]
    )


def main() -> int:
    args = parse_args()
    usage_log = Path(args.usage_log).expanduser()
    usage_counts = read_usage_counts(usage_log)

    if args.stats or (args.query_parts and args.query_parts[0] == "stats"):
        emit(build_stats(args, usage_counts), args.format, format_stats_markdown)
        return 0

    query = args.query or " ".join(args.query_parts).strip()
    if not query:
        print("error: --query 또는 위치 인자로 current_query를 전달하세요.", file=sys.stderr)
        return 2

    candidates, warnings = query_candidates(args, query)
    dormant = rank_dormant(candidates, usage_counts)
    payload = build_payload(query, candidates, dormant, usage_log, warnings)
    emit(payload, args.format)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
