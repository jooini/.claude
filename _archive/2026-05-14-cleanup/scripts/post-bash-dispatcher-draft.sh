#!/bin/zsh
# PostToolUse(Bash) 통합 디스패처 (DRAFT — 적용 보류)
#
# 목적: PostToolUse(Bash) matcher에 8개 hook 직렬 등록 → 1개 디스패처로 통합
# 효과: 8 × 70ms = 560ms → 1 × 100ms (stdin 1회 파싱) = 460ms 절감/호출
# 일일 절감 예상: 2500회 × 460ms = 약 19분
#
# 위험: 통합 안에서 각 분기 누락 가능성. 1주 운영 데이터 검증 후 적용.
#
# 통합 대상 (현재 PostToolUse matcher=Bash 8개):
#   1. dangerous-command-detect    (가드 — 항상 검사)
#   2. error-codex-remind          (테스트/빌드 명령 + exit≠0)
#   3. tool-usage-log              (jsonl 기록)
#   4. branch-switch-detect        (git 명령 분석)
#   5. cwd-change-detect           (cd/pushd 분석)
#   6. gemini-auto-scan            (코드 구조 질문)
#   7. gemma-error-summarize       (exit≠0 + 에러 키워드)
#   8. gemini-test-failure-analyze (테스트 명령 + exit≠0)
#   9. tool-trace                  (jsonl 기록)

: "${HOME:?}"

# stdin 1회 읽기
INPUT=$(cat)

# 핵심 메타 추출 (한 번만)
COMMAND=$(echo "$INPUT" | sed -n 's/.*"command"[[:space:]]*:[[:space:]]*"\(.*\)"/\1/p' | head -1)
EXIT_CODE=$(echo "$INPUT" | sed -n 's/.*"exit_code"[[:space:]]*:[[:space:]]*\([0-9]*\).*/\1/p')

# 빠른 분기 — 패턴 매칭
IS_TEST_BUILD=0
case "$COMMAND" in
    *pytest*|*"npm test"*|*"npm run test"*|*"jest"*|*"vitest"*|*"gradle test"*|*"mvn test"*|*"go test"*|*"cargo test"*|*"phpunit"*|*"rspec"*)
        IS_TEST_BUILD=1
        ;;
esac

IS_GIT=0
case "$COMMAND" in
    git*|*" git "*) IS_GIT=1 ;;
esac

IS_CD=0
case "$COMMAND" in
    cd[[:space:]]*|*"&& cd "*|pushd*) IS_CD=1 ;;
esac

# 항상 실행 (가벼움): 데이터 수집 + 가드
echo "$INPUT" | /bin/zsh "$HOME/.claude/hooks/tool-trace.sh" >/dev/null 2>&1
echo "$INPUT" | /bin/zsh "$HOME/.claude/hooks/tool-usage-log.sh" >/dev/null 2>&1
echo "$INPUT" | /bin/zsh "$HOME/.claude/hooks/dangerous-command-detect.sh"
# (output 있을 수 있어서 stdout 통과)

# 조건부 dispatch
if [ "$IS_GIT" = "1" ]; then
    echo "$INPUT" | /bin/zsh "$HOME/.claude/hooks/branch-switch-detect.sh"
fi

if [ "$IS_CD" = "1" ]; then
    echo "$INPUT" | /bin/zsh "$HOME/.claude/hooks/cwd-change-detect.sh"
fi

if [ "$IS_TEST_BUILD" = "1" ] && [ "$EXIT_CODE" != "0" ]; then
    echo "$INPUT" | /bin/zsh "$HOME/.claude/hooks/error-codex-remind.sh"
    echo "$INPUT" | /bin/zsh "$HOME/.claude/hooks/gemini-test-failure-analyze.sh"
fi

# exit≠0 + 에러 시그널 시만
if [ "$EXIT_CODE" != "0" ] && echo "$INPUT" | grep -qiE '(traceback|error:|failed|fatal|exception)'; then
    echo "$INPUT" | /bin/zsh "$HOME/.claude/hooks/gemma-error-summarize.sh"
fi

# gemini-auto-scan: 별도 트리거 (코드 구조 질문) — 현재 매번 호출됨, 조건 검토 필요
echo "$INPUT" | /bin/zsh "$HOME/.claude/hooks/gemini-auto-scan.sh" >/dev/null 2>&1

exit 0

# ─────────────────────────────────────────────
# 적용 절차 (사용자 승인 후):
# 1. settings.json PostToolUse(Bash) 블록의 9개 hook 등록 → 1개로 통합
# 2. 백업: settings.json.bak-dispatcher-{date}
# 3. 1주 hook-trace 비교 — output 발생 횟수 동일한지 검증
# 4. 차이 발견 시 즉시 롤백
