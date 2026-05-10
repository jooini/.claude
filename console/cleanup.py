"""commit_ready 일괄 커밋 + delete 일괄 삭제."""
from __future__ import annotations

from pathlib import Path
import re
import subprocess


COMMIT_MESSAGE = "chore: WIP cleanup (lockfiles, generated)"

_ITEM_RE = re.compile(r"^- `(.+?)` :: `(.+)` \[")


def parse_triage_md(md_path: Path) -> dict[str, list[tuple[str, str]]]:
    """triage 마크다운 파싱. `<repo_rel_path>` :: `<file_path>` [<status>] 형식.

    repo_rel_path 는 workspace_root 기준 상대 경로 (중첩 repo 지원,
    예: ``meeting-minutes/frontend``). file_path 는 해당 repo 내부 파일 경로.
    """
    text = md_path.read_text()
    sections: dict[str, list[tuple[str, str]]] = {
        "commit_ready": [],
        "delete": [],
        "experiment": [],
        "unknown": [],
    }
    current: str | None = None
    for line in text.splitlines():
        stripped = line.strip()
        if stripped.startswith("## "):
            header = stripped[3:].split("(")[0].strip()
            current = header if header in sections else None
            continue
        if current is None:
            continue
        m = _ITEM_RE.match(line)
        if m:
            sections[current].append((m.group(1), m.group(2)))
    return sections


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
