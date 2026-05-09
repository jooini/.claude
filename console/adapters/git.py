"""107개 repo의 git status를 병렬 스캔."""
from __future__ import annotations

from dataclasses import dataclass
from datetime import datetime
from pathlib import Path
from typing import Iterator
import subprocess


@dataclass(frozen=True)
class RepoStatus:
    path: Path
    dirty_count: int
    last_commit_at: datetime | None


def scan_repos(root: Path, max_depth: int = 2) -> Iterator[RepoStatus]:
    """root 하위 max_depth 단계에서 .git 디렉토리를 가진 repo를 찾고 status 수집."""
    for git_dir in _find_git_dirs(root, max_depth):
        repo_path = git_dir.parent
        yield RepoStatus(
            path=repo_path,
            dirty_count=_count_dirty(repo_path),
            last_commit_at=_last_commit(repo_path),
        )


def _find_git_dirs(root: Path, max_depth: int) -> Iterator[Path]:
    if max_depth < 0:
        return
    if not root.is_dir():
        return
    for child in root.iterdir():
        if child.name == ".git" and child.is_dir():
            yield child
            continue
        if child.is_dir() and not child.is_symlink():
            yield from _find_git_dirs(child, max_depth - 1)


def _count_dirty(repo: Path) -> int:
    result = subprocess.run(
        ["git", "status", "--porcelain"],
        cwd=repo, capture_output=True, text=True,
    )
    if result.returncode != 0:
        return 0
    return len([l for l in result.stdout.splitlines() if l.strip()])


def _last_commit(repo: Path) -> datetime | None:
    result = subprocess.run(
        ["git", "log", "-1", "--format=%cI"],
        cwd=repo, capture_output=True, text=True,
    )
    if result.returncode != 0 or not result.stdout.strip():
        return None
    return datetime.fromisoformat(result.stdout.strip())
