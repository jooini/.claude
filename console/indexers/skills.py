"""skills 디렉토리 스캔 → catalog.db 인덱싱."""
from __future__ import annotations

from dataclasses import dataclass
from pathlib import Path
import json
import re

from console.catalog import Catalog, Entity, EntityType, init_db


@dataclass(frozen=True)
class SkillInfo:
    name: str
    path: Path
    description: str | None
    has_frontmatter: bool


_FRONTMATTER_RE = re.compile(r"^---\n(.*?)\n---", re.DOTALL)
_NAME_RE = re.compile(r"^name:\s*(.+?)\s*$", re.MULTILINE)
_DESC_RE = re.compile(r"^description:\s*(.+?)\s*$", re.MULTILINE)


def _strip_quotes(value: str) -> str:
    """frontmatter 값 양쪽 따옴표 제거."""
    if len(value) >= 2 and value[0] == value[-1] and value[0] in ('"', "'"):
        return value[1:-1]
    return value


def parse_skill_frontmatter(skill_md: Path) -> tuple[str | None, str | None, bool]:
    """returns (name, description, has_frontmatter)."""
    try:
        text = skill_md.read_text(errors="ignore")
    except OSError:
        return None, None, False
    m = _FRONTMATTER_RE.match(text)
    if not m:
        return None, None, False
    fm = m.group(1)
    name_m = _NAME_RE.search(fm)
    desc_m = _DESC_RE.search(fm)
    name = _strip_quotes(name_m.group(1).strip()) if name_m else None
    desc = _strip_quotes(desc_m.group(1).strip()) if desc_m else None
    return name, desc, True


def scan_skills(skills_roots: list[Path]) -> list[SkillInfo]:
    """skills_roots 각각 하위 <skill_name>/SKILL.md 발견."""
    found: list[SkillInfo] = []
    for root in skills_roots:
        if not root.is_dir():
            continue
        for skill_dir in sorted(root.iterdir()):
            if not skill_dir.is_dir():
                continue
            skill_md = skill_dir / "SKILL.md"
            if not skill_md.is_file():
                continue
            name, desc, has_fm = parse_skill_frontmatter(skill_md)
            found.append(SkillInfo(
                name=name or skill_dir.name,
                path=skill_md,
                description=desc,
                has_frontmatter=has_fm,
            ))
    return found


def index_skills_to_catalog(skills_roots: list[Path], db_path: Path) -> int:
    """skills 스캔 → 기존 skill entity 정리 → 새로 upsert. 반환: 인덱싱된 수."""
    init_db(db_path)
    skills = scan_skills(skills_roots)

    with Catalog(db_path) as cat:
        cat.delete_type_prefix(EntityType.SKILL, "skill:")
        for s in skills:
            broken = None if s.has_frontmatter else "frontmatter 없음 (name/description 누락)"
            cat.upsert(Entity(
                id=f"skill:{s.name}",
                type=EntityType.SKILL,
                name=s.name,
                path=str(s.path),
                last_used_at=None,
                use_count_30d=0,
                vitality_score=None,
                broken_reason=broken,
                metadata_json=json.dumps({"description": s.description}) if s.description else None,
            ))
    return len(skills)
