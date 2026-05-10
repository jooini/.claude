"""hooks 디렉토리 스캔 + settings.json 매핑 → catalog.db 인덱싱."""
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
    event: str | None       # None = settings 미등록 (orphan)
    name: str               # 파일명
    relative_id: str        # event/name 또는 (root)/name
    path: Path
    executable: bool
    size_bytes: int
    mtime: datetime
    registered: bool        # settings.json 에 등록되어 있는가


def _load_settings_hook_map(settings_path: Path) -> dict[str, list[str]]:
    """settings.json 파싱 → {script_path: [event1, event2]}.

    settings.json 의 hooks.<event>[].hooks[].command 안에서 'hooks/' 토큰을 찾아
    이후 경로를 키로 사용한다. flat 스크립트(`foo.sh`)와 중첩(`Event/foo.sh`) 모두 지원.
    """
    if not settings_path.is_file():
        return {}
    try:
        data = json.loads(settings_path.read_text())
    except (json.JSONDecodeError, OSError):
        return {}
    mapping: dict[str, list[str]] = {}
    for event, configs in data.get("hooks", {}).items():
        if not isinstance(configs, list):
            continue
        for cfg in configs:
            for h in cfg.get("hooks", []):
                cmd = h.get("command", "")
                # cmd 안의 hooks/ 경로 추출 (예: "$CLAUDE_PROJECT_DIR/hooks/foo.sh ...")
                for token in cmd.split():
                    if "hooks/" in token:
                        idx = token.rfind("hooks/")
                        rel = token[idx + len("hooks/"):]
                        mapping.setdefault(rel, []).append(event)
    return mapping


def scan_hooks(hooks_root: Path, settings_path: Path | None = None) -> list[HookInfo]:
    """hooks_root 안의 모든 스크립트 발견.

    1) flat 스크립트: ``~/.claude/hooks/*.sh``
    2) 중첩 스크립트: ``~/.claude/hooks/<event>/<script>``

    settings_path 가 주어지면 등록 여부 + event 매핑에 사용.
    """
    if not hooks_root.is_dir():
        return []
    settings_map = _load_settings_hook_map(settings_path) if settings_path else {}

    hooks: list[HookInfo] = []

    # 1) flat 스크립트 (~/.claude/hooks/*.sh)
    for script in sorted(hooks_root.iterdir()):
        if not script.is_file() or not script.name.endswith(_SCRIPT_EXTS):
            continue
        try:
            st = script.stat()
        except OSError:
            continue
        events = settings_map.get(script.name, [])
        hooks.append(HookInfo(
            event=events[0] if events else None,
            name=script.name,
            relative_id=script.name,
            path=script,
            executable=bool(st.st_mode & stat.S_IXUSR),
            size_bytes=st.st_size,
            mtime=datetime.fromtimestamp(st.st_mtime, tz=timezone.utc),
            registered=bool(events),
        ))

    # 2) <event>/<script> 패턴 (~/.claude/hooks/SessionStart/foo.sh)
    for event_dir in sorted(hooks_root.iterdir()):
        if not event_dir.is_dir():
            continue
        for script in sorted(event_dir.iterdir()):
            if not script.is_file() or not script.name.endswith(_SCRIPT_EXTS):
                continue
            try:
                st = script.stat()
            except OSError:
                continue
            rel = f"{event_dir.name}/{script.name}"
            events = settings_map.get(rel, [event_dir.name])
            hooks.append(HookInfo(
                event=events[0],
                name=script.name,
                relative_id=rel,
                path=script,
                executable=bool(st.st_mode & stat.S_IXUSR),
                size_bytes=st.st_size,
                mtime=datetime.fromtimestamp(st.st_mtime, tz=timezone.utc),
                registered=bool(settings_map.get(rel)),
            ))
    return hooks


def index_hooks_to_catalog(
    hooks_root: Path,
    db_path: Path,
    settings_path: Path | None = None,
) -> int:
    """hooks 스캔 → 기존 hook entity 정리 → 새로 upsert. 반환: 인덱싱된 수."""
    init_db(db_path)
    hooks = scan_hooks(hooks_root, settings_path)

    with Catalog(db_path) as cat:
        cat.delete_type_prefix(EntityType.HOOK, "hook:")
        for h in hooks:
            broken_reasons: list[str] = []
            if not h.executable:
                broken_reasons.append("실행 권한 없음 (chmod +x 필요)")
            if not h.registered and h.event is None:
                broken_reasons.append("settings.json 미등록 (orphan)")
            broken = "; ".join(broken_reasons) if broken_reasons else None

            cat.upsert(Entity(
                id=f"hook:{h.relative_id}",
                type=EntityType.HOOK,
                name=h.name,
                path=str(h.path),
                last_used_at=None,
                use_count_30d=0,
                vitality_score=None,
                broken_reason=broken,
                metadata_json=json.dumps({
                    "event": h.event,
                    "registered": h.registered,
                    "size_bytes": h.size_bytes,
                    "mtime": h.mtime.isoformat(),
                }),
            ))
    return len(hooks)
