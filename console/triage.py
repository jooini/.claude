"""미커밋 파일을 4 카테고리로 자동 분류."""
from __future__ import annotations

from enum import Enum
from pathlib import PurePath


class FileCategory(str, Enum):
    COMMIT_READY = "commit_ready"
    EXPERIMENT = "experiment"
    DELETE = "delete"
    UNKNOWN = "unknown"


COMMIT_READY_PATTERNS = {
    p.lower() for p in {
        "package-lock.json", "yarn.lock", "uv.lock", "Pipfile.lock",
        "Cargo.lock", "go.sum", "poetry.lock",
    }
}
DELETE_EXTS = {".log", ".tmp", ".bak", ".swp"}
DELETE_NAMES = {n.lower() for n in {"nohup.out", "core", "Thumbs.db", ".DS_Store"}}
EXPERIMENT_NAME_HINTS = ("scratch", "tmp_", "_experiment", "draft_")


def classify(path: str, status: str) -> FileCategory:
    p = PurePath(path)
    name = p.name.lower()

    if name in COMMIT_READY_PATTERNS:
        return FileCategory.COMMIT_READY

    if p.suffix.lower() in DELETE_EXTS or name in DELETE_NAMES:
        return FileCategory.DELETE

    if any(hint in name for hint in EXPERIMENT_NAME_HINTS):
        return FileCategory.EXPERIMENT

    return FileCategory.UNKNOWN
