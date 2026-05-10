"""~/Workspace repos 스캔 → vitality + catalog 인덱싱."""
from __future__ import annotations

from pathlib import Path
import json

from console.catalog import Catalog, Entity, EntityType, init_db
from console.adapters.git import scan_repos
from console.adapters.backlog import has_active_backlog, has_readme
from console.vitality import score


def index_repos_to_catalog(workspace_root: Path, db_path: Path, max_depth: int = 2) -> int:
    init_db(db_path)
    repos = list(scan_repos(workspace_root, max_depth=max_depth))

    with Catalog(db_path) as cat:
        cat.delete_type_prefix(EntityType.REPO, "repo:")
        for r in repos:
            try:
                rel = r.path.relative_to(workspace_root)
                rel_str = str(rel)
            except ValueError:
                rel_str = r.path.name

            s = score(
                r,
                has_backlog=has_active_backlog(r.path),
                has_readme_=has_readme(r.path),
            )

            cat.upsert(Entity(
                id=f"repo:{rel_str}",
                type=EntityType.REPO,
                name=r.path.name,
                path=str(r.path),
                last_used_at=r.last_commit_at.isoformat() if r.last_commit_at else None,
                use_count_30d=0,  # TODO: git log --since="30 days ago" | wc -l
                vitality_score=s.value,
                broken_reason=None,
                metadata_json=json.dumps({
                    "label": s.label,
                    "dirty_count": r.dirty_count,
                    "reason": s.reason,
                    "rel_path": rel_str,
                }),
            ))
    return len(repos)
