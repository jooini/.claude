---
name: pr-draft
description: "현재 브랜치의 커밋/diff를 Gemma(로컬 Ollama)에 넘겨 PR 제목·본문 한국어 초안을 생성한다. /pr-draft 로 트리거. 초안은 /tmp/pr-draft.md 저장 후 사용자/Claude가 검토·수정해 사용."
argument-hint: "[base-branch]"
disable-model-invocation: true
allowed-tools: Bash(git *), Bash(curl *), Bash(python3 *), Bash(cat *), Bash(echo *)
---

# /pr-draft

현재 브랜치의 커밋 내역을 로컬 Gemma에 넘겨 PR 제목/본문 초안을 생성한다. 외부 API 호출 없음(로컬 Ollama).

## 실행 절차

### 1단계: base 브랜치 결정

```bash
BASE="${ARGUMENTS:-main}"
# origin에 base 존재 여부 확인
if ! git rev-parse --verify "origin/$BASE" &>/dev/null; then
    # main 없으면 master 시도
    if git rev-parse --verify "origin/master" &>/dev/null; then
        BASE="master"
    elif git rev-parse --verify "origin/develop" &>/dev/null; then
        BASE="develop"
    fi
fi
CURRENT=$(git branch --show-current)
```

현재 브랜치 = base면 중단 ("동일 브랜치에는 PR 생성 불가").

### 2단계: 변경 내역 수집

```bash
# 커밋 로그 (제목만, 최대 30개)
COMMITS=$(git log --oneline "origin/${BASE}..HEAD" | head -30)

# 변경 파일 통계
STAT=$(git diff --stat "origin/${BASE}..HEAD")

# diff 본문 (최대 800줄)
DIFF=$(git diff "origin/${BASE}..HEAD" | head -800)
```

커밋 0개면 중단.

### 3단계: Ollama 서버 확인

```bash
OLLAMA_HOST="${OLLAMA_HOST_LAN:-leonard.local:11434}"

if ! curl -s --max-time 3 "http://${OLLAMA_HOST}/api/tags" >/dev/null 2>&1; then
    echo "Ollama 서버(${OLLAMA_HOST}) 접근 불가"
    exit 1
fi
```

서버 다운 시 중단하고 사용자에게 알림.

### 4단계: Gemma 호출

python3로 JSON 페이로드 안전하게 조립:

```bash
PAYLOAD=$(python3 <<'PYEOF'
import json, os
commits = os.environ["COMMITS"]
stat = os.environ["STAT"]
diff = os.environ["DIFF"]
prompt = f"""다음 변경사항으로 GitHub/GitLab PR 설명 초안을 한국어로 작성해줘.

출력 형식 (정확히 이 구조):

# 제목
<70자 이내 한글 제목>

# 본문
## 요약
- <핵심 변경 2~4줄>

## 변경 내역
- <파일/모듈별 주요 변경>

## 테스트
- [ ] <수동 검증 항목 초안>

## 리뷰 포인트
- <리뷰어가 주목할 부분>

규칙:
- 환각 금지. diff에 없는 내용 추측 금지
- 커밋 메시지와 diff만 근거로 작성
- Co-Authored-By 포함 금지

커밋 목록:
{commits}

변경 파일 통계:
{stat}

diff:
{diff}
"""
print(json.dumps({
    "model": "gemma4:e4b",
    "messages": [
        {"role": "system", "content": "한국어로 간결하게. PR 초안 외 다른 설명/인사 금지."},
        {"role": "user", "content": prompt}
    ],
    "stream": False,
    "keep_alive": "30m"
}))
PYEOF
)

RESULT=$(curl -s --max-time 60 "http://${OLLAMA_HOST}/api/chat" \
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

환경변수에 COMMITS/STAT/DIFF 주입 후 실행.

### 5단계: 초안 저장 + 안내

```bash
DRAFT_PATH="/tmp/pr-draft-$(date +%Y%m%d-%H%M%S).md"
echo "$RESULT" > "$DRAFT_PATH"
```

사용자에게 출력:

```
[PR 초안 생성 완료] (로컬 Gemma)

저장 경로: ${DRAFT_PATH}

--- 초안 미리보기 ---
${RESULT}
---

다음 단계:
1. 초안 검토/수정: ${DRAFT_PATH}
2. PR 생성 (gh):
     gh pr create --base ${BASE} --body-file ${DRAFT_PATH} --title "<제목>"
3. PR 생성 (GitLab — create-mr 스킬 사용 시):
     해당 스킬 실행 후 본문에 초안 붙여넣기
```

## 규칙

- 자동으로 `gh pr create`/`gh pr edit` 실행하지 않는다 — 사용자 명시 확인 필수
- 민감 파일 포함된 브랜치에서는 diff 잘라내기 경고
- Gemma 환각 가능성 있으므로 반드시 사용자 검토 단계를 거칠 것
- 초안 경로는 타임스탬프 포함하여 덮어쓰기 방지
- 커밋 30개 초과 시 최근 30개만 사용 (모델 컨텍스트 한계)

## 트러블슈팅

| 증상 | 원인 | 해결 |
|------|------|------|
| `Ollama 서버 접근 불가` | 윈도우 노트북 꺼짐/방화벽 | Ollama 트레이 확인, 포트 11434 허용 |
| 초안이 영어로 나옴 | 시스템 프롬프트 무시 | 재실행 (keep_alive로 다음은 OK) |
| 응답 비어있음 | 타임아웃 (60초 초과) | diff가 너무 큼 — `git log --oneline`만 넘기기 |
| JSON 파싱 실패 | 특수문자 이스케이프 | python3 `os.environ` 경유로 주입 (현재 방식) |
