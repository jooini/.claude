"""commands .md 파일 → catalog.db."""
from __future__ import annotations

from dataclasses import dataclass
from pathlib import Path
import json

from console.catalog import Catalog, Entity, EntityType, init_db
from console.indexers._frontmatter import parse_md_frontmatter


@dataclass(frozen=True)
class CommandInfo:
    name: str
    path: Path
    description: str | None


def scan_commands(commands_dir: Path) -> list[CommandInfo]:
    if not commands_dir.is_dir():
        return []
    found: list[CommandInfo] = []
    for md in sorted(commands_dir.glob("*.md")):
        _, desc, _ = parse_md_frontmatter(md)
        found.append(CommandInfo(
            name=md.stem,
            path=md,
            description=desc,
        ))
    return found


def index_commands_to_catalog(commands_dir: Path, db_path: Path) -> int:
    init_db(db_path)
    cmds = scan_commands(commands_dir)
    with Catalog(db_path) as cat:
        cat.delete_type_prefix(EntityType.COMMAND, "command:")
        for c in cmds:
            cat.upsert(Entity(
                id=f"command:{c.name}",
                type=EntityType.COMMAND,
                name=c.name,
                path=str(c.path),
                last_used_at=None,
                use_count_30d=0,
                vitality_score=None,
                broken_reason=None,
                metadata_json=json.dumps({"description": c.description}) if c.description else None,
            ))
    return len(cmds)
