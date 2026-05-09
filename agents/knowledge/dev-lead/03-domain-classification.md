# 도메인 분류 기준

> Backend, Frontend, Fullstack, Data, AI, DevOps를 빠르게 식별하여 전문 에이전트를 배치한다.

---

## 1. 도메인 분류의 목적

작업 도메인을 정확히 분류해야 적절한 에이전트가 투입된다.

도메인 분류는 파일 확장자보다 변경의 목적을 우선한다.

예를 들어 TypeScript 파일이라도 React 컴포넌트면 Frontend이고, NestJS 서비스면 Backend다.

---

## 2. 도메인 빠른 판별표

| 도메인 | 핵심 질문 | 대표 에이전트 |
|--------|-----------|---------------|
| Backend | 서버 상태, API, DB, 권한이 바뀌는가? | backend-developer |
| Frontend | 사용자 화면, 상호작용, 상태가 바뀌는가? | frontend-developer |
| Fullstack | API 계약과 화면이 함께 바뀌는가? | backend + frontend |
| Data | 쿼리, 지표, 모델링, ETL이 핵심인가? | data-analyst |
| AI | LLM, 프롬프트, 임베딩, 평가가 핵심인가? | ai-engineer |
| DevOps | 배포, 인프라, CI/CD, 운영이 핵심인가? | ops-lead |

---

## 3. Backend 도메인

Backend는 서버가 보유한 상태와 규칙을 다룬다.

**Backend 신호:**
- API 엔드포인트 추가/수정
- 서비스 계층 로직 변경
- DB schema 또는 repository 변경
- 인증/인가 로직 변경
- 캐시, 큐, 트랜잭션 변경
- 외부 시스템 연동

**대표 파일:**
- `controller`, `route`, `handler`
- `service`, `usecase`, `domain`
- `repository`, `entity`, `migration`
- `security`, `auth`, `middleware`

### Backend 에이전트 호출

```typescript
Agent("backend-developer", {
  task: "회원 탈퇴 API에서 세션 무효화와 audit log 저장 구현",
  risk: ["auth", "data deletion", "transaction"],
  expectedOutput: ["changed files", "test command", "edge cases"],
});
```

---

## 4. Frontend 도메인

Frontend는 사용자가 직접 보는 화면과 상호작용을 다룬다.

**Frontend 신호:**
- 페이지, 컴포넌트, 폼 변경
- 라우팅, 상태 관리 변경
- API 응답 표시 방식 변경
- 접근성, 반응형, 시각 디자인 변경
- 브라우저 이벤트와 사용자 입력 처리

**대표 파일:**
- `*.tsx`, `*.jsx`, `component`, `page`
- `store`, `hook`, `viewmodel`
- `css`, `scss`, `tailwind`
- `playwright`, `storybook`

### Frontend 에이전트 호출

```python
frontend = Agent(
    "frontend-developer",
    task="주문 상세 화면에 환불 상태 배지를 추가",
    constraints=["기존 디자인 시스템 유지", "모바일 레이아웃 확인"],
)
designer = Agent("designer", task="상태 배지 색상과 밀도 리뷰")
```

---

## 5. Fullstack 도메인

Fullstack은 API 계약과 화면이 함께 바뀌는 경우다.

**Fullstack 신호:**
- 서버 응답 필드가 추가되고 UI가 이를 표시함
- 폼 입력값이 API 요청 DTO와 연결됨
- 인증 플로우가 서버와 브라우저 양쪽에서 바뀜
- 에러 코드와 UI 메시지를 함께 설계해야 함

### Fullstack 분류 기준

| 질문 | 예이면 |
|------|--------|
| API 요청/응답이 바뀌는가? | Fullstack 가능성 |
| 프론트 mock만 바꾸면 안 되는가? | Fullstack |
| BE/FE 작업 순서가 계약에 묶이는가? | Fullstack |
| 통합 테스트가 필요한가? | Fullstack |

### Fullstack 실행 패턴

```typescript
const contract = {
  endpoint: "GET /orders/:id",
  response: "{ id, status, refundStatus, items }",
};

Agent("backend-developer", { task: "refundStatus 응답 필드 추가", contract });
Agent("frontend-developer", { task: "refundStatus 배지 표시", contract });
Agent("qa", { task: "API 계약과 화면 표시 통합 검증", contract });
```

---

## 6. Data 도메인

Data는 쿼리와 지표의 정확성이 핵심인 작업이다.

**Data 신호:**
- 대시보드 지표 변경
- SQL/ClickHouse/BigQuery 쿼리 변경
- 이벤트 스키마 변경
- 집계 기준 변경
- 데이터 품질 검증
- 실험 분석 또는 코호트 분석

**주의점:**
- 지표 정의는 제품 정책과 연결된다.
- 쿼리 결과는 샘플 데이터로 검증해야 한다.
- 성능과 정확성이 동시에 중요하다.

```python
Agent("data-analyst", task="MAU 집계 기준 변경 영향 분석", output=[
    "old_vs_new_definition",
    "sample_query",
    "edge_cases",
])
```

---

## 7. AI 도메인

AI 도메인은 모델 호출, 프롬프트, 평가, 임베딩, RAG가 핵심이다.

**AI 신호:**
- LLM 프롬프트 변경
- 도구 호출 체인 변경
- embedding 검색 품질 개선
- 모델 라우팅 변경
- 평가셋 구성
- hallucination 또는 safety 대응

### AI 에이전트 조합

| 상황 | 주 에이전트 | 보조 |
|------|-------------|------|
| 프롬프트 품질 | prompt-engineer | ai-engineer |
| RAG 검색 개선 | ai-engineer | data-analyst |
| 모델 비용 절감 | ai-engineer | ops-lead |
| 평가셋 구축 | qa | data-analyst |

---

## 8. DevOps 도메인

DevOps는 실행 환경과 배포 신뢰성을 다룬다.

**DevOps 신호:**
- Dockerfile, compose, Helm, Terraform 변경
- CI/CD 파이프라인 변경
- 모니터링, 알림, 로그 변경
- 배포 전략 변경
- secret, network, IAM 변경
- 운영 장애 대응

```typescript
Agent("ops-lead", {
  task: "Redis 연결 timeout 설정을 운영 환경에 반영",
  checks: ["rollback", "observability", "secret impact"],
});
```

---

## 9. 혼합 도메인 처리

혼합 도메인은 주 도메인과 보조 도메인을 나눈다.

| 작업 | 주 도메인 | 보조 도메인 |
|------|-----------|-------------|
| 로그인 UI + 토큰 갱신 | Fullstack | DevOps 가능 |
| 추천 모델 결과 화면 | AI | Frontend |
| 대시보드 성능 개선 | Data | Backend |
| 배포 후 500 에러 | DevOps | Backend |

---

## 10. 분류 체크리스트

- [ ] 변경 목적이 무엇인지 확인했는가?
- [ ] 파일 확장자가 아니라 책임 기준으로 분류했는가?
- [ ] API 계약이 바뀌는지 확인했는가?
- [ ] 데이터 정의가 바뀌는지 확인했는가?
- [ ] 배포 또는 운영 영향이 있는지 확인했는가?
- [ ] AI 모델/프롬프트/평가가 관련되는지 확인했는가?
- [ ] 혼합 도메인이면 주/보조 도메인을 나눴는가?

---

## 11. 최종 기준

도메인 분류는 에이전트 배치의 시작점이다.

확신이 없으면 사전 분석 에이전트에게 "이 작업의 실제 도메인을 코드 근거로 분류하라"고 먼저 요청한다.
