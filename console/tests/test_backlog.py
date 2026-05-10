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


def test_has_active_backlog_in_docs_active(tmp_path: Path):
    """<repo>/docs/active/ 컨벤션 (가장 많음)"""
    (tmp_path / "docs" / "active").mkdir(parents=True)
    (tmp_path / "docs" / "active" / "task.md").write_text("- [ ] todo\n")
    assert has_active_backlog(tmp_path) is True


def test_has_active_backlog_in_claude_active(tmp_path: Path):
    """<repo>/.claude/active/ 컨벤션 (일부)"""
    (tmp_path / ".claude" / "active").mkdir(parents=True)
    (tmp_path / ".claude" / "active" / "task.md").write_text("- [ ] todo\n")
    assert has_active_backlog(tmp_path) is True


def test_has_active_backlog_priority_root_first(tmp_path: Path):
    """3 경로 모두 있어도 하나만 True면 True (단락)"""
    # docs/active만 미완료
    (tmp_path / "docs" / "active").mkdir(parents=True)
    (tmp_path / "docs" / "active" / "t.md").write_text("- [ ] todo\n")
    # active/ 는 모두 완료
    (tmp_path / "active").mkdir()
    (tmp_path / "active" / "done.md").write_text("- [x] done\n")
    assert has_active_backlog(tmp_path) is True


def test_has_active_backlog_all_paths_empty(tmp_path: Path):
    """모든 경로에 미완료 없음"""
    (tmp_path / "active").mkdir()
    (tmp_path / "docs" / "active").mkdir(parents=True)
    (tmp_path / ".claude" / "active").mkdir(parents=True)
    # 파일 없음
    assert has_active_backlog(tmp_path) is False
