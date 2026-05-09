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
