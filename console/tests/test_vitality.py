from datetime import datetime, timedelta, timezone
from pathlib import Path
from console.adapters.git import RepoStatus
from console.vitality import score, VitalityScore


def _repo(name: str, dirty: int, last_days_ago: int | None) -> RepoStatus:
    last = (
        datetime.now(timezone.utc) - timedelta(days=last_days_ago)
        if last_days_ago is not None else None
    )
    return RepoStatus(path=Path(f"/tmp/{name}"), dirty_count=dirty, last_commit_at=last)


def test_active_repo_high_score():
    s = score(_repo("active", dirty=2, last_days_ago=1))
    assert s.value >= 80
    assert s.label == "active"


def test_dead_repo_zero_score():
    s = score(_repo("dead", dirty=0, last_days_ago=400))
    assert s.value <= 10
    assert s.label == "dead"


def test_zombie_repo_warning():
    s = score(_repo("zombie", dirty=50, last_days_ago=30))
    assert 30 <= s.value <= 60
    assert s.label == "zombie"


def test_never_committed():
    s = score(_repo("empty", dirty=0, last_days_ago=None))
    assert s.value == 0
    assert s.label == "empty"
