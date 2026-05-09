# Test Report Format

---

## 1. 검증 리포트 구조

코드 변경 후 검증 결과를 구조화하여 보고한다.

### 전체 구조

```markdown
# 검증 리포트

## 요약
| 항목 | 결과 | 새 이슈 | 기존 이슈 |
|------|------|---------|----------|
| 린트 | ✅ PASS | 0 | 3 |
| 타입 체크 | ❌ FAIL | 2 | 1 |
| 빌드 | ✅ PASS | - | - |
| 테스트 | ⚠️ WARN | 1 | 0 |

**판정: ❌ 수정 필요** (새로 도입된 이슈 3건)

---

## 상세

### 타입 체크 (tsc --noEmit)
#### 🆕 새 에러 (2건)
1. `src/user.service.ts:45` — TS2322: Type 'string' is not assignable to type 'number'
   - 변경 라인에서 발생
   - 수정 제안: `parseInt(value)` 또는 타입 변경

2. `src/user.dto.ts:12` — TS2345: Argument of type 'X' is not assignable
   - user.service.ts 변경의 파생 에러
   - 수정 제안: DTO 타입 업데이트

#### ⚠️ 기존 에러 (1건, 참고)
- `src/legacy.ts:89` — TS7006: Parameter implicitly has 'any' type

### 테스트 (jest)
#### 🆕 실패 (1건)
1. `tests/user.spec.ts` > UserService > should create user
   - Expected: 201, Received: 400
   - 원인: validation 로직 변경으로 기존 테스트 데이터 불합치
   - 수정 제안: 테스트 데이터에 필수 필드 추가

#### ✅ 통과
- 142 passed, 1 failed, 0 skipped
- 커버리지: 85.2% (변경 파일: 92.0%)
```

## 2. 판정 기준

### 자동 판정 규칙

| 조건 | 판정 |
|------|------|
| 새 에러 0건 | ✅ PASS |
| 새 경고만 존재 | ⚠️ WARN (참고) |
| 새 에러 존재 (린트) | ❌ FAIL |
| 새 에러 존재 (타입) | ❌ FAIL |
| 빌드 실패 | ❌ FAIL (최우선) |
| 테스트 실패 (새 코드 관련) | ❌ FAIL |
| 테스트 실패 (기존 코드) | ⚠️ WARN (기존 이슈) |

### 심각도 분류

| 심각도 | 설명 | 예시 |
|--------|------|------|
| 🔴 Critical | 빌드 실패 또는 런타임 에러 가능 | 타입 에러, import 누락 |
| 🟡 Major | 잠재적 버그 또는 품질 저하 | 미처리 Promise, null 체크 누락 |
| 🟢 Minor | 스타일 또는 경미한 이슈 | 네이밍, 미사용 변수 |
| ⚪ Info | 참고 사항 | 기존 에러, 커버리지 변화 |

## 3. 항목별 리포트 형식

### 린트 리포트

```markdown
### 린트 (ESLint)
- 실행 명령: `npx eslint src/ --format json`
- 검사 파일: 15개
- 규칙 위반: 5건 (새: 2, 기존: 3)

| 심각도 | 파일 | 라인 | 규칙 | 메시지 | 신규 |
|--------|------|------|------|--------|------|
| 🔴 | user.service.ts | 23 | no-floating-promises | Promise returned but not awaited | 🆕 |
| 🟡 | user.controller.ts | 45 | no-explicit-any | Unexpected any | 🆕 |
| ⚪ | legacy.ts | 12 | no-console | Unexpected console statement | 기존 |
```

### 타입 체크 리포트

```markdown
### 타입 체크 (tsc)
- 실행 명령: `npx tsc --noEmit`
- 에러: 3건 (새: 2, 기존: 1)

| 코드 | 파일 | 라인 | 메시지 | 신규 |
|------|------|------|--------|------|
| TS2322 | user.service.ts | 45 | Type 'string' not assignable to 'number' | 🆕 |
| TS2345 | user.dto.ts | 12 | Argument type mismatch | 🆕 |
| TS7006 | legacy.ts | 89 | Implicit 'any' | 기존 |
```

### 테스트 리포트

```markdown
### 테스트 (Jest)
- 실행 명령: `npx jest --coverage`
- 결과: 141 passed / 1 failed / 2 skipped
- 실행 시간: 12.3s
- 커버리지: Lines 85.2% | Branches 78.1% | Functions 90.0%

#### 실패 테스트
1. **UserService > should create user** 🆕
   ```
   Expected: 201
   Received: 400

   at Object.<anonymous> (tests/user.spec.ts:45:5)
   ```
   관련 변경: `src/user.service.ts:23-30`

#### 커버리지 변화
| 파일 | 이전 | 현재 | 변화 |
|------|------|------|------|
| user.service.ts | 82% | 92% | +10% ✅ |
| user.controller.ts | 75% | 70% | -5% ⚠️ |
```

### 빌드 리포트

```markdown
### 빌드 (next build)
- 실행 명령: `npx next build`
- 결과: ✅ 성공
- 빌드 시간: 45.2s
- 페이지: 12 static / 5 dynamic

#### 번들 크기 변화
| 페이지 | 이전 | 현재 | 변화 |
|--------|------|------|------|
| /users | 85kB | 87kB | +2kB |
| /api/users | 0B | 0B | - |
```

## 4. 요약 한 줄

리포트 맨 앞에 한 줄 요약을 둔다:

```
✅ 모든 검증 통과 — 린트(0), 타입(0), 빌드(OK), 테스트(142/142)
❌ 수정 필요 — 타입 에러 2건, 테스트 실패 1건 (모두 새로 도입)
⚠️ 기존 이슈 참고 — 새 이슈 없음, 기존 린트 경고 3건 존재
```

## 5. 자동 수정 제안

```markdown
## 자동 수정 가능 항목

다음 이슈는 자동 수정이 가능합니다:

| # | 파일 | 이슈 | 자동 수정 명령 |
|---|------|------|--------------|
| 1 | user.controller.ts:3 | 미사용 import | `eslint --fix` |
| 2 | user.service.ts:10 | import 순서 | `eslint --fix` |

자동 수정을 적용하시겠습니까?
```
