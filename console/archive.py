"""죽은 repo 아카이브. 이동만, 삭제 금지. git history 유지."""
from __future__ import annotations

from pathlib import Path
import shutil


def archive_repos(repo_paths: list[Path], archive_dir: Path) -> list[Path]:
    """repo_paths의 각 repo를 archive_dir로 이동.
    충돌 시 suffix `-N` 추가. 이동만, 압축/삭제 X."""
    archive_dir.mkdir(parents=True, exist_ok=True)
    moved: list[Path] = []
    for src in repo_paths:
        if not src.exists():
            continue
        target = archive_dir / src.name
        if target.exists():
            i = 2
            while (archive_dir / f"{src.name}-{i}").exists():
                i += 1
            target = archive_dir / f"{src.name}-{i}"
        shutil.move(str(src), str(target))
        moved.append(target)
    return moved
