from datetime import datetime, timezone
from pathlib import Path
import sqlite3
import pytest

from console.catalog import (
    Catalog, Entity, EntityType,
    init_db, upsert_entity, find_by_id, search_by_name,
    delete_by_type_and_id_prefix, get_max_mtime,
)


@pytest.fixture
def db_path(tmp_path: Path) -> Path:
    return tmp_path / "catalog.db"


def test_init_db_creates_schema(db_path: Path):
    init_db(db_path)
    conn = sqlite3.connect(db_path)
    tables = {r[0] for r in conn.execute("SELECT name FROM sqlite_master WHERE type='table'")}
    assert "entity" in tables
    assert "entity_fts" in tables
    assert "schema_version" in tables
    version = conn.execute("SELECT MAX(version) FROM schema_version").fetchone()[0]
    assert version == 1


def test_init_db_idempotent(db_path: Path):
    init_db(db_path)
    init_db(db_path)  # 두 번 호출해도 에러 없음
    conn = sqlite3.connect(db_path)
    versions = conn.execute("SELECT COUNT(*) FROM schema_version").fetchone()[0]
    assert versions == 1  # 중복 insert X


def test_upsert_entity_insert(db_path: Path):
    init_db(db_path)
    e = Entity(
        id="hook:SessionStart/wsq-daily-sweep",
        type=EntityType.HOOK,
        name="wsq-daily-sweep",
        path="/Users/leonard/.claude/hooks/SessionStart/wsq-daily-sweep.sh",
        last_used_at=None,
        use_count_30d=0,
        vitality_score=None,
        broken_reason=None,
        metadata_json='{"event": "SessionStart"}',
    )
    upsert_entity(db_path, e)

    found = find_by_id(db_path, e.id)
    assert found is not None
    assert found.name == "wsq-daily-sweep"
    assert found.type == EntityType.HOOK


def test_upsert_entity_update(db_path: Path):
    init_db(db_path)
    e = Entity(
        id="skill:debug",
        type=EntityType.SKILL,
        name="debug",
        path="/Users/leonard/.claude/skills/debug/SKILL.md",
        last_used_at=None, use_count_30d=0,
        vitality_score=None, broken_reason=None, metadata_json=None,
    )
    upsert_entity(db_path, e)

    e2 = Entity(
        id="skill:debug",
        type=EntityType.SKILL,
        name="debug",
        path="/Users/leonard/.claude/skills/debug/SKILL.md",
        last_used_at="2026-05-10T11:00:00+00:00",
        use_count_30d=12,
        vitality_score=None, broken_reason=None, metadata_json=None,
    )
    upsert_entity(db_path, e2)

    found = find_by_id(db_path, "skill:debug")
    assert found.use_count_30d == 12
    assert found.last_used_at == "2026-05-10T11:00:00+00:00"


def test_search_by_name_fuzzy(db_path: Path):
    init_db(db_path)
    upsert_entity(db_path, Entity("skill:debug", EntityType.SKILL, "debug", "/p/1", None, 0, None, None, None))
    upsert_entity(db_path, Entity("agent:debug-master", EntityType.AGENT, "debug-master", "/p/2", None, 0, None, None, None))
    upsert_entity(db_path, Entity("command:morning", EntityType.COMMAND, "morning", "/p/3", None, 0, None, None, None))

    results = search_by_name(db_path, "debug")
    names = sorted(e.name for e in results)
    assert "debug" in names
    assert "debug-master" in names
    assert "morning" not in names


def test_delete_by_type_and_id_prefix(db_path: Path):
    """re-index 시 stale entity 정리 (예: hook:* 모두 삭제 후 재삽입)"""
    init_db(db_path)
    upsert_entity(db_path, Entity("hook:a", EntityType.HOOK, "a", "/p/a", None, 0, None, None, None))
    upsert_entity(db_path, Entity("hook:b", EntityType.HOOK, "b", "/p/b", None, 0, None, None, None))
    upsert_entity(db_path, Entity("skill:c", EntityType.SKILL, "c", "/p/c", None, 0, None, None, None))

    deleted = delete_by_type_and_id_prefix(db_path, EntityType.HOOK, "hook:")
    assert deleted == 2
    assert find_by_id(db_path, "hook:a") is None
    assert find_by_id(db_path, "skill:c") is not None


def test_entity_type_enum_values():
    """EntityType은 6종"""
    assert {t.value for t in EntityType} == {"hook", "skill", "agent", "command", "repo", "mcp"}


def test_get_max_mtime_returns_max(db_path: Path):
    """metadata_json.mtime 중 최대값 반환. 없으면 None."""
    init_db(db_path)
    upsert_entity(db_path, Entity(
        "hook:a", EntityType.HOOK, "a", "/p/a", None, 0, None, None,
        '{"mtime": "2026-05-09T10:00:00+00:00"}',
    ))
    upsert_entity(db_path, Entity(
        "hook:b", EntityType.HOOK, "b", "/p/b", None, 0, None, None,
        '{"mtime": "2026-05-10T10:00:00+00:00"}',
    ))
    upsert_entity(db_path, Entity(
        "skill:c", EntityType.SKILL, "c", "/p/c", None, 0, None, None, None,
    ))
    assert get_max_mtime(db_path, EntityType.HOOK) == "2026-05-10T10:00:00+00:00"
    assert get_max_mtime(db_path, EntityType.SKILL) is None


def test_get_max_mtime_ignores_invalid_json(db_path: Path):
    """metadata_json이 잘못된 JSON이거나 mtime 없으면 무시."""
    init_db(db_path)
    upsert_entity(db_path, Entity(
        "hook:bad", EntityType.HOOK, "bad", "/p/bad", None, 0, None, None,
        'not-json',
    ))
    upsert_entity(db_path, Entity(
        "hook:nomt", EntityType.HOOK, "nomt", "/p/nomt", None, 0, None, None,
        '{"event": "SessionStart"}',
    ))
    upsert_entity(db_path, Entity(
        "hook:ok", EntityType.HOOK, "ok", "/p/ok", None, 0, None, None,
        '{"mtime": "2026-05-08T01:00:00+00:00"}',
    ))
    assert get_max_mtime(db_path, EntityType.HOOK) == "2026-05-08T01:00:00+00:00"


def test_catalog_class_context_manager(db_path: Path):
    """Catalog 클래스로 connection 관리 (with 문 지원)"""
    init_db(db_path)
    with Catalog(db_path) as c:
        c.upsert(Entity("hook:x", EntityType.HOOK, "x", "/p/x", None, 0, None, None, None))
        result = c.find_by_id("hook:x")
        assert result is not None
