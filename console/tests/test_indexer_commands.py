from pathlib import Path
import pytest

from console.indexers.commands import scan_commands, index_commands_to_catalog
from console.catalog import Catalog, EntityType, init_db


@pytest.fixture
def fake_commands_dir(tmp_path: Path) -> Path:
    d = tmp_path / "commands"
    d.mkdir()
    (d / "morning.md").write_text(
        "---\ndescription: 아침 루틴\n---\n# /morning\n"
    )
    (d / "deploy-status.md").write_text(
        "---\ndescription: 배포 상태\n---\n"
    )
    (d / "no-frontmatter.md").write_text("# /no-fm")
    return d


def test_scan_commands_finds_all_md(fake_commands_dir: Path):
    cmds = list(scan_commands(fake_commands_dir))
    names = sorted(c.name for c in cmds)
    assert names == ["deploy-status", "morning", "no-frontmatter"]


def test_scan_commands_description(fake_commands_dir: Path):
    by = {c.name: c for c in scan_commands(fake_commands_dir)}
    assert by["morning"].description == "아침 루틴"
    assert by["deploy-status"].description == "배포 상태"
    assert by["no-frontmatter"].description is None


def test_index_commands_to_catalog(tmp_path: Path, fake_commands_dir: Path):
    db = tmp_path / "catalog.db"
    init_db(db)
    count = index_commands_to_catalog(fake_commands_dir, db)
    assert count == 3
    with Catalog(db) as cat:
        cmd = cat.find_by_id("command:morning")
        assert cmd is not None
        assert cmd.path.endswith("morning.md")
