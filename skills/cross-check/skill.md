---
name: cross-check
description: SSO 멀티프로젝트 간 영향 분석. Identity Hub API 변경 시 B2C/Keycloak/Frontend에 미치는 영향을 검사한다. "/cross-check", "교차 검증", "영향 분석" 등으로 트리거.
allowed-tools: Bash, Read, Glob, Grep, Agent
---

# Cross Check

하나의 프로젝트 변경이 SSO 생태계 전체에 미치는 영향을 분석한다.

## SSO 프로젝트 의존 관계

```
Identity Hub (Python/FastAPI) ← 중심
    ↑ API 호출
    ├── B2C Backend (PHP/CI3) — /api/v1/* 엔드포인트 사용
    ├── Admin Frontend (Next.js) — /api/v1/* 프록시 경유
    └── Keycloak (SPI) — Admin API, Webhook 연동
```

## 실행 절차

### 1단계: 변경 프로젝트 & 범위 파악

어떤 프로젝트에서 무엇이 바뀌었는지 확인:

```bash
# 현재 프로젝트의 변경사항
git diff --name-only HEAD~1..HEAD
# 또는
git diff --name-only
```

### 2단계: 영향 매트릭스 적용

| 변경 위치 | 확인 대상 | 검사 항목 |
|----------|----------|----------|
| **Identity Hub API 엔드포인트** | B2C, Frontend | 호출 URL, 요청/응답 필드, 상태 코드 |
| **Identity Hub 토큰 형식** | B2C (JWT 검증), Frontend (세션) | JWT claims, 만료 시간, 서명 방식 |
| **Identity Hub DB 스키마** | B2C (T_Member 동기화) | 필드 추가/삭제/타입 변경 |
| **Keycloak Realm 설정** | Identity Hub, B2C | 클라이언트 설정, 플로우, 매퍼 |
| **Keycloak SPI** | Identity Hub (콜백) | Webhook URL, 페이로드 형식 |
| **B2C AUTH_MODE** | Identity Hub | SSO/레거시 분기 로직 |
| **Frontend 인증 플로우** | Identity Hub | OAuth 콜백, 토큰 교환 |

### 3단계: 프로젝트별 Grep 검사

변경된 API 경로, 필드명, 상수를 다른 프로젝트에서 검색:

```bash
# Identity Hub API 변경 시 → B2C에서 사용 여부 확인
grep -r "변경된_경로_또는_필드" ~/Workspace/maxai-b2c-backend/application/

# Identity Hub API 변경 시 → Frontend에서 사용 여부 확인
grep -r "변경된_경로_또는_필드" ~/Workspace/identity-hub-frontend/src/

# Keycloak 변경 시 → Identity Hub에서 참조 여부 확인
grep -r "변경된_설정_또는_필드" ~/Workspace/identity-hub/
```

### 4단계: 호환성 판정

| 판정 | 기준 | 액션 |
|------|------|------|
| **안전** | 다른 프로젝트에서 참조 없음 | 진행 |
| **주의** | 참조 있으나 하위호환 유지됨 | 변경 프로젝트 기록, 후속 업데이트 권고 |
| **위험** | Breaking change 감지 | 사용자에게 알림, 동시 수정 필요 |

### 5단계: 결과 보고

```
## 교차 영향 분석 결과

**변경 프로젝트**: [프로젝트명]
**변경 내용**: [요약]

### 영향 받는 프로젝트

| 프로젝트 | 영향 수준 | 영향 파일 | 필요 조치 |
|----------|----------|----------|----------|
| B2C Backend | 안전/주의/위험 | [파일 목록] | [조치 사항] |
| Admin Frontend | 안전/주의/위험 | [파일 목록] | [조치 사항] |
| Keycloak | 안전/주의/위험 | [파일 목록] | [조치 사항] |

### Breaking Changes
- [있으면 나열, 없으면 "없음"]

### 권고 사항
- [동시 수정 필요 여부, 배포 순서 등]
```

## 규칙

- 분석만 수행. 다른 프로젝트 코드 수정은 하지 않음
- Breaking change 감지 시 반드시 사용자에게 알림
- 배포 순서 권고: Identity Hub → Keycloak → B2C → Frontend (의존 방향 순)
