-- Workspace Console catalog.db 초기 스키마
-- 모든 부품 (hook/skill/agent/command/repo/mcp) 단일 인덱스

CREATE TABLE IF NOT EXISTS schema_version (
  version INTEGER PRIMARY KEY,
  applied_at TEXT NOT NULL
);

CREATE TABLE IF NOT EXISTS entity (
  id              TEXT PRIMARY KEY,
  type            TEXT NOT NULL,
  name            TEXT NOT NULL,
  path            TEXT NOT NULL,
  last_used_at    TEXT,
  use_count_30d   INTEGER DEFAULT 0,
  vitality_score  INTEGER,
  broken_reason   TEXT,
  metadata_json   TEXT,
  updated_at      TEXT NOT NULL
);

CREATE INDEX IF NOT EXISTS idx_entity_type      ON entity(type);
CREATE INDEX IF NOT EXISTS idx_entity_vitality  ON entity(vitality_score);
CREATE INDEX IF NOT EXISTS idx_entity_name      ON entity(name);

-- FTS5 (full-text search) 가상 테이블
CREATE VIRTUAL TABLE IF NOT EXISTS entity_fts USING fts5(
  name, path, content=entity, content_rowid=rowid, tokenize='unicode61'
);

-- entity 변경 시 FTS 동기화 trigger
CREATE TRIGGER IF NOT EXISTS entity_ai AFTER INSERT ON entity BEGIN
  INSERT INTO entity_fts(rowid, name, path) VALUES (new.rowid, new.name, new.path);
END;

CREATE TRIGGER IF NOT EXISTS entity_ad AFTER DELETE ON entity BEGIN
  INSERT INTO entity_fts(entity_fts, rowid, name, path) VALUES('delete', old.rowid, old.name, old.path);
END;

CREATE TRIGGER IF NOT EXISTS entity_au AFTER UPDATE ON entity BEGIN
  INSERT INTO entity_fts(entity_fts, rowid, name, path) VALUES('delete', old.rowid, old.name, old.path);
  INSERT INTO entity_fts(rowid, name, path) VALUES (new.rowid, new.name, new.path);
END;
