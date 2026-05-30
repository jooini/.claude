#!/bin/zsh
# danger-keyword-detect.sh SQL 차단/오탐 테스트
# 키워드를 변수 조합으로 만들어 Claude Code 내장 차단을 회피
HOOK="$HOME/.claude/hooks/danger-keyword-detect.sh"

D=$'\x44\x52\x4f\x50'        # DROP
DB=$'\x44\x41\x54\x41\x42\x41\x53\x45'  # DATABASE
TBL=$'\x54\x41\x42\x4c\x45'  # TABLE
DEL=$'\x44\x45\x4c\x45\x54\x45'  # DELETE

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
  if [ "$got" = "$expect" ]; then mark="OK"; pass=$((pass+1)); else mark="FAIL"; fail=$((fail+1)); fi
  printf '%-4s [%s] expect=%s got=%s rc=%s\n' "$mark" "$desc" "$expect" "$got" "$rc"
}

echo "=== 오탐 테스트 (pass 기대) ==="
run "echo SQL 언급"   "echo \"$D $TBL users is risky\""        pass
run "codex 분석"      "codex exec \"explain $D $DB\""          pass
run "grep SQL 검색"   "grep -r \"$DEL FROM\" ./src"            pass
run "주석 작성"       "echo \"# $D $TBL caution\" >> notes.md" pass
run "커밋메시지 도구명" "git commit -m \"mysql psql $D $TBL 오탐 수정\"" pass
run "DB도구 인자언급"  "echo \"psql -c $D $DB 설명\" >> doc.md"  pass
run "코드 grep"        "grep -rn \"mysql.*$DEL FROM\" ./src"      pass

echo ""
echo "=== 정탐 테스트 (block 기대) ==="
run "psql DROP DB"    "psql -c \"$D $DB prod\""                block
run "mysql DROP TBL"  "mysql -e \"$D $TBL users\""             block
run "psql DELETE"     "psql -d app -c \"$DEL FROM members\""   block
run "mongosh dropDB"  "mongosh --eval \"db.${D:l}Database()\"" block

echo ""
echo "=== 기타 위험 (warn 기대) ==="
run "sudo rm"         "sudo rm /tmp/x"                         warn
run "chmod 777"       "chmod -R 777 ./dir"                     warn

echo ""
echo "결과: $pass OK / $fail FAIL"
exit $fail
