---
name: go
description: "작업 완료 검증 자동화 스킬. /go 로 실행하면 end-to-end 테스트 → 코드 단순화 → (PR 생성은 비활성) 까지 자동 진행. 구현 직후 품질 보장용."
---

# go

작업 직후 스스로 검증하고 정리하는 워크플로우.
Opus 4.7 Anthropic 팀 권장 패턴: **검증 수단을 내장한 실행**.

"구현했다"는 것만으로는 부족함. 실제 동작을 직접 테스트하고, 코드 품질을 다듬고, 배포 준비까지 한 번에.

## 실행 조건

- 최근 대화에서 코드 수정/구현이 완료되었을 것
- 테스트 대상(서버/프론트/스크립트)이 식별 가능할 것
- 현재 디렉토리가 프로젝트 루트일 것 (`.git` 또는 `package.json` / `pyproject.toml` 등 존재)

만족 안 되면 사용자에게 대상/범위 확인 후 진행.

## 실행 절차

### 1단계: 대상 및 검증 방식 판단

최근 변경 파일과 프로젝트 스택을 분석하여 검증 방식 결정.

```bash
git diff --stat HEAD~1..HEAD 2>/dev/null || git status --short
basename $(pwd)
```

| 스택/유형 | 검증 방식 |
|---------|----------|
| FastAPI / Django / Flask | 서버 기동 + `curl` 또는 pytest end-to-end |
| Kotlin Spring Boot | `./gradlew bootRun` + `curl` 또는 `./gradlew test` |
| React / Next.js / Vue | dev 서버 기동 + Playwright MCP 브라우저 자동화 |
| PHP (CodeIgniter) | `php -S` + `curl` 또는 `phpunit` |
| CLI / 스크립트 | 실제 명령 실행 후 exit code + 출력 검증 |
| Docker Compose | `docker compose up -d` + 헬스체크 |
| SPI / Keycloak | `/build-spi` 스킬로 빌드 + 로컬 컨테이너 확인 |

### 2단계: end-to-end 테스트

결정된 방식으로 **실제 실행**.

**백엔드 예시:**
```bash
# 서버 기동 (background)
{서버 기동 명령}

# 헬스체크 + 주요 엔드포인트 요청
curl -fsS http://localhost:PORT/health
curl -fsS -X POST http://localhost:PORT/{변경된 엔드포인트} ...

# 로그 검증
tail -50 {로그 경로} | grep -iE "error|exception|warn"
```

**프론트엔드 예시:**
```
mcp__plugin_playwright_playwright__browser_navigate → 페이지 접근
browser_snapshot → DOM 상태 확인
browser_click / browser_fill_form → 변경된 UI 인터랙션
browser_console_messages → JS 에러 확인
```

**테스트 스위트 있으면 함께 실행:**
```bash
# Python
pytest -x tests/ 2>&1 | tail -30

# Node
npm test 2>&1 | tail -30

# PHP
vendor/bin/phpunit 2>&1 | tail -30
```

검증 실패 시:
- 원인 분석 후 수정 → 재검증 (최대 3회)
- 3회 실패 시 `codex:codex-rescue` foreground 호출 또는 사용자에게 판단 요청

### 3단계: /simplify 실행

검증 통과 후 `simplify` 스킬 실행. 변경 파일 대상 중복 제거, 네이밍 일관성, 불필요한 추상화 제거.

```
Skill(simplify)
```

simplify가 변경을 제안하면 적용 후 **2단계 검증 재실행** (회귀 방지).

### 4단계: 상태 리포트

```
🎯 /go 완료 — {프로젝트명}
══════════════════════════════════════════

✅ end-to-end 검증
  • {테스트 항목 1}: 통과
  • {테스트 항목 2}: 통과
  • ...

🧹 /simplify
  • 변경 파일: {N}개
  • 주요 개선: {요약}

📦 변경 요약
  • {파일}: {변경 내용}
  • ...

──────────────────────────────────────────
다음 단계: 커밋/PR 준비 완료
```

### 5단계: PR 생성 (현재 비활성)

<!--
PR 생성은 현재 주석 처리됨. 활성화하려면 아래 블록 주석 해제.

- 먼저 `git status`로 변경사항 확인
- 커밋 메시지는 한글로 작성, Co-Authored-By 포함 금지
- PR 생성 전 `codex:review` 로 최종 검증 (글로벌 파이프라인 규칙)

```bash
# 1. 브랜치 확인 (main/master면 새 브랜치 생성)
CURRENT_BRANCH=$(git branch --show-current)

# 2. 스테이징 + 커밋
git add {변경 파일들}
git commit -m "{한글 커밋 메시지}"

# 3. 푸시
git push -u origin "$CURRENT_BRANCH"

# 4. PR 생성 전 Codex 최종 리뷰
# codex:review 호출 (또는 codex exec --skip-git-repo-check "diff 리뷰")

# 5. PR 생성
gh pr create \
  --title "{PR 제목}" \
  --body "$(cat <<'EOF'
## Summary
- {변경 요약 1}
- {변경 요약 2}

## Test plan
- [x] end-to-end 검증 완료
- [x] /simplify 실행
- [ ] 리뷰어 확인

EOF
)"
```
-->

PR 생성을 수동으로 진행할 경우 사용자에게 안내:

```
📌 PR 생성은 현재 비활성 상태입니다.
   수동 PR 생성이 필요하면 `gh pr create` 또는 `@dev PR 만들어줘` 요청하세요.
```

## 주의사항

- **검증 없이 "완료" 선언 금지**. 테스트 미실행/실패 시 명시.
- end-to-end 테스트는 **실제 실행**이 원칙. 정적 분석만으로 대체 금지.
- 외부 API 호출 테스트는 사전 확인 (비용/레이트리밋/상태 변경 주의).
- DB/인프라 영향 작업은 추가로 `codex:adversarial-review` 호출 권장.
- 검증 실패 재시도 3회 초과 → codex-rescue 에스컬레이션 (background 금지, foreground만).
- simplify가 동작을 바꿀 수 있으므로 반드시 재검증.
- PR 생성 블록 활성화 시 글로벌 파이프라인 규칙(병렬 리뷰, Codex review 등) 준수.
