#!/bin/zsh
# SessionStart: 현재 세션 transcript 크기를 점검해 컨텍스트 누적 경고.
#
# 배경 (2026-05-31 정정):
#   이 hook은 '긴 세션 = 응답 비용/지연 증가' 경고 전용이다.
#   ⚠️ 도구 호출 깨짐의 원인을 '컨텍스트 길이'로 단정하지 말 것 (반증됨):
#     - <invoke> 태그 평문 누출은 428KB 작은 세션에서도 발생 → 크기 무관.
#       실측 근본원인 = 모델이 도구호출 XML(function_calls) 스트리밍 중
#       내부 stop sequence에 걸려 블록이 미완성 절단 → call/count 잔여물 +
#       네임스페이스 누락 <invoke>가 평문으로 굳음. stop_reason=stop_sequence
#       (정상은 tool_use). 모델/서빙 계층 버그라 사용자 통제 불가, 재시도로 회피.
#     - AskUserQuestion questions=string(한글 \uXXXX 깨짐)은 별개 증상.
#   따라서 '세션 재시작'은 깨짐 해결책이 아니라 비용/지연 완화책일 뿐이다.
#
# 동작: resume/compact 시점에 transcript 크기 측정 → 임계 초과면 경고 출력.
#   startup(신규 세션)은 transcript가 작으므로 조용.

: "${HOME:?}"

INPUT=$(cat 2>/dev/null)

# transcript_path 추출
TRANSCRIPT=$(printf '%s' "$INPUT" | /usr/bin/python3 -c '
import json,sys
try:
    d=json.loads(sys.stdin.read())
    print(d.get("transcript_path","") or "")
except Exception:
    pass
' 2>/dev/null)

[ -n "$TRANSCRIPT" ] || exit 0
[ -f "$TRANSCRIPT" ] || exit 0

SIZE=$(/usr/bin/stat -f '%z' "$TRANSCRIPT" 2>/dev/null || echo 0)

# 임계값 (bytes)
WARN=1258291    # 1.2MB — 경고
DANGER=1782579  # 1.7MB — 강력 권고 (실측 깨짐 발생 지점)

MB=$(echo "scale=1; $SIZE/1048576" | /usr/bin/bc 2>/dev/null || echo "?")

if [ "$SIZE" -ge "$DANGER" ]; then
    printf '%s\n' "[🔴 긴 세션 ${MB}MB] 컨텍스트 비대 — 응답 비용/지연 증가. 큰 작업은 새 세션 권장. (도구호출 <invoke> 평문 누출이나 AskUserQuestion 깨짐은 세션 크기 무관한 모델측 버그 — 즉시 재시도로 회피되며 새 세션이 해결책 아님.)"
elif [ "$SIZE" -ge "$WARN" ]; then
    printf '%s\n' "[🟡 세션 ${MB}MB] 길어지는 중. 큰 작업은 새 세션 고려."
fi

exit 0
