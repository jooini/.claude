"""repo의 active 백로그 + README 존재 신호."""
from __future__ import annotations

from pathlib import Path


_README_NAMES = ("README.md", "README.rst", "README", "readme.md")
_ACTIVE_PATHS = ("active", "docs/active", ".claude/active")


def has_active_backlog(repo: Path) -> bool:
    """워크스페이스 컨벤션 3경로 중 하나에 미완료 체크박스가 있는 .md 파일이 있는가."""
    for relative in _ACTIVE_PATHS:
        active_dir = repo / relative
        if not active_dir.is_dir():
            continue
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
