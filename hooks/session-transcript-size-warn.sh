#!/bin/zsh
# SessionStart: 현재 세션 transcript 크기를 점검해 컨텍스트 누적 경고.
#
# 배경 (2026-05-31 확정):
#   긴 대화(transcript ~1.5MB+)에서 모델의 구조화 출력(structured output)이 저하되어
#   AskUserQuestion 등 복잡한 한글 배열 인자 도구 호출이 JSON 직렬화 실패
#   (questions=string, 한글 \uXXXX 깨짐). 인코딩/설정 문제가 아니라 컨텍스트 한계.
#   해결: 임계점 전에 세션 재시작. 이 hook이 조기 경고.
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
    printf '%s\n' "[🔴 긴 세션 ${MB}MB] 컨텍스트 비대 — 응답 비용/지연 증가. 큰 작업은 새 세션 권장. 참고: AskUserQuestion이 questions=string으로 깨지면(이중 직렬화) 평문 질문으로 대체."
elif [ "$SIZE" -ge "$WARN" ]; then
    printf '%s\n' "[🟡 세션 ${MB}MB] 길어지는 중. 큰 작업은 새 세션 고려."
fi

exit 0
