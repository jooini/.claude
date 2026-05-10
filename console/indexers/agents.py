"""agents .md 파일 → catalog.db."""
from __future__ import annotations

from dataclasses import dataclass
from pathlib import Path
import json

from console.catalog import Catalog, Entity, EntityType, init_db
from console.indexers._frontmatter import parse_md_frontmatter


_EXCLUDED_NAMES = {"README", "readme"}


@dataclass(frozen=True)
class AgentInfo:
    name: str
    path: Path
    description: str | None
    has_frontmatter: bool


def scan_agents(agents_dir: Path) -> list[AgentInfo]:
    if not agents_dir.is_dir():
        return []
    found: list[AgentInfo] = []
    for md in sorted(agents_dir.glob("*.md")):
        stem = md.stem
        if stem in _EXCLUDED_NAMES:
            continue
        name, desc, has_fm = parse_md_frontmatter(md)
        found.append(AgentInfo(
            name=name or stem,
            path=md,
            description=desc,
            has_frontmatter=has_fm,
        ))
    return found


def index_agents_to_catalog(agents_dir: Path, db_path: Path) -> int:
    init_db(db_path)
    agents = scan_agents(agents_dir)
    with Catalog(db_path) as cat:
        cat.delete_type_prefix(EntityType.AGENT, "agent:")
        for a in agents:
            broken = None if a.has_frontmatter else "frontmatter 없음"
            cat.upsert(Entity(
                id=f"agent:{a.name}",
                type=EntityType.AGENT,
                name=a.name,
                path=str(a.path),
                last_used_at=None,
                use_count_30d=0,
                vitality_score=None,
                broken_reason=broken,
                metadata_json=json.dumps({"description": a.description}) if a.description else None,
            ))
    return len(agents)
