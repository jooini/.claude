"""frontmatter 파싱 헬퍼."""
from __future__ import annotations

from pathlib import Path
import re


_FRONTMATTER_RE = re.compile(r"^---\n(.*?)\n---", re.DOTALL)
_NAME_RE = re.compile(r"^name:\s*(.+?)\s*$", re.MULTILINE)
_DESC_RE = re.compile(r"^description:\s*(.+?)\s*$", re.MULTILINE)


def parse_md_frontmatter(md_path: Path) -> tuple[str | None, str | None, bool]:
    """returns (name, description, has_frontmatter)."""
    try:
        text = md_path.read_text(errors="ignore")
    except OSError:
        return None, None, False
    m = _FRONTMATTER_RE.match(text)
    if not m:
        return None, None, False
    fm = m.group(1)
    name_m = _NAME_RE.search(fm)
    desc_m = _DESC_RE.search(fm)
    return (
        name_m.group(1).strip() if name_m else None,
        desc_m.group(1).strip() if desc_m else None,
        True,
    )
