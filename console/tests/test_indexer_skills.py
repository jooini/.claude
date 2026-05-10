from pathlib import Path
import pytest

from console.indexers.skills import scan_skills, index_skills_to_catalog, SkillInfo
from console.catalog import Catalog, EntityType, init_db


@pytest.fixture
def fake_skills_dir(tmp_path: Path) -> Path:
    user_skills = tmp_path / "skills"
    user_skills.mkdir()

    # 정상 skill
    s1 = user_skills / "debug"
    s1.mkdir()
    (s1 / "SKILL.md").write_text(
        "---\n"
        "name: debug\n"
        "description: 에러/버그를 체계적으로 분석하고 수정\n"
        "---\n\n"
        "# Debug Skill\n"
    )

    # 정상 skill 2
    s2 = user_skills / "vitality"
    s2.mkdir()
    (s2 / "SKILL.md").write_text(
        "---\n"
        "name: vitality\n"
        "description: 멀티 프로젝트 사망 감지기\n"
        "---\n\n"
    )

    # 부서진 skill — SKILL.md 없음
    s3 = user_skills / "broken"
    s3.mkdir()
    (s3 / "README.md").write_text("nope")

    # frontmatter 없는 skill
    s4 = user_skills / "no-frontmatter"
    s4.mkdir()
    (s4 / "SKILL.md").write_text("# No frontmatter\n")

    return tmp_path


def test_scan_skills_finds_skill_md(fake_skills_dir: Path):
    skills = list(scan_skills([fake_skills_dir / "skills"]))
    names = sorted(s.name for s in skills)
    # broken 은 SKILL.md 없으니 제외, no-frontmatter는 포함 (frontmatter 없어도 path는 있음)
    assert "debug" in names
    assert "vitality" in names
    assert "no-frontmatter" in names
    assert "broken" not in names


def test_scan_skills_parses_frontmatter(fake_skills_dir: Path):
    skills = {s.name: s for s in scan_skills([fake_skills_dir / "skills"])}
    assert skills["debug"].description == "에러/버그를 체계적으로 분석하고 수정"
    assert skills["vitality"].description == "멀티 프로젝트 사망 감지기"
    assert skills["no-frontmatter"].description is None


def test_scan_skills_multiple_roots(tmp_path: Path):
    user = tmp_path / "user_skills"
    user.mkdir()
    (user / "a").mkdir()
    (user / "a" / "SKILL.md").write_text("---\nname: a\ndescription: x\n---\n")

    plugin = tmp_path / "plugin_skills"
    plugin.mkdir()
    (plugin / "b").mkdir()
    (plugin / "b" / "SKILL.md").write_text("---\nname: b\ndescription: y\n---\n")

    skills = list(scan_skills([user, plugin]))
    assert {s.name for s in skills} == {"a", "b"}


def test_index_skills_to_catalog(tmp_path: Path, fake_skills_dir: Path):
    db = tmp_path / "catalog.db"
    init_db(db)
    count = index_skills_to_catalog([fake_skills_dir / "skills"], db)
    assert count >= 3  # debug, vitality, no-frontmatter
    with Catalog(db) as cat:
        results = list(cat.iter_type(EntityType.SKILL))
        ids = {e.id for e in results}
        assert "skill:debug" in ids
        assert "skill:vitality" in ids


def test_index_skills_marks_no_frontmatter_broken(tmp_path: Path, fake_skills_dir: Path):
    db = tmp_path / "catalog.db"
    init_db(db)
    index_skills_to_catalog([fake_skills_dir / "skills"], db)
    with Catalog(db) as cat:
        nf = cat.find_by_id("skill:no-frontmatter")
        assert nf is not None
        assert nf.broken_reason is not None  # frontmatter 없음
