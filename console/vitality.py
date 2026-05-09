"""repo 생존 점수. 0 (죽음) ~ 100 (활발)."""
from __future__ import annotations

from dataclasses import dataclass
from datetime import datetime, timezone
from typing import Literal

from console.adapters.git import RepoStatus

Label = Literal["active", "warm", "zombie", "stale", "dead", "empty"]


@dataclass(frozen=True)
class VitalityScore:
    value: int
    label: Label
    reason: str


def score(repo: RepoStatus) -> VitalityScore:
    if repo.last_commit_at is None:
        return VitalityScore(0, "empty", "커밋 없음")

    days_ago = (datetime.now(timezone.utc) - repo.last_commit_at).days

    if days_ago <= 3:
        commit_pts = 60
    elif days_ago <= 14:
        commit_pts = 45
    elif days_ago <= 60:
        commit_pts = 25
    elif days_ago <= 180:
        commit_pts = 10
    else:
        commit_pts = 0

    # 180일+ 미커밋 = dead. 깨끗하든 더럽든 점수 0.
    if commit_pts == 0:
        return VitalityScore(0, "dead", f"커밋 {days_ago}일 전 (180일 초과 — dead)")

    if repo.dirty_count == 0:
        dirty_pts = 30
    elif repo.dirty_count <= 10:
        dirty_pts = 40
    elif repo.dirty_count <= 50:
        dirty_pts = 20
    else:
        dirty_pts = 5

    value = commit_pts + dirty_pts
    label = _label(value, repo.dirty_count, days_ago)
    reason = f"커밋 {days_ago}일 전 + 미커밋 {repo.dirty_count}개"
    return VitalityScore(value, label, reason)


def _label(value: int, dirty: int, days_ago: int) -> Label:
    if dirty > 30 and days_ago > 14:
        return "zombie"
    if value >= 75:
        return "active"
    if value >= 50:
        return "warm"
    if value >= 20:
        return "stale"
    return "dead"
