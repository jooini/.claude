"""Workspace Console catalog.db — 모든 부품 (hook/skill/agent/command/repo/mcp) 단일 인덱스."""
from __future__ import annotations

from dataclasses import dataclass
from datetime import datetime, timezone
from enum import Enum
from pathlib import Path
import json
import sqlite3
from typing import Iterator


class EntityType(str, Enum):
    HOOK = "hook"
    SKILL = "skill"
    AGENT = "agent"
    COMMAND = "command"
    REPO = "repo"
    MCP = "mcp"


@dataclass(frozen=True)
class Entity:
    id: str
    type: EntityType
    name: str
    path: str
    last_used_at: str | None
    use_count_30d: int
    vitality_score: int | None
    broken_reason: str | None
    metadata_json: str | None


_MIGRATIONS_DIR = Path(__file__).parent / "migrations"


def _now_iso() -> str:
    return datetime.now(timezone.utc).isoformat()


def _connect(db_path: Path) -> sqlite3.Connection:
    db_path.parent.mkdir(parents=True, exist_ok=True)
    conn = sqlite3.connect(db_path)
    conn.execute("PRAGMA foreign_keys = ON")
    conn.execute("PRAGMA journal_mode = WAL")
    return conn


def init_db(db_path: Path) -> None:
    """idempotent — 이미 존재하면 schema_version만 확인하고 종료."""
    conn = _connect(db_path)
    try:
        cur = conn.execute(
            "SELECT name FROM sqlite_master WHERE type='table' AND name='schema_version'"
        )
        has_meta = cur.fetchone() is not None
        if has_meta:
            current = conn.execute("SELECT MAX(version) FROM schema_version").fetchone()[0]
            if current and current >= 1:
                return

        sql_path = _MIGRATIONS_DIR / "001_initial.sql"
        conn.executescript(sql_path.read_text())
        conn.execute(
            "INSERT INTO schema_version (version, applied_at) VALUES (?, ?)",
            (1, _now_iso()),
        )
        conn.commit()
    finally:
        conn.close()


def upsert_entity(db_path: Path, entity: Entity) -> None:
    conn = _connect(db_path)
    try:
        conn.execute(
            """
            INSERT INTO entity (
                id, type, name, path, last_used_at, use_count_30d,
                vitality_score, broken_reason, metadata_json, updated_at
            ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            ON CONFLICT(id) DO UPDATE SET
                type = excluded.type,
                name = excluded.name,
                path = excluded.path,
                last_used_at = excluded.last_used_at,
                use_count_30d = excluded.use_count_30d,
                vitality_score = excluded.vitality_score,
                broken_reason = excluded.broken_reason,
                metadata_json = excluded.metadata_json,
                updated_at = excluded.updated_at
            """,
            (
                entity.id, entity.type.value, entity.name, entity.path,
                entity.last_used_at, entity.use_count_30d,
                entity.vitality_score, entity.broken_reason, entity.metadata_json,
                _now_iso(),
            ),
        )
        conn.commit()
    finally:
        conn.close()


def find_by_id(db_path: Path, entity_id: str) -> Entity | None:
    conn = _connect(db_path)
    try:
        row = conn.execute(
            "SELECT id, type, name, path, last_used_at, use_count_30d, "
            "vitality_score, broken_reason, metadata_json FROM entity WHERE id = ?",
            (entity_id,),
        ).fetchone()
        if row is None:
            return None
        return _row_to_entity(row)
    finally:
        conn.close()


def search_by_name(db_path: Path, query: str, limit: int = 20) -> list[Entity]:
    """FTS5 기반 이름 검색."""
    conn = _connect(db_path)
    try:
        # FTS5 prefix search
        fts_query = " OR ".join(f"{token}*" for token in query.split() if token)
        if not fts_query:
            return []
        rows = conn.execute(
            """
            SELECT e.id, e.type, e.name, e.path, e.last_used_at, e.use_count_30d,
                   e.vitality_score, e.broken_reason, e.metadata_json
            FROM entity_fts f JOIN entity e ON e.rowid = f.rowid
            WHERE entity_fts MATCH ?
            ORDER BY rank
            LIMIT ?
            """,
            (fts_query, limit),
        ).fetchall()
        return [_row_to_entity(r) for r in rows]
    finally:
        conn.close()


def delete_by_type_and_id_prefix(db_path: Path, type_: EntityType, id_prefix: str) -> int:
    """type 이 일치하고 id가 prefix로 시작하는 entity 삭제. 반환: 삭제된 수."""
    conn = _connect(db_path)
    try:
        cur = conn.execute(
            "DELETE FROM entity WHERE type = ? AND id LIKE ?",
            (type_.value, f"{id_prefix}%"),
        )
        conn.commit()
        return cur.rowcount
    finally:
        conn.close()


def get_max_mtime(db_path: Path, type_: EntityType) -> str | None:
    """해당 type의 entity 중 metadata_json.mtime 최대값 반환 (incremental 비교용)."""
    conn = _connect(db_path)
    try:
        rows = conn.execute(
            "SELECT metadata_json FROM entity WHERE type = ? AND metadata_json IS NOT NULL",
            (type_.value,),
        ).fetchall()
        max_mtime: str | None = None
        for (meta_str,) in rows:
            try:
                meta = json.loads(meta_str)
                mt = meta.get("mtime") if isinstance(meta, dict) else None
                if mt and (max_mtime is None or mt > max_mtime):
                    max_mtime = mt
            except (json.JSONDecodeError, TypeError):
                continue
        return max_mtime
    finally:
        conn.close()


def iter_by_type(db_path: Path, type_: EntityType) -> Iterator[Entity]:
    conn = _connect(db_path)
    try:
        rows = conn.execute(
            "SELECT id, type, name, path, last_used_at, use_count_30d, "
            "vitality_score, broken_reason, metadata_json FROM entity WHERE type = ?",
            (type_.value,),
        )
        for row in rows:
            yield _row_to_entity(row)
    finally:
        conn.close()


def _row_to_entity(row) -> Entity:
    return Entity(
        id=row[0],
        type=EntityType(row[1]),
        name=row[2],
        path=row[3],
        last_used_at=row[4],
        use_count_30d=row[5] or 0,
        vitality_score=row[6],
        broken_reason=row[7],
        metadata_json=row[8],
    )


class Catalog:
    """connection을 with 문으로 관리하는 wrapper. Wave 3 인덱서가 사용."""

    def __init__(self, db_path: Path):
        self.db_path = db_path
        init_db(db_path)

    def __enter__(self) -> "Catalog":
        return self

    def __exit__(self, *args) -> None:
        return None

    def upsert(self, entity: Entity) -> None:
        upsert_entity(self.db_path, entity)

    def find_by_id(self, entity_id: str) -> Entity | None:
        return find_by_id(self.db_path, entity_id)

    def search(self, query: str, limit: int = 20) -> list[Entity]:
        return search_by_name(self.db_path, query, limit)

    def delete_type_prefix(self, type_: EntityType, prefix: str) -> int:
        return delete_by_type_and_id_prefix(self.db_path, type_, prefix)

    def iter_type(self, type_: EntityType) -> Iterator[Entity]:
        return iter_by_type(self.db_path, type_)
