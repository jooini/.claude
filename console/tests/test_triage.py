from console.triage import classify, FileCategory


def test_classify_lockfile_as_commit_ready():
    assert classify("package-lock.json", "M") == FileCategory.COMMIT_READY
    assert classify("uv.lock", "M") == FileCategory.COMMIT_READY


def test_classify_log_as_delete():
    assert classify("debug.log", "??") == FileCategory.DELETE
    assert classify("nohup.out", "??") == FileCategory.DELETE


def test_classify_test_scratch_as_experiment():
    assert classify("test_scratch.py", "??") == FileCategory.EXPERIMENT
    assert classify("scratch.ipynb", "??") == FileCategory.EXPERIMENT


def test_classify_source_as_unknown():
    assert classify("src/main.py", "M") == FileCategory.UNKNOWN
