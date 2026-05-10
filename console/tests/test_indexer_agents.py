from pathlib import Path
import pytest

from console.indexers.agents import scan_agents, index_agents_to_catalog, AgentInfo
from console.catalog import Catalog, EntityType, init_db


@pytest.fixture
def fake_agents_dir(tmp_path: Path) -> Path:
    d = tmp_path / "agents"
    d.mkdir()
    (d / "backend-developer.md").write_text(
        "---\n"
        "name: backend-developer\n"
        "description: 백엔드 코드 작성\n"
        "tools: All tools\n"
        "---\n\n# Backend Developer\n"
    )
    (d / "code-reviewer.md").write_text(
        "---\n"
        "name: code-reviewer\n"
        "description: 코드 리뷰\n"
        "---\n"
    )
    (d / "no-frontmatter.md").write_text("# Plain MD\n")
    (d / "README.md").write_text("# README — 무시")  # README는 agent 아님
    return d


def test_scan_agents_finds_md_files(fake_agents_dir: Path):
    agents = list(scan_agents(fake_agents_dir))
    names = sorted(a.name for a in agents)
    # README는 보통 제외 가능 — 단순화: 모든 .md 포함하되 frontmatter 없으면 broken
    # 또는 README.md 명시 제외 — 여기서는 명시 제외
    assert "backend-developer" in names
    assert "code-reviewer" in names
    assert "no-frontmatter" in names
    assert "README" not in names  # 명시 제외


def test_scan_agents_parses_description(fake_agents_dir: Path):
    by = {a.name: a for a in scan_agents(fake_agents_dir)}
    assert by["backend-developer"].description == "백엔드 코드 작성"
    assert by["code-reviewer"].description == "코드 리뷰"
    assert by["no-frontmatter"].description is None


def test_index_agents_to_catalog(tmp_path: Path, fake_agents_dir: Path):
    db = tmp_path / "catalog.db"
    init_db(db)
    count = index_agents_to_catalog(fake_agents_dir, db)
    assert count >= 3
    with Catalog(db) as cat:
        ids = {e.id for e in cat.iter_type(EntityType.AGENT)}
        assert "agent:backend-developer" in ids
        nf = cat.find_by_id("agent:no-frontmatter")
        assert nf is not None
        assert nf.broken_reason is not None
