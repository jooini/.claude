# /yesterday - 어제 추적 종합

어제 한 일 / 변경 / 자동화 결과를 한 화면에 표시하는 통합 명령.

## 사용법

- `/yesterday` — 어제 (전일)
- `/yesterday 2` — 2일 전
- `/yesterday 7` — 7일 전 (주간 회고와 별개)

## 수행 작업 (병렬)

### 1단계: 어제 커밋 (12 프로젝트 병렬)

```bash
YESTERDAY=$(date -v-1d +%Y-%m-%d)
PROJECTS=(
  identity-hub maxai-b2c-backend identity-keycloak
  identity-hub-frontend identity-hub-python-sdk
  sso-fallback-monitor wb-platform-backend
  ai-agentic-workflow identity-platform-docker
  keycloak-kakao-social-provider member-api maxai-docker
)

for proj in "${PROJECTS[@]}"; do
  COMMITS=$(git -C ~/Workspace/$proj log --oneline --since="$YESTERDAY 00:00" --until="$YESTERDAY 23:59" 2>/dev/null)
  PUSHED=$(git -C ~/Workspace/$proj log --oneline --since="$YESTERDAY 00:00" --until="$YESTERDAY 23:59" --remotes 2>/dev/null)
  if [ -n "$COMMITS" ]; then
    echo "[$proj]"
    echo "$COMMITS"
  fi
done
```

### 2단계: 어제 일일 보고서 (있다면)

```bash
DAILY="$HOME/Workspace/weaversbrain/weaversbrain/Daily/$(date -v-1d +%Y-%m)/$(date -v-1d +%Y-%m-%d).md"
if [ -f "$DAILY" ]; then
    head -30 "$DAILY"
fi
```

### 3단계: 어제 자동화 작업 결과

```bash
# Gemma cron 결과
grep "$(date -v-1d +%Y-%m-%d)" ~/.claude/cache/gemma-cron.log | head -5

# 주간 retro (금요일이었으면)
ls ~/.claude/cache/retro/$(date -v-1d +%Y-%m-%d)*.md 2>/dev/null

# backup-cleanup (월요일이었으면)
grep "$(date -v-1d +%Y-%m-%d)" ~/.claude/cache/backup-cleanup.log 2>/dev/null | head -3

# claude-mem 인덱싱
grep "$(date -v-1d +%Y-%m-%d)" ~/.claude/cache/gemma-calls.jsonl 2>/dev/null | wc -l
```

### 4단계: 어제 active 파일 진척

```bash
for proj in "${PROJECTS[@]}"; do
  ACTIVE_DIR="$HOME/Workspace/$proj/docs/active"
  if [ -d "$ACTIVE_DIR" ]; then
    YESTERDAY_FILES=$(find "$ACTIVE_DIR" -name "*.md" -newer "$ACTIVE_DIR/.." -mtime -1 2>/dev/null)
    if [ -n "$YESTERDAY_FILES" ]; then
      echo "[$proj] active 변경: $(echo "$YESTERDAY_FILES" | wc -l)개"
    fi
  fi
done
```

### 5단계: 어제 메트릭 (있다면)

```bash
METRIC="$HOME/.claude/cache/metrics/$(date -v-1d +%Y-%m-%d).tsv"
if [ -f "$METRIC" ]; then
    TOTAL=$(grep -v "^timestamp" "$METRIC" | wc -l)
    AGENTS=$(awk -F'\t' 'NR>1 {a[$2]++} END {for (k in a) print "  " k": "a[k]"회"}' "$METRIC")
    echo "총 호출: $TOTAL회"
    echo "$AGENTS"
fi
```

### 6단계: 종합 출력

```
📅 어제 ({날짜}) 종합 추적
══════════════════════════════════════════

📦 커밋 (총 N개, M 프로젝트)
  [identity-hub]
  abc1234 회원가입 검증 추가
  [maxai-b2c-backend]
  def5678 SSO 콜백 수정

📝 일일 보고서: {요약 또는 "없음"}

🤖 자동화 결과
  • Gemma cron: ✅ 14:00 정상 / ❌ 실패
  • 주간 retro: (금요일만)
  • backup-cleanup: (월요일만)
  • claude-mem 인덱싱: N건

📋 active 변경
  • {프로젝트}: N개 파일

🤖 에이전트 호출
  • backend-developer: X회
  • code-reviewer: Y회
  ...

══════════════════════════════════════════

💡 어제 못 끝낸 것:
  - {detected from active files marked 진행중}

💡 오늘 이어서 할 것:
  - {추천}
```

## 활용 패턴

### 아침 첫 명령
```
/yesterday  # 어제 진척 확인
/morning    # 오늘 시작
```

### 회고 전
```
/yesterday 7  # 1주일 전 비교
/retro 7      # 주간 통계
```

## 주의

- 모든 소스 read-only — 변경 없음
- 어제 일일 보고서 없으면 "보고서 없음" 표시 (탓 아님)
- 12 프로젝트 git log 병렬 실행 (5초 이내 완료)

## 관련 자료

- `/morning` — 오늘 시작
- `/retro 7` — 주간 회고
- `/decisions` — 과거 결정 검색
