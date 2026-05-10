"""hooks 디렉토리 스캔 → catalog.db 인덱싱."""
from __future__ import annotations

from dataclasses import dataclass
from datetime import datetime, timezone
from pathlib import Path
import json
import stat

from console.catalog import Catalog, Entity, EntityType, init_db


_SCRIPT_EXTS = (".sh", ".py", ".js", ".ts")


@dataclass(frozen=True)
class HookInfo:
    event: str
    name: str
    path: Path
    executable: bool
    size_bytes: int
    mtime: datetime


def scan_hooks(hooks_root: Path) -> list[HookInfo]:
    """hooks_root 하위 <event>/<script> 패턴 발견."""
    if not hooks_root.is_dir():
        return []
    hooks: list[HookInfo] = []
    for event_dir in sorted(hooks_root.iterdir()):
        if not event_dir.is_dir():
            continue
        for script in sorted(event_dir.iterdir()):
            if not script.is_file():
                continue
            if not script.name.endswith(_SCRIPT_EXTS):
                continue
            try:
                st = script.stat()
            except OSError:
                continue
            hooks.append(HookInfo(
                event=event_dir.name,
                name=script.name,
                path=script,
                executable=bool(st.st_mode & stat.S_IXUSR),
                size_bytes=st.st_size,
                mtime=datetime.fromtimestamp(st.st_mtime, tz=timezone.utc),
            ))
    return hooks


def index_hooks_to_catalog(hooks_root: Path, db_path: Path) -> int:
    """hooks 스캔 → 기존 hook entity 정리 → 새로 upsert. 반환: 인덱싱된 수."""
    init_db(db_path)
    hooks = scan_hooks(hooks_root)

    with Catalog(db_path) as cat:
        cat.delete_type_prefix(EntityType.HOOK, "hook:")
        for h in hooks:
            broken = None if h.executable else "실행 권한 없음 (chmod +x 필요)"
            cat.upsert(Entity(
                id=f"hook:{h.event}/{h.name}",
                type=EntityType.HOOK,
                name=h.name,
                path=str(h.path),
                last_used_at=None,
                use_count_30d=0,
                vitality_score=None,
                broken_reason=broken,
                metadata_json=json.dumps({
                    "event": h.event,
                    "size_bytes": h.size_bytes,
                    "mtime": h.mtime.isoformat(),
                }),
            ))
    return len(hooks)
