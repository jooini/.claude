# @dev 에이전트에 글로벌 에이전트 호출 기능 추가

## Context

현재 `@dev`는 프로젝트 단독 작업만 수행. 글로벌 에이전트(백엔드, 리뷰어, 테스터 등)를 활용하려면 사용자가 직접 호출해야 함.
`@dev`가 업무 파악 후 필요한 글로벌 에이전트를 자율 호출하도록 개선.
`@team`은 크로스 프로젝트 전용으로 유지.

## 역할 분리

| 에이전트 | 역할 |
|----------|------|
| `@dev` | 프로젝트 전담 리드. docs 로드 → 작업 분석 → 글로벌 에이전트 호출 → 결과 통합 |
| `@team` | 크로스 프로젝트 팀 구성 (다른 프로젝트 teammate spawn) |
| 글로벌 에이전트 | `@dev`가 호출하는 전문가 (리뷰어, 테스터, 백엔드 등) |

## 수정 대상

10개 프로젝트의 `.claude/agents/dev.md`:

1. `~/Workspace/speakingmax-backend/.claude/agents/dev.md`
2. `~/Workspace/identity-hub/.claude/agents/dev.md`
3. `~/Workspace/identity-hub-frontend/.claude/agents/dev.md`
4. `~/Workspace/identity-keycloak/.claude/agents/dev.md`
5. `~/Workspace/maxai-b2c-backend/.claude/agents/dev.md`
6. `~/Workspace/identity-hub-python-sdk/.claude/agents/dev.md`
7. `~/Workspace/keycloak-kakao-social-provider/.claude/agents/dev.md`
8. `~/Workspace/sso-fallback-monitor/.claude/agents/dev.md`
9. `~/Workspace/maxai-docker/.claude/agents/dev.md`
10. `~/Workspace/identity-platform-docker/.claude/agents/dev.md`

## 추가할 섹션: "글로벌 에이전트 활용"

각 dev.md에 아래 섹션 추가:

```markdown
## 글로벌 에이전트 활용

작업 수행 시 필요에 따라 글로벌 에이전트를 호출한다.

| 단계 | 에이전트 | 호출 조건 |
|------|---------|-----------|
| 구현 | backend-developer / frontend-developer | 복잡한 구현 작업 |
| 리뷰 | code-reviewer | 코드 수정 후 항상 |
| 테스트 | code-tester | 테스트 가능한 환경일 때 |
| QA | qa | 테스트 전략 수립 필요 시 |
| 설계 | Plan | 아키텍처 결정 필요 시 |

### 워크플로우

1. docs/ 로드 → 작업 분석
2. 구현 (직접 또는 developer 에이전트 호출)
3. code-reviewer 호출 (필수)
4. code-tester 호출 (테스트 환경 있으면)
5. docs/ 업데이트
```

## 프로젝트별 커스텀

- speakingmax-backend: 테스트 생략 (CI3 테스트 인프라 없음), 리뷰만
- identity-hub: backend-developer + code-tester 활용
- identity-keycloak: frontend-developer (테마 TS) + backend-developer (SPI Kotlin)
- identity-hub-frontend: frontend-developer + code-tester
- maxai-b2c-backend: 테스트 생략, 리뷰만
- Docker 프로젝트: ops-lead 활용

## 검증

- 각 프로젝트 디렉토리에서 `@dev` 호출 시 글로벌 에이전트 활용 섹션 포함 확인
- `@team`은 기존대로 동작 확인
