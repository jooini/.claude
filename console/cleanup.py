"""commit_ready 일괄 커밋 + delete 일괄 삭제."""
from __future__ import annotations

from pathlib import Path
import subprocess


COMMIT_MESSAGE = "chore: WIP cleanup (lockfiles, generated)"


def commit_ready_in_repo(repo: Path, files: list[str]) -> None:
    """repo의 files를 stage 후 단일 커밋."""
    subprocess.run(["git", "add", "--"] + files, cwd=repo, check=True, timeout=10)
    subprocess.run(
        ["git", "commit", "-q", "-m", COMMIT_MESSAGE],
        cwd=repo, check=True, timeout=10,
    )


def delete_in_repo(repo: Path, files: list[str]) -> None:
    """repo의 files를 안전하게 삭제 (파일만, 디렉토리 X)."""
    for f in files:
        target = repo / f
        if target.exists() and target.is_file():
            target.unlink()
