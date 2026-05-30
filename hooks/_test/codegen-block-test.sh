#!/bin/zsh
# bash-codegen-block.sh — heredoc 전면차단 제거 후 검증
# 오탐(분석/검증 heredoc 통과) + 정탐(코드파일 생성 차단)
HOOK="$HOME/.claude/hooks/bash-codegen-block.sh"

# heredoc 마커를 변수로 조립해 이 테스트 스크립트 자체가 차단되지 않게
LT="<<"
MARKER="EOF"
PYM="PYEOF"

pass=0; fail=0
run() {
    local desc="$1" cmd="$2" expect="$3"
    local payload out rc got mark
    payload=$(/usr/bin/python3 -c 'import json,sys; print(json.dumps({"tool_input":{"command":sys.argv[1]}}))' "$cmd")
    out=$(printf '%s' "$payload" | /bin/zsh "$HOOK" 2>&1)
    rc=$?
    got="pass"; [ $rc -eq 2 ] && got="block"
    if [ "$got" = "$expect" ]; then mark="OK"; pass=$((pass+1)); else mark="FAIL"; fail=$((fail+1)); fi
    printf '%-5s [%s] expect=%s got=%s\n' "$mark" "$desc" "$expect" "$got"
}

echo "=== 오탐 테스트 (pass 기대 — 이전엔 전면차단됨) ==="
run "python3 검증 heredoc"  "python3 - ${LT}'$PYM'
import json
print(1)
$PYM" pass
run "cat heredoc 분석"      "cat ${LT}$MARKER
analysis text
$MARKER" pass
run "ini 프롬프트 heredoc"  "ini -p - ${LT}'$MARKER'
요약해줘
$MARKER" pass
run "docker exec heredoc"   "docker exec c sh ${LT}$MARKER
ls /app
$MARKER" pass

echo ""
echo "=== 정탐 테스트 (block 기대 — 코드파일 생성) ==="
run "cat > .py 파일"        "cat ${LT}$MARKER > script.py
print(1)
$MARKER" block
run "cat > .ts 파일"        "cat ${LT}$MARKER > app.ts
const x=1
$MARKER" block
run "echo > .js 파일"       "echo \"const x=1\" > app.js" block
run "printf > .go 파일"     "printf 'package main' > main.go" block

echo ""
echo "=== 정상 명령 (pass 기대) ==="
run "일반 git"              "git status" pass
run "python 실행"          "python3 script.py" pass

echo ""
echo "결과: $pass OK / $fail FAIL"
exit $fail
