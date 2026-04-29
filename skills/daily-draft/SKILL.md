---
name: daily-draft
description: "오늘의 git 커밋 + 수정 파일을 Gemma(로컬 Ollama)에 넘겨 일일 보고서 초안을 한국어로 생성한다. /daily-draft 로 트리거. 초안은 파일로 저장 후 사용자/Claude가 검토. /done 스킬의 로컬 대체본."
argument-hint: "[날짜 YYYY-MM-DD, 기본값 오늘]"
disable-model-invocation: true
allowed-tools: Bash(git *), Bash(curl *), Bash(python3 *), Bash(cat *), Bash(echo *), Bash(mkdir *), Bash(date *)
---

# /daily-draft

오늘 한 작업을 로컬 Gemma에 요약시켜 일일 보고서 초안을 만든다. 외부 API 호출 없음.

## 사용 시점

- 퇴근 전 빠른 정리 (`/done`보다 가벼움, Claude 토큰 절약)
- 주간 보고서 작성 전 일일 재료 축적
- 세션 기밀이라 외부 LLM 부적합할 때

## 실행 절차

### 1단계: 대상 날짜 결정

```bash
TARGET_DATE="${ARGUMENTS:-$(date +%Y-%m-%d)}"
SINCE="${TARGET_DATE} 00:00:00"
UNTIL="${TARGET_DATE} 23:59:59"
```

### 2단계: 워크스페이스 프로젝트 순회

사용자의 Workspace 하위 git 저장소들에서 해당 날짜 커밋 수집:

```bash
WORKSPACE="${HOME}/Workspace"
COLLECTED=""

for dir in "${WORKSPACE}"/*/; do
    [ -d "${dir}/.git" ] || continue
    proj=$(basename "${dir}")

    # 저자 필터 없이 로컬 변경사항 수집
    LOG=$(git -C "${dir}" log \
        --since="${SINCE}" --until="${UNTIL}" \
        --pretty=format:'%h %s' 2>/dev/null)

    DIRTY=$(git -C "${dir}" status --porcelain 2>/dev/null | head -20)
    BRANCH=$(git -C "${dir}" branch --show-current 2>/dev/null)

    if [ -n "$LOG" ] || [ -n "$DIRTY" ]; then
        COLLECTED+="\n\n## ${proj} (브랜치: ${BRANCH})\n"
        [ -n "$LOG" ] && COLLECTED+="\n커밋:\n${LOG}\n"
        [ -n "$DIRTY" ] && COLLECTED+="\n미커밋:\n${DIRTY}\n"
    fi
done
```

데이터 없으면 "오늘 작업 이력 없음" 출력 후 종료.

### 3단계: Ollama 서버 확인

```bash
OLLAMA_HOST="${OLLAMA_HOST_LAN:-leonard.local:11434}"

if ! curl -s --max-time 3 "http://${OLLAMA_HOST}/api/tags" >/dev/null 2>&1; then
    echo "Ollama 서버 접근 불가 — /done 스킬로 Claude가 처리하도록 전환 필요"
    exit 1
fi
```

### 4단계: Gemma 호출

```bash
export COLLECTED TARGET_DATE

PAYLOAD=$(python3 <<'PYEOF'
import json, os
data = os.environ["COLLECTED"]
date = os.environ["TARGET_DATE"]
prompt = f"""다음은 {date} 하루 동안의 git 커밋/수정 내역이다. 이를 바탕으로 한국어 일일 보고서 초안을 작성해줘.

출력 형식 (정확히):

# {date} 일일 보고서

## 오늘 한 일
- <프로젝트명>: <주요 작업 요약 한 줄>
- ...

## 진행 상황
- <진행 중인 이슈/미완료>

## 내일 할 일
- <미커밋/미푸시/이슈로부터 추정>

## 메모
- <특이사항, 없으면 생략>

규칙:
- 커밋 메시지와 파일명만 근거로 작성. 없는 내용 추측 금지.
- 프로젝트별로 한 줄씩 압축.
- 이모지/장식 금지.

데이터:
{data}
"""
print(json.dumps({
    "model": "gemma4:e4b",
    "messages": [
        {"role": "system", "content": "한국어로 간결한 일일 보고서 초안만 출력. 인사/설명 금지."},
        {"role": "user", "content": prompt}
    ],
    "stream": False,
    "keep_alive": "30m"
}))
PYEOF
)

RESULT=$(curl -s --max-time 45 "http://${OLLAMA_HOST}/api/chat" \
    -H "Content-Type: application/json" \
    -d "$PAYLOAD" | python3 -c "
import json, sys
try:
    data = json.load(sys.stdin)
    print(data.get('message', {}).get('content', ''))
except Exception:
    pass
")
```

### 5단계: 초안 저장 + 안내

```bash
DRAFT_DIR="${HOME}/.claude/cache/daily-draft"
mkdir -p "${DRAFT_DIR}"
DRAFT_PATH="${DRAFT_DIR}/${TARGET_DATE}.md"
echo "$RESULT" > "$DRAFT_PATH"
```

사용자에게 출력:

```
[일일 보고서 초안 생성 완료] (로컬 Gemma)

저장 경로: ${DRAFT_PATH}

--- 초안 미리보기 ---
${RESULT}
---

다음 단계:
- 내용 검토/수정 후 최종 저장 경로로 복사 (각자 vault 위치에 맞춰)
- 전체 `/done` 루틴(커밋+푸시+세션 저장 포함) 필요하면 `/done` 실행
```

## 규칙

- 자동으로 보고서를 공식 저장 위치에 쓰지 않음 — `${HOME}/.claude/cache/daily-draft/`에만 저장
- `/done` 스킬이 수행하는 커밋/푸시/세션 히스토리 저장은 포함하지 않음 — 요약만 담당
- Gemma 환각 가능성 → 사용자 검토 필수
- 민감 커밋 메시지가 있어도 로컬이라 외부 유출 없음
- 커밋 너무 많으면(100+) git log에서 최근 50개만 사용

## 트러블슈팅

| 증상 | 원인 | 해결 |
|------|------|------|
| `Ollama 서버 접근 불가` | 로컬 서버 다운 | `/done` 루틴으로 전환 |
| 초안 비어있음 | 커밋/수정 0건 | 실제 작업 없으면 정상 |
| 프로젝트 누락 | Workspace 밖 프로젝트 | 인자 확장 검토 |
