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


def test_classify_lockfile_mixed_case():
    assert classify("Pipfile.lock", "M") == FileCategory.COMMIT_READY
    assert classify("Cargo.lock", "M") == FileCategory.COMMIT_READY


def test_classify_ds_store_as_delete():
    assert classify(".DS_Store", "??") == FileCategory.DELETE


def test_classify_scratch_substring_does_not_match_unrelated():
    # scratchpad.py도 EXPERIMENT (scratch substring)
    assert classify("scratchpad.py", "??") == FileCategory.EXPERIMENT
    # 무관한 파일은 UNKNOWN
    assert classify("config.py", "M") == FileCategory.UNKNOWN
