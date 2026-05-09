from pathlib import Path
import subprocess
from console.archive import archive_repos


def test_archive_moves_repo(tmp_path: Path):
    src = tmp_path / "src"
    src.mkdir()
    for name in ["a", "b"]:
        d = src / name
        d.mkdir()
        subprocess.run(["git", "init", "-q"], cwd=d, check=True)

    archive_dir = tmp_path / "_archive"

    archived = archive_repos([src / "a"], archive_dir)

    assert (archive_dir / "a" / ".git").exists()
    assert not (src / "a").exists()
    assert (src / "b").exists()
    assert archived == [archive_dir / "a"]


def test_archive_skips_existing(tmp_path: Path):
    src = tmp_path / "src"
    src.mkdir()
    d = src / "dup"
    d.mkdir()
    subprocess.run(["git", "init", "-q"], cwd=d, check=True)

    archive_dir = tmp_path / "_archive"
    (archive_dir / "dup").mkdir(parents=True)

    archived = archive_repos([src / "dup"], archive_dir)

    # 충돌 처리 — suffix or skip. 데이터 손실 X
    assert (src / "dup").exists() or any(p.name.startswith("dup") for p in archived)
