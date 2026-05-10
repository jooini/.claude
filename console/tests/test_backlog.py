from pathlib import Path
from console.adapters.backlog import has_active_backlog, has_readme


def test_has_active_backlog_true(tmp_path: Path):
    active = tmp_path / "active"
    active.mkdir()
    (active / "task1.md").write_text("# Task 1\n- [ ] todo item\n- [x] done item\n")
    assert has_active_backlog(tmp_path) is True


def test_has_active_backlog_no_dir(tmp_path: Path):
    assert has_active_backlog(tmp_path) is False


def test_has_active_backlog_all_done(tmp_path: Path):
    active = tmp_path / "active"
    active.mkdir()
    (active / "task1.md").write_text("# Task\n- [x] done\n")
    assert has_active_backlog(tmp_path) is False


def test_has_readme_md(tmp_path: Path):
    (tmp_path / "README.md").write_text("# Hello")
    assert has_readme(tmp_path) is True


def test_has_readme_none(tmp_path: Path):
    assert has_readme(tmp_path) is False


def test_has_readme_rst(tmp_path: Path):
    (tmp_path / "README.rst").write_text("Hello")
    assert has_readme(tmp_path) is True
