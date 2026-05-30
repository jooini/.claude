#!/bin/zsh
# gemma-session-stop-unified.sh.new 통합 훅 검증
NEW="$HOME/.claude/hooks/gemma-session-stop-unified.sh.new"

echo "=== 1. 문법 검증 ==="
/bin/zsh -n "$NEW" && echo "OK zsh 문법" || echo "FAIL 문법"
echo ""

# 모의 ini 응답으로 블록 분할 테스트
export RESULT_TEXT='=== 블록 A: 세션 요약 ===
## 한 줄 요약
훅 통합 작업
## 주요 작업
- autoApprove 제거
=== 블록 B: 다음 세션 의도 ===
마지막 목표: Stop 훅 통합
다음 작업: 검증
=== 블록 C: 결정 ===
decisions:
  - topic: ini 1회 호출 통합
    decision: 3개 훅 합침
=== 블록 D: 학습 ===
learnings: []
=== 끝 ==='

extract_block() {
    /usr/bin/python3 - "$1" "$2" "$RESULT_TEXT" <<'PYEOF'
import re, sys
text = sys.argv[3]
start = re.escape(sys.argv[1]); end = re.escape(sys.argv[2])
pattern = r"^\s*" + start + r"\s*(.*?)^\s*" + end
m = re.search(pattern, text, re.DOTALL | re.MULTILINE)
if m: print(m.group(1).strip())
PYEOF
}

echo "=== 2. 블록 분할 테스트 ==="
A=$(extract_block "=== 블록 A: 세션 요약 ===" "=== 블록 B: 다음 세션 의도 ===")
C=$(extract_block "=== 블록 C: 결정 ===" "=== 블록 D: 학습 ===")
D=$(extract_block "=== 블록 D: 학습 ===" "=== 끝 ===")
[ -n "$A" ] && echo "OK 블록A 추출됨" || echo "FAIL 블록A"
printf '%s' "$A" | grep -q "한 줄 요약" && echo "OK 블록A 내용" || echo "FAIL 블록A 내용"
printf '%s' "$C" | grep -q "ini 1회 호출 통합" && echo "OK 블록C 내용" || echo "FAIL 블록C 내용"
printf '%s' "$D" | grep -q "learnings: \[\]" && echo "OK 블록D 빈값" || echo "FAIL 블록D"
echo ""

echo "=== 3. 빈값 체크 로직 ==="
chk() { /usr/bin/python3 -c 'import re,sys; t=sys.argv[1]; print("EMPTY" if re.search(r"'$2':\s*\[\s*\]",t) or not re.search(r"(?m)^\s*-\s*topic\s*:",t) else "HAS")' "$1"; }
r=$(chk "$C" "decisions"); [ "$r" = "HAS" ] && echo "OK decisions HAS" || echo "FAIL decisions=$r"
r=$(chk "$D" "learnings"); [ "$r" = "EMPTY" ] && echo "OK learnings EMPTY" || echo "FAIL learnings=$r"
echo ""

echo "=== 4. session_id 없는 입력 → exit 0 ==="
printf '{}' | /bin/zsh "$NEW"; echo "exit=$? (0 기대)"
echo ""

echo "=== 5. 기존 원본과 페르소나/경로 비교 ==="
echo "[ini 호출 횟수 (1 기대)]"
grep -c '"\$QWEN" -p -\|"$QWEN" -p -' "$NEW"
echo "[출력 경로 4종 확인]"
grep -oE 'SUMMARY_FILE=|INTENT_FILE=|DECISION_FILE=|LEARNING_FILE=' "$NEW" | sort -u
