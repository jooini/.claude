---
name: migrate-endpoint
description: 레거시 B2C 엔드포인트를 SSO(Identity Hub) 경유로 전환하는 마이그레이션 절차. "/migrate-endpoint", "엔드포인트 마이그레이션", "SSO 전환" 등으로 트리거.
allowed-tools: Bash, Read, Glob, Grep, Agent, Write, Edit
---

# Migrate Endpoint

B2C 레거시 엔드포인트를 Identity Hub SSO 경유로 전환하는 표준 절차.

## 마이그레이션 패턴

```
Before: Client → B2C Backend (직접 인증/처리)
After:  Client → B2C Backend → Identity Hub (SSO 인증) → Keycloak
```

## 실행 절차

### 1단계: 대상 엔드포인트 분석

마이그레이션 대상 엔드포인트를 B2C에서 찾아 현재 구현 분석:

```bash
# B2C에서 대상 엔드포인트 찾기
grep -rn "대상_경로" ~/Workspace/maxai-b2c-backend/application/controllers/
grep -rn "대상_경로" ~/Workspace/maxai-b2c-backend/application/config/routes.php
```

확인 항목:
- 현재 인증 방식 (세션? 토큰? 없음?)
- 요청/응답 형식
- DB 접근 (T_Member 등)
- 외부 서비스 호출

### 2단계: Identity Hub 대응 API 확인

```bash
# Identity Hub에 대응 API가 이미 있는지 확인
grep -rn "관련_경로" ~/Workspace/identity-hub/app/api/
```

| 상황 | 액션 |
|------|------|
| Identity Hub에 대응 API 있음 | B2C에서 호출 전환만 |
| Identity Hub에 대응 API 없음 | Identity Hub에 새 API 추가 필요 |
| 부분 대응 | Identity Hub API 확장 필요 |

### 3단계: B2C 측 수정

AUTH_MODE 분기 패턴 적용:

```php
// 표준 마이그레이션 패턴
if ($this->config->item('AUTH_MODE') === 'sso') {
    // SSO 경로: Identity Hub API 호출
    $response = $this->identity_hub->call('대상_API');
} else {
    // 레거시 경로: 기존 로직 유지
    $response = $this->legacy_method();
}
```

### 4단계: 테스트 체크리스트

| 항목 | AUTH_MODE=legacy | AUTH_MODE=sso |
|------|-----------------|--------------|
| 정상 요청 | ✅ 기존 동작 유지 | ✅ SSO 경유 동작 |
| 인증 실패 | ✅ 기존 에러 | ✅ SSO 에러 전파 |
| Identity Hub 장애 | N/A | ✅ 폴백 동작 확인 |
| 응답 형식 | ✅ 동일 | ✅ 동일 (하위호환) |

### 5단계: 교차 검증

`/cross-check` 스킬 호출하여 다른 프로젝트 영향 확인.

### 6단계: 결과 보고

```
## 엔드포인트 마이그레이션 결과

**대상**: [엔드포인트 경로]
**방식**: [AUTH_MODE 분기 / 완전 전환]

### 변경 파일
| 프로젝트 | 파일 | 변경 내용 |
|----------|------|----------|
| B2C Backend | [파일] | [변경 내용] |
| Identity Hub | [파일] | [변경 내용 또는 "변경 없음"] |

### 하위호환성
- 레거시 모드 동작: [확인됨/미확인]
- SSO 모드 동작: [확인됨/미확인]
- 응답 형식 호환: [유지됨/변경됨]

### 폴백 시나리오
- Identity Hub 502/503/504 시: [폴백 동작 설명]
```

## 규칙

- 레거시 코드 삭제 금지 — AUTH_MODE 분기로 공존
- 응답 형식 하위호환 필수 (프론트엔드 깨지면 안 됨)
- Identity Hub API 추가 시 반드시 파이프라인 실행
