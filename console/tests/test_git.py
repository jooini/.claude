from pathlib import Path
import subprocess
import pytest
from console.adapters.git import scan_repos, RepoStatus


def test_scan_repos_finds_git_dirs(tmp_path: Path):
    # Given: 임시 디렉토리에 2개의 git repo
    for name in ["repo_a", "repo_b"]:
        d = tmp_path / name
        d.mkdir()
        subprocess.run(["git", "init", "-q"], cwd=d, check=True)

    # When: scan_repos 호출
    repos = list(scan_repos(tmp_path, max_depth=2))

    # Then: 2개 repo 발견
    paths = sorted(r.path.name for r in repos)
    assert paths == ["repo_a", "repo_b"]
    assert all(isinstance(r, RepoStatus) for r in repos)


def test_scan_repos_collects_dirty_count(tmp_path: Path):
    # Given: 더러운 repo 1개
    d = tmp_path / "dirty"
    d.mkdir()
    subprocess.run(["git", "init", "-q"], cwd=d, check=True)
    (d / "file.txt").write_text("hello")

    # When
    repos = list(scan_repos(tmp_path, max_depth=2))

    # Then: dirty_count == 1 (untracked file)
    assert len(repos) == 1
    assert repos[0].dirty_count == 1


def test_scan_repos_collects_last_commit(tmp_path: Path):
    # Given: 커밋 1개 있는 repo
    d = tmp_path / "with_commit"
    d.mkdir()
    subprocess.run(["git", "init", "-q"], cwd=d, check=True)
    subprocess.run(["git", "config", "user.email", "test@test"], cwd=d, check=True)
    subprocess.run(["git", "config", "user.name", "test"], cwd=d, check=True)
    (d / "f.txt").write_text("x")
    subprocess.run(["git", "add", "."], cwd=d, check=True)
    subprocess.run(["git", "commit", "-q", "-m", "init"], cwd=d, check=True)

    # When
    repos = list(scan_repos(tmp_path, max_depth=2))

    # Then
    assert len(repos) == 1
    assert repos[0].last_commit_at is not None


def test_scan_repos_skips_permission_denied(tmp_path: Path):
    # Given: 권한 없는 디렉토리 안에 repo가 있고, 형제로 정상 repo도 있음
    import os
    blocked = tmp_path / "blocked"
    blocked.mkdir()
    (blocked / "inner_repo").mkdir()
    subprocess.run(["git", "init", "-q"], cwd=blocked / "inner_repo", check=True)

    sibling = tmp_path / "sibling_repo"
    sibling.mkdir()
    subprocess.run(["git", "init", "-q"], cwd=sibling, check=True)

    os.chmod(blocked, 0o000)
    try:
        # When: scan_repos 호출
        repos = list(scan_repos(tmp_path, max_depth=3))

        # Then: 권한 없는 디렉토리는 스킵되어도 generator 중단되지 않음
        # blocked 안의 repo는 발견 안 됨, sibling은 발견됨
        names = [r.path.name for r in repos]
        assert "sibling_repo" in names
        assert all("blocked" not in str(r.path) for r in repos)
    finally:
        os.chmod(blocked, 0o700)  # cleanup
