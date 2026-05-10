from pathlib import Path
import json
import os
import stat
import pytest

from console.indexers.hooks import scan_hooks, index_hooks_to_catalog, HookInfo
from console.catalog import Catalog, EntityType, init_db


@pytest.fixture
def fake_hooks_dir(tmp_path: Path) -> Path:
    """~/.claude/hooks 모방 — 2 event 디렉토리, 각 hook 파일."""
    sess = tmp_path / "SessionStart"
    sess.mkdir()
    (sess / "init.sh").write_text("#!/usr/bin/env bash\necho hi\n")
    (sess / "init.sh").chmod(0o755)
    (sess / "noexec.sh").write_text("#!/usr/bin/env bash\necho noexec\n")
    # noexec.sh는 chmod 안 함

    pre = tmp_path / "PreToolUse"
    pre.mkdir()
    (pre / "check.py").write_text("#!/usr/bin/env python3\nprint('check')\n")
    (pre / "check.py").chmod(0o755)
    return tmp_path


def test_scan_hooks_finds_all_scripts(fake_hooks_dir: Path):
    hooks = list(scan_hooks(fake_hooks_dir))
    names = sorted((h.event, h.name) for h in hooks)
    assert names == [
        ("PreToolUse", "check.py"),
        ("SessionStart", "init.sh"),
        ("SessionStart", "noexec.sh"),
    ]


def test_scan_hooks_detects_executable(fake_hooks_dir: Path):
    hooks = {(h.event, h.name): h for h in scan_hooks(fake_hooks_dir)}
    assert hooks[("SessionStart", "init.sh")].executable is True
    assert hooks[("SessionStart", "noexec.sh")].executable is False
    assert hooks[("PreToolUse", "check.py")].executable is True


def test_scan_hooks_collects_size_and_mtime(fake_hooks_dir: Path):
    hook = next(h for h in scan_hooks(fake_hooks_dir) if h.name == "init.sh")
    assert hook.size_bytes > 0
    assert hook.mtime is not None


def test_scan_hooks_skips_non_script(tmp_path: Path):
    """README.md 같은 비스크립트 무시."""
    d = tmp_path / "SessionStart"
    d.mkdir()
    (d / "README.md").write_text("# notes")
    (d / "init.sh").write_text("#!/bin/bash")
    hooks = list(scan_hooks(tmp_path))
    assert all(h.name.endswith((".sh", ".py", ".js", ".ts")) for h in hooks)
    assert any(h.name == "init.sh" for h in hooks)


def test_index_hooks_to_catalog_inserts(tmp_path: Path, fake_hooks_dir: Path):
    db = tmp_path / "catalog.db"
    init_db(db)
    count = index_hooks_to_catalog(fake_hooks_dir, db)
    assert count == 3
    with Catalog(db) as cat:
        results = list(cat.iter_type(EntityType.HOOK))
    assert len(results) == 3
    by_id = {e.id: e for e in results}
    assert "hook:SessionStart/init.sh" in by_id
    assert by_id["hook:SessionStart/noexec.sh"].broken_reason is not None  # 실행 권한 없음
    assert by_id["hook:SessionStart/init.sh"].broken_reason is None


def test_index_hooks_replaces_stale(tmp_path: Path, fake_hooks_dir: Path):
    """재인덱싱 시 stale entity 정리 후 재삽입."""
    db = tmp_path / "catalog.db"
    init_db(db)

    # 1차 인덱싱
    index_hooks_to_catalog(fake_hooks_dir, db)

    # 한 hook 삭제
    (fake_hooks_dir / "SessionStart" / "init.sh").unlink()

    # 2차 인덱싱
    count = index_hooks_to_catalog(fake_hooks_dir, db)
    assert count == 2  # init.sh 제외 2개

    with Catalog(db) as cat:
        assert cat.find_by_id("hook:SessionStart/init.sh") is None  # stale 삭제됨
        assert cat.find_by_id("hook:PreToolUse/check.py") is not None


def test_scan_hooks_finds_flat_scripts(tmp_path: Path):
    """flat ~/.claude/hooks/*.sh 도 인덱싱.

    실제 settings.json 의 command 는 ``…/hooks/<script>`` 형태이므로
    'hooks/' 토큰이 path 안에 들어 있어야 매핑이 동작한다.
    """
    hooks_dir = tmp_path / "hooks"
    hooks_dir.mkdir()
    (hooks_dir / "post-hook.sh").write_text("#!/bin/bash")
    (hooks_dir / "post-hook.sh").chmod(0o755)
    settings = tmp_path / "settings.json"
    settings.write_text(json.dumps({
        "hooks": {
            "PostToolUse": [{"hooks": [{"command": f"{hooks_dir}/post-hook.sh"}]}]
        }
    }))
    hooks = scan_hooks(hooks_dir, settings)
    by_id = {h.relative_id: h for h in hooks}
    assert "post-hook.sh" in by_id
    assert by_id["post-hook.sh"].registered is True
    assert by_id["post-hook.sh"].event == "PostToolUse"


def test_scan_hooks_marks_orphan(tmp_path: Path):
    """settings 미등록 = orphan."""
    hooks_dir = tmp_path / "hooks"
    hooks_dir.mkdir()
    (hooks_dir / "orphan.sh").write_text("#!/bin/bash")
    (hooks_dir / "orphan.sh").chmod(0o755)
    settings = tmp_path / "settings.json"
    settings.write_text('{"hooks": {}}')
    hooks = scan_hooks(hooks_dir, settings)
    by_id = {h.relative_id: h for h in hooks}
    assert by_id["orphan.sh"].registered is False
    assert by_id["orphan.sh"].event is None


def test_index_hooks_orphan_marked_broken(tmp_path: Path):
    hooks_dir = tmp_path / "hooks"
    hooks_dir.mkdir()
    (hooks_dir / "orphan.sh").write_text("#!/bin/bash")
    (hooks_dir / "orphan.sh").chmod(0o755)
    settings = tmp_path / "settings.json"
    settings.write_text('{"hooks": {}}')
    db = tmp_path / "catalog.db"
    init_db(db)
    index_hooks_to_catalog(hooks_dir, db, settings)
    with Catalog(db) as cat:
        e = cat.find_by_id("hook:orphan.sh")
        assert e is not None
        assert "orphan" in e.broken_reason


def test_scan_hooks_supports_wrapper_command(tmp_path: Path):
    """`/bin/zsh wrapper.sh /path/to/hooks/target.sh` 같은 다중 토큰 명령에서도
    실제 타깃 스크립트를 정확히 매핑한다 (real settings.json 패턴)."""
    hooks_dir = tmp_path / "hooks"
    hooks_dir.mkdir()
    lib = hooks_dir / "_lib"
    lib.mkdir()
    (lib / "hook-timing.sh").write_text("#!/bin/bash")
    (lib / "hook-timing.sh").chmod(0o755)
    (hooks_dir / "real-target.sh").write_text("#!/bin/bash")
    (hooks_dir / "real-target.sh").chmod(0o755)
    settings = tmp_path / "settings.json"
    settings.write_text(json.dumps({
        "hooks": {
            "PostToolUse": [{"hooks": [{
                "command": f"/bin/zsh {hooks_dir}/_lib/hook-timing.sh {hooks_dir}/real-target.sh"
            }]}]
        }
    }))
    hooks = scan_hooks(hooks_dir, settings)
    by_id = {h.relative_id: h for h in hooks}
    # 마지막 토큰이 우선이라기보다, 둘 다 인식되어 둘 다 registered=True
    assert by_id["real-target.sh"].registered is True
    assert by_id["_lib/hook-timing.sh"].registered is True
