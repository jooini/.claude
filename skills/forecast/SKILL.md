---
name: forecast
description: 30분 후 장애 예보관. /forecast 로 현재 git diff를 분석해 운영 흐름에서 깨질 위험 시나리오를 자동 추출. API shape, SSO 인증, 환경변수, DB 마이그레이션, 호출자 분석.
---

# Forecast — 30분 후 장애 예보

코드 변경 직후 30분 안에 발생할 가능성이 높은 운영 장애를 시나리오로 추출한다.

## 검출 시나리오

1. **API shape 변경** — JSON key add/remove + API/schema 파일 변경 감지
2. **SSO/인증 영향** — AUTH_MODE/JWT/Identity Hub/Keycloak 키워드
3. **환경변수 의존성** — os.environ / process.env 참조 변경
4. **DB 마이그레이션** — migration 디렉토리/SQL 파일 변경
5. **테스트 약화** — 테스트 파일 삭제/skip
6. **호출자 영향** — 제거된 함수의 caller 위치 grep

## 사용법

- `/forecast` — 현재 cwd 의 unstaged diff 분석
- `/forecast staged` — 스테이지된 변경만
- `/forecast head` — 마지막 커밋 (HEAD~1..HEAD)
- `/forecast json` — JSON 출력

## 절차

```bash
# 현재 작업 디렉토리에서
python3 ~/.claude/scripts/failure-forecaster.py --cwd "$PWD" --mode unstaged
```

각 시나리오는 (확률, 영향, 완화 방법) 형식으로 출력.

## 출력 예시

```
## 위험 시나리오

### 1. API shape 변경 (확률: 높음)
- 시나리오: 제거된 키 ['user'] / 추가된 키 ['subject']. 프론트 캐시는 이전 shape를 들고 있음. 30분 내 토큰 refresh 시 shape 불일치.
- 완화: 프론트에서 새 shape 핸들링 확인. 캐시 무효화.

### 2. SSO/인증 영향 (확률: 높음)
- ...
```

## 한계 (MVP)

- Playwright/API smoke 자동 실행 미구현 — 수동 검증 필요
- LLM 시뮬레이션 미통합 — 휴리스틱 기반
- callers 검색은 rg 기반 — 동적 호출/리플렉션 미감지

## 통합 아이디어

- PostToolUse(Edit/Write) 훅에서 자동 실행 후 큰 위험 시 stderr 알림
- /go (작업 완료 검증) 스킬 마지막 단계로 추가
- /cross-check 와 결합 (SSO 멀티 프로젝트 영향)
