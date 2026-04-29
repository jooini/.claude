---
name: done
description: "퇴근 전 마무리 루틴. /done 으로 실행하면 미커밋 확인 → 커밋 → 일일 보고서 → 세션 히스토리 저장까지 자동 진행."
---

# done

퇴근 전 하루 마무리 루틴. 한 번에 모든 정리 작업 수행.

## 실행 절차

### 1단계: 미커밋 변경 확인

모든 프로젝트에서 미커밋 변경사항 수집:

```bash
PROJECTS=(
  "$HOME/Workspace/identity-hub"
  "$HOME/Workspace/maxai-b2c-backend"
  "$HOME/Workspace/identity-keycloak"
  "$HOME/Workspace/identity-hub-frontend"
  "$HOME/Workspace/identity-hub-python-sdk"
  "$HOME/Workspace/sso-fallback-monitor"
  "$HOME/Workspace/maxai-stt-engine"
  "$HOME/Workspace/wb-platform-backend"
  "$HOME/Workspace/speakingmax-backend"
)

for proj in "${PROJECTS[@]}"; do
  if [ -d "$proj/.git" ]; then
    DIRTY=$(git -C "$proj" status --porcelain 2>/dev/null)
    if [ -n "$DIRTY" ]; then
      BRANCH=$(git -C "$proj" branch --show-current 2>/dev/null)
      COUNT=$(echo "$DIRTY" | wc -l | tr -d ' ')
      echo "$(basename $proj)|$BRANCH|$COUNT"
    fi
  fi
done
```

### 2단계: 미커밋 처리

미커밋 변경이 있는 프로젝트별로:

1. `git diff --stat` 으로 변경 내용 확인
2. 변경 내용 분석하여 한글 커밋 메시지 자동 생성
3. `git add` + `git commit` 실행
4. `git push` 실행

- `.env`, 민감 파일은 스테이징하지 않는다
- Co-Authored-By 포함하지 않는다
- 프로젝트가 여러 개면 순차 처리

### 3단계: 미푸시 커밋 확인

```bash
for proj in "${PROJECTS[@]}"; do
  if [ -d "$proj/.git" ]; then
    UNPUSHED=$(git -C "$proj" log --oneline @{u}..HEAD 2>/dev/null)
    if [ -n "$UNPUSHED" ]; then
      echo "$(basename $proj): 미푸시 커밋 있음"
      echo "$UNPUSHED"
    fi
  fi
done
```

미푸시 커밋이 있으면 `git push` 실행.

### 4단계: 일일 보고서 작성

`/write-daily-report` 스킬의 절차를 따라 일일 보고서 생성.

경로: `~/Workspace/weaversbrain/weaversbrain/Daily/YYYY-MM/YYYY-MM-DD.md`

### 5단계: 세션 히스토리 저장

`/save-history` 스킬의 절차를 따라 세션 히스토리 저장.

경로: `~/Workspace/weaversbrain/weaversbrain/Sessions/YYYY-MM/YYYY-MM-DD-{프로젝트명}.md`

### 6단계: 최종 요약 출력

```
🌙 마무리 완료 — {YYYY-MM-DD}
══════════════════════════════════════════

📦 커밋/푸시
  • {프로젝트}: {커밋 메시지} ✅
  • {프로젝트}: 변경 없음
  • ...

📝 일일 보고서
  • {obsidian://URI}

📓 세션 히스토리
  • {obsidian://URI}

🔮 내일 할 일
  • {보고서에서 추출한 내일 할 일 1}
  • {내일 할 일 2}
  • ...

──────────────────────────────────────────
수고하셨습니다 👋
```

## 주의사항

- 커밋/푸시 실패 시 에러 표시하고 다음 프로젝트로 넘어간다
- 일일 보고서가 이미 있으면 기존 내용에 추가 (덮어쓰기 금지)
- 민감 정보 마스킹
- 전체 프로세스 중 에러가 발생해도 나머지는 계속 진행
