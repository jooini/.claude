from pathlib import Path
import subprocess

from console.cleanup import commit_ready_in_repo, delete_in_repo


def test_commit_ready_creates_one_commit(tmp_path: Path):
    repo = tmp_path / "r"
    repo.mkdir()
    subprocess.run(["git", "init", "-q"], cwd=repo, check=True)
    subprocess.run(["git", "config", "user.email", "t@t"], cwd=repo, check=True)
    subprocess.run(["git", "config", "user.name", "t"], cwd=repo, check=True)
    (repo / "package-lock.json").write_text("{}")

    commit_ready_in_repo(repo, ["package-lock.json"])

    log = subprocess.run(
        ["git", "log", "--oneline"],
        cwd=repo, capture_output=True, text=True,
    ).stdout
    assert log.count("\n") == 1
    assert "WIP" in log or "lockfile" in log.lower() or "cleanup" in log.lower()


def test_delete_removes_files(tmp_path: Path):
    repo = tmp_path / "r"
    repo.mkdir()
    subprocess.run(["git", "init", "-q"], cwd=repo, check=True)
    (repo / "debug.log").write_text("...")

    delete_in_repo(repo, ["debug.log"])

    assert not (repo / "debug.log").exists()
