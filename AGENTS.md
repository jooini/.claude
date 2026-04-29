# 공용 에이전트 규칙

이 파일은 Claude Code, Antigravity, Gemini CLI, Codex CLI 공통 규칙입니다.

## 커밋 규칙

- Co-Authored-By 포함하지 않음
- 커밋 메시지는 한글로 작성

## 응답 스타일

- 묻지 말고 알아서 끝까지 진행. 중간 확인/상태 업데이트 금지
- 병렬 실행 우선. 순차 실행 금지
- "~하겠습니다" 식 확인 반복 금지. 결과 나오면 바로 다음 단계

## 코딩 컨벤션

- FastAPI: `Depends()` 직접 사용 금지 → `Annotated` 앨리어스 사용
- 클래스 리네이밍 시 파일명도 함께 변경
- 약어/줄임 네이밍 금지 → 풀네임 사용

## 코드 수정 워크플로우

코드를 수정할 때는 반드시 구현 → 리뷰 → 테스트 파이프라인을 실행한다.

- 수정 후 반드시 테스트 실행. 테스트 안 돌리고 완료 선언 금지
- 리뷰 → 재수정 루프 최대 3회. 초과 시 사용자에게 판단 요청
- 보안/DB/인프라/API breaking change 시 추가 보안 리뷰 수행

## 도구 역할 분담

- **Claude Code**: 메인 두뇌 — 구현, 추론, 리뷰, 의사결정
- **Codex CLI**: 검증/대안 — adversarial review, 세컨드 오피니언
- **Gemini CLI**: 스캐너 — 대규모 코드베이스 전체 로딩 후 요약 추출 (1M 토큰)
- **Antigravity**: 병렬 일손 — Manager Surface로 멀티 에이전트 동시 디스패치
- **Jules**: 백그라운드 워커 — 테스트/문서/의존성 PR 자동 생성
- **Deep Research**: 조사관 — 기술 조사, 보안 분석, 마이그레이션 전략

## 문서 작성 규칙

- Obsidian Vault: `~/Workspace/weaversbrain/weaversbrain/`
- 파일명에 시분 포함: `YYYY-MM-DD-HHMM-{파일명}.md`
- YAML frontmatter 필수
- 프로젝트 내부(docs/)에 만들지 말 것 → 반드시 옵시디언 Vault에 생성

## 프로젝트 공통 규칙

- Kotlin Spring Boot 우선 (백엔드 신규)
- PostgreSQL (관계형), Redis (캐시/세션)
- Prometheus 메트릭 + 구조화 로그로 관측성 확보
- 티켓: EPIC-NNN 형식, 1-2일 단위, acceptance criteria 필수
- 알 수 없는 비즈니스 요구사항을 만들어내지 말 것

## SSO 핵심 정책

- 계정 중복 허용: 전화번호/이메일 중복 허용 (레거시 유지)
- SSO 폴백: identity-nginx에서 502/503/504 시 레거시 폴백
- BFF 패턴: client_secret은 Identity Hub만 보유
- Keycloak: `getUserByUsername`에 반드시 `exact=True`
