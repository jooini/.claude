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


def _make_repo(dirty: int, days_ago: int) -> RepoStatus:
    last = datetime.now(timezone.utc) - timedelta(days=days_ago)
    return RepoStatus(path=Path("/tmp/x"), dirty_count=dirty, last_commit_at=last)


def test_active_backlog_bonus():
    """active backlog 있으면 +10 가산."""
    repo = _make_repo(dirty=2, days_ago=30)  # base: commit_pts=25 + dirty_pts=40 = 65 (warm)
    s_no = score(repo, has_backlog=False, has_readme_=True)
    s_yes = score(repo, has_backlog=True, has_readme_=True)
    assert s_yes.value == s_no.value + 10
    # 65 → 75 = active 경계


def test_no_readme_low_score_penalty():
    """value < 50 + README 없으면 -10 페널티."""
    repo_low = _make_repo(dirty=60, days_ago=70)  # base: 25 + 5 = 30 < 50
    s = score(repo_low, has_backlog=False, has_readme_=False)
    s_with_readme = score(repo_low, has_backlog=False, has_readme_=True)
    assert s.value == s_with_readme.value - 10


def test_readme_does_not_penalize_high_score():
    """value >= 50일 때는 README 없어도 페널티 X."""
    repo = _make_repo(dirty=2, days_ago=1)  # base 100
    s_no_readme = score(repo, has_backlog=False, has_readme_=False)
    s_with_readme = score(repo, has_backlog=False, has_readme_=True)
    assert s_no_readme.value == s_with_readme.value


def test_clamp_max_100():
    """active + backlog → 100 초과 X."""
    repo = _make_repo(dirty=2, days_ago=1)  # base 100
    s = score(repo, has_backlog=True, has_readme_=True)
    assert s.value == 100  # +10 unused, clamp


def test_clamp_min_0():
    """dead repo (commit_pts==0)는 early return으로 0 유지."""
    repo = _make_repo(dirty=0, days_ago=400)
    s = score(repo, has_backlog=True, has_readme_=False)
    assert s.value == 0  # early return 무시
    assert s.label == "dead"


def test_default_args_backwards_compatible():
    """기존 호출 (위치 인자만) 그대로 동작."""
    repo = _make_repo(dirty=2, days_ago=1)
    s = score(repo)  # has_backlog/has_readme_ 기본 False/True (옵션)
    assert s.value > 0
