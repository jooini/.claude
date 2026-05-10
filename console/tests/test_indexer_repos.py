from pathlib import Path
import subprocess
import pytest

from console.indexers.repos import index_repos_to_catalog
from console.catalog import Catalog, EntityType, init_db


@pytest.fixture
def fake_workspace(tmp_path: Path) -> Path:
    """2개 git repo: 하나는 active, 하나는 dirty backlog."""
    a = tmp_path / "alive"
    a.mkdir()
    subprocess.run(["git", "init", "-q"], cwd=a, check=True)
    subprocess.run(["git", "config", "user.email", "t@t"], cwd=a, check=True)
    subprocess.run(["git", "config", "user.name", "t"], cwd=a, check=True)
    (a / "README.md").write_text("# alive")
    (a / "f.txt").write_text("x")
    subprocess.run(["git", "add", "."], cwd=a, check=True)
    subprocess.run(["git", "commit", "-q", "-m", "init"], cwd=a, check=True)

    b = tmp_path / "with-backlog"
    b.mkdir()
    subprocess.run(["git", "init", "-q"], cwd=b, check=True)
    subprocess.run(["git", "config", "user.email", "t@t"], cwd=b, check=True)
    subprocess.run(["git", "config", "user.name", "t"], cwd=b, check=True)
    (b / "README.md").write_text("# b")
    active = b / "docs" / "active"
    active.mkdir(parents=True)
    (active / "task.md").write_text("- [ ] todo\n")
    subprocess.run(["git", "add", "."], cwd=b, check=True)
    subprocess.run(["git", "commit", "-q", "-m", "init"], cwd=b, check=True)

    return tmp_path


def test_index_repos_inserts(tmp_path: Path, fake_workspace: Path):
    db = tmp_path / "catalog.db"
    init_db(db)
    count = index_repos_to_catalog(fake_workspace, db)
    assert count == 2
    with Catalog(db) as cat:
        ids = {e.id for e in cat.iter_type(EntityType.REPO)}
        assert "repo:alive" in ids
        assert "repo:with-backlog" in ids


def test_index_repos_includes_vitality_score(tmp_path: Path, fake_workspace: Path):
    db = tmp_path / "catalog.db"
    init_db(db)
    index_repos_to_catalog(fake_workspace, db)
    with Catalog(db) as cat:
        alive = cat.find_by_id("repo:alive")
        backlog = cat.find_by_id("repo:with-backlog")
        assert alive.vitality_score is not None
        assert backlog.vitality_score is not None
        # backlog 보유 repo는 +10 보너스
        assert backlog.vitality_score >= alive.vitality_score


def test_index_repos_replaces_stale(tmp_path: Path, fake_workspace: Path):
    db = tmp_path / "catalog.db"
    init_db(db)
    index_repos_to_catalog(fake_workspace, db)
    # alive 삭제 후 재인덱싱
    import shutil
    shutil.rmtree(fake_workspace / "alive")
    count = index_repos_to_catalog(fake_workspace, db)
    assert count == 1
    with Catalog(db) as cat:
        assert cat.find_by_id("repo:alive") is None
        assert cat.find_by_id("repo:with-backlog") is not None
