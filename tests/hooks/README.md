# Claude Code Hook 회귀 테스트

`~/.claude/hooks/` 아래 hook 스크립트를 직접 수정하지 않고, 표준 입력 JSON과 exit code, outcome 로그를 검증하는 가벼운 회귀 테스트 골격입니다.

## 디렉토리 구조

```text
~/.claude/tests/hooks/
  README.md
  runner.sh
  lib/
    assert.sh
  fixtures/
    .gitkeep
  cases/
    .gitkeep
    example.test.sh
```

- `runner.sh`: `cases/*.test.sh`를 자동 검색해 격리 실행합니다.
- `lib/assert.sh`: 공통 assertion 함수입니다.
- `fixtures/`: 테스트 입력 JSON, 샘플 로그 등 고정 fixture를 둘 자리입니다.
- `cases/`: hook별 회귀 테스트 케이스를 둡니다.

## 왜 지금 비워두는가

현재 outcome 로그 데이터가 아직 적어서 실제 사용 패턴을 대표하는 케이스를 확정하기 이릅니다. 1주일 뒤 `~/.claude/cache/hook-outcomes/{date}.jsonl`에 500건 이상 쌓이면 핵심 5개 hook의 실제 `pass/warn/block/detect/summarize/trigger` 패턴을 보고 케이스를 추가합니다.

## 사용법

```bash
bash ~/.claude/tests/hooks/runner.sh
bash ~/.claude/tests/hooks/runner.sh --verbose
bash ~/.claude/tests/hooks/runner.sh --filter dangerous
```

- `--verbose`: 각 케이스 stdout/stderr를 출력합니다.
- `--filter <pattern>`: 케이스명에 grep 매칭되는 테스트만 실행합니다.

## 케이스 추가 방법

1. `cases/{hook-name}.test.sh` 파일을 추가합니다.
2. 첫 줄 근처에 `# name: {검색 가능한 케이스명}`을 적으면 `--filter` 대상 이름으로 사용됩니다.
3. `lib/assert.sh`를 source합니다.
4. `HOOK_OUTCOME_DIR`를 임시 디렉토리로 export한 뒤 hook을 호출합니다.
5. 기대 exit code와 outcome 로그를 assertion으로 검증합니다.

예:

```bash
source "$TEST_ROOT/lib/assert.sh"
stdout=$(printf '%s\n' "$stdin_json" | "$HOME/.claude/hooks/some-hook.sh" 2>&1)
actual=$?
assert_exit_code 2 "$actual"
assert_outcome_logged "some-hook" "block"
```

`HOOK_OUTCOME_DIR` override는 현재 `outcome-log.sh`에서 지원합니다. CI에는 나중에 `bash ~/.claude/tests/hooks/runner.sh`를 그대로 연결할 수 있습니다.

참고: `dangerous-command-detect.sh`는 현재 `PostToolUse` 경고 hook입니다. 실제 소스 기준으로 위험 명령에서도 `exit 0`과 `warn` outcome을 기대합니다.
