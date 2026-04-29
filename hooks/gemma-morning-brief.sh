#!/bin/zsh
# SessionStart: 세션 시작 시 어제 요약 + 오늘 git 상태 + 우선순위 브리핑
# 출력: stdout (세션 시작 시 한 번만 표시)
# 캐시: 같은 날 이미 실행했으면 캐시 사용

: "${HOME:?}"

OLLAMA_HOST="${OLLAMA_HOST_LAN:-leonard.local:11434}"
CACHE_DIR="$HOME/.claude/cache/morning-brief"
mkdir -p "$CACHE_DIR"

TODAY=$(date +%Y-%m-%d)
YESTERDAY=$(date -v-1d +%Y-%m-%d 2>/dev/null || date -d "1 day ago" +%Y-%m-%d)
CURRENT_HOUR=$(date +%H)

OUTPUT_FILE="$CACHE_DIR/${TODAY}.md"

# 오늘 이미 브리핑 했으면 캐시 출력 (세션당 1회만)
if [ -f "$OUTPUT_FILE" ]; then
    echo "[세션 브리핑 — 캐시 ${TODAY}]"
    cat "$OUTPUT_FILE"
    exit 0
fi

# 오전 일찍(<04시)이나 심야엔 스킵
if [ "$CURRENT_HOUR" -lt 5 ]; then
    exit 0
fi

# Ollama 확인
if ! curl -s --max-time 2 "http://${OLLAMA_HOST}/api/tags" >/dev/null 2>&1; then
    exit 0
fi

# 어제 health 리포트 있으면 요약 활용
YESTERDAY_HEALTH="$HOME/.claude/cache/health-report/${YESTERDAY}.md"
YESTERDAY_CONTEXT=""
if [ -f "$YESTERDAY_HEALTH" ]; then
    # "오늘 평가" 섹션만 10줄 (토큰 절약)
    YESTERDAY_CONTEXT=$(/usr/bin/awk '/## 오늘 평가/{flag=1; next} /^## /{flag=0} flag' "$YESTERDAY_HEALTH" | /usr/bin/head -10)
fi

# 오늘 git 상태 빠르게 수집 (워크스페이스 전체)
WORKSPACE="$HOME/Workspace"
export GIT_STATUS YESTERDAY_CONTEXT TODAY YESTERDAY

GIT_STATUS=$(python3 <<'PYEOF'
import os, subprocess
from pathlib import Path
workspace = Path.home() / "Workspace"
dirty_list = []
today_commits = 0
unpushed_count = 0

for d in sorted(workspace.iterdir()):
    if not d.is_dir() or not (d / ".git").exists():
        continue
    try:
        status = subprocess.run(
            ["git", "-C", str(d), "status", "--porcelain"],
            capture_output=True, text=True, timeout=3
        ).stdout.strip()
        if status:
            cnt = len(status.splitlines())
            if cnt >= 3:
                dirty_list.append((d.name, cnt))

        # 어제 커밋 개수
        log = subprocess.run(
            ["git", "-C", str(d), "log", f"--since={os.environ['YESTERDAY']} 00:00", f"--until={os.environ['TODAY']} 00:00", "--oneline"],
            capture_output=True, text=True, timeout=3
        ).stdout.strip()
        if log:
            today_commits += len(log.splitlines())

        # 미푸시
        unpushed = subprocess.run(
            ["git", "-C", str(d), "log", "@{u}..HEAD", "--oneline"],
            capture_output=True, text=True, timeout=3
        ).stdout.strip()
        if unpushed:
            unpushed_count += len(unpushed.splitlines())
    except Exception:
        continue

dirty_list.sort(key=lambda x: -x[1])
top_dirty = dirty_list[:5]

parts = []
parts.append(f"어제 커밋: {today_commits}건")
parts.append(f"미푸시 커밋: {unpushed_count}건")
parts.append(f"dirty 프로젝트: {len(dirty_list)}개")
if top_dirty:
    parts.append("상위 5개 dirty:")
    for name, cnt in top_dirty:
        parts.append(f"  - {name}: {cnt}개")

print("\n".join(parts))
PYEOF
)

if [ -z "$GIT_STATUS" ]; then
    exit 0
fi

# Gemma 호출 - 간결한 브리핑 생성
export GIT_STATUS YESTERDAY_CONTEXT TODAY YESTERDAY OLLAMA_HOST_LAN="${OLLAMA_HOST}"

BRIEF=$(python3 <<'PYEOF'
import json, os, urllib.request

ctx = os.environ.get("YESTERDAY_CONTEXT", "")
status = os.environ["GIT_STATUS"]
today = os.environ["TODAY"]
yesterday = os.environ["YESTERDAY"]

prompt = f"""{today} 세션 시작 브리핑을 작성해줘.

[{yesterday} 헬스 평가 요약]
{ctx if ctx else "(없음)"}

[오늘 {today} 워크스페이스 상태]
{status}

출력 형식 (정확히 4줄, 한국어):
어제: <어제 핵심 성과/이슈 한 줄>
오늘 상태: <미커밋/미푸시 요약 한 줄>
오늘 우선순위: <가장 먼저 손대야 할 것 한 줄, 구체 프로젝트명 포함>
목표 제안: <오늘 최소 달성 목표 한 줄>

규칙:
- 정확히 4줄만. 접두어 그대로.
- 이모지/장식 금지. 간결하게.
- 데이터 근거만 사용.
"""

def call_gemma(num_predict):
    body = json.dumps({
        "model": "gemma4:e4b",
        "messages": [{"role": "user", "content": prompt}],
        "stream": False,
        "keep_alive": "30m",
        "options": {"num_predict": num_predict, "temperature": 0.3}
    }).encode()
    req = urllib.request.Request(
        f"http://{os.environ.get('OLLAMA_HOST_LAN', 'leonard.local:11434')}/api/chat",
        data=body,
        headers={"Content-Type": "application/json"}
    )
    try:
        with urllib.request.urlopen(req, timeout=45) as r:
            data = json.loads(r.read())
        return data.get("message", {}).get("content", "").strip()
    except Exception:
        return ""

# 1차 시도. 빈 응답 시 num_predict 2배로 재시도 (gemma4:e4b가 thinking에 토큰 소진하는 케이스 대응)
result = call_gemma(3000)
if not result:
    result = call_gemma(6000)
print(result)
PYEOF
)

if [ -z "$BRIEF" ]; then
    exit 0
fi

# 파일 저장 + 출력
{
    echo "=== 세션 시작 브리핑 (${TODAY}) ==="
    echo ""
    echo "$BRIEF"
    echo ""
    echo "---"
    echo "(상세: /health 2026-04-21 어제 리포트 · /triage 미커밋 정리)"
} > "$OUTPUT_FILE"

cat "$OUTPUT_FILE"
exit 0
