"""repo의 active 백로그 + README 존재 신호."""
from __future__ import annotations

from pathlib import Path


_README_NAMES = ("README.md", "README.rst", "README", "readme.md")


def has_active_backlog(repo: Path) -> bool:
    """active/ 디렉토리에 미완료 체크박스가 있는 .md 파일이 있는가."""
    active_dir = repo / "active"
    if not active_dir.is_dir():
        return False
    for path in active_dir.glob("*.md"):
        try:
            text = path.read_text(errors="ignore")
        except OSError:
            continue
        if "- [ ]" in text:
            return True
    return False


def has_readme(repo: Path) -> bool:
    """README 파일 존재 여부."""
    return any((repo / name).exists() for name in _README_NAMES)
