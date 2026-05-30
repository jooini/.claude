#!/bin/zsh
# danger-keyword-detect.sh rm 우회 탐지 현황 테스트
# 현재 어떤 rm 변형이 잡히고 어떤 게 빠져나가는지 가시화
HOOK="$HOME/.claude/hooks/danger-keyword-detect.sh"

pass=0; fail=0
run() {
  local desc="$1" cmd="$2" expect="$3"
  local payload out rc got mark
  payload=$(python3 -c 'import json,sys; print(json.dumps({"tool_input":{"command":sys.argv[1]}}))' "$cmd")
  out=$(printf '%s' "$payload" | /bin/zsh "$HOOK" 2>&1)
  rc=$?
  got="pass"
  [ $rc -eq 2 ] && got="block"
  if [ $rc -ne 2 ] && printf '%s' "$out" | grep -q "위험 명령 감지"; then got="warn"; fi
  if [ "$got" = "$expect" ]; then mark="OK"; pass=$((pass+1)); else mark="MISS"; fail=$((fail+1)); fi
  printf '%-5s [%s] expect>=%s got=%s\n' "$mark" "$desc" "$expect" "$got"
}

H="$HOME"
echo "=== rm 루트/홈 삭제 변형 (warn 이상 기대) ==="
run "rm -rf /"          "rm -rf /"               warn
run "rm -rf ~"          "rm -rf ~"               warn
run "rm -rf \$HOME"     "rm -rf \$HOME"          warn
run "절대경로 /bin/rm /" "/bin/rm -rf /"          warn
run "절대경로 /usr/bin/rm ~" "/usr/bin/rm -rf ~"  warn
run "command rm -rf /"  "command rm -rf /"       warn
run "env rm -rf ~"      "env rm -rf ~"           warn

echo ""
echo "=== 우회 명령 (warn 이상 기대) ==="
run "find -delete 홈"   "find ~ -delete"         warn
run "find -exec rm"     "find / -exec rm -rf {} +" warn
run "xargs rm 홈"       "ls ~ | xargs rm -rf"    warn

echo ""
echo "=== 정상 명령 (pass 기대 — 오탐 점검) ==="
run "rm 일반 파일"      "rm -rf ./build"         pass
run "rm 임시"           "rm /tmp/x.log"          pass

echo ""
echo "현황: $pass 기대일치 / $fail 빠져나감(MISS=커버 안 됨)"
exit 0
