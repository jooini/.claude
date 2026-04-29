# 코드 리뷰 프로세스

> 참조 링크: https://google.github.io/eng-practices/review/, https://docs.github.com/en/pull-requests/collaborating-with-pull-requests/reviewing-changes-in-pull-requests

---

## 개요

효과적인 코드 리뷰는 범위 설정, 우선순위 결정, 시간 관리, 체계적인 단계를 따른다. 리뷰어는 코드 품질의 게이트키퍼이자, 팀 지식 공유의 촉매 역할을 한다.

## 1. 리뷰 범위 설정

### 변경 크기에 따른 접근

```typescript
// 리뷰 범위 분류
interface ReviewScope {
  size: 'small' | 'medium' | 'large' | 'xl';
  linesChanged: number;
  estimatedTime: string;
  strategy: string;
}

const reviewScopeGuide: ReviewScope[] = [
  { size: 'small', linesChanged: 50, estimatedTime: '10분', strategy: '전체 읽기' },
  { size: 'medium', linesChanged: 200, estimatedTime: '30분', strategy: '핵심 로직 → 주변 코드' },
  { size: 'large', linesChanged: 500, estimatedTime: '1시간', strategy: '아키텍처 → 핵심 → 세부' },
  { size: 'xl', linesChanged: 1000, estimatedTime: '분할 요청', strategy: 'PR 분할 권고' },
];
```

### 리뷰 범위 체크리스트

- [ ] PR 설명과 관련 이슈를 먼저 읽었는가?
- [ ] 변경의 목적과 컨텍스트를 이해했는가?
- [ ] 변경 범위가 PR 제목/설명과 일치하는가?
- [ ] 범위 밖의 변경(리팩토링, 스타일 변경)이 섞여 있지 않은가?

## 2. 리뷰 우선순위

### 심각도 기반 우선순위

```
P0 — 즉시 수정 (블로커)
├── 보안 취약점 (인젝션, 인증 우회)
├── 데이터 손실 가능성
├── 프로덕션 장애 유발 가능
└── 레이스 컨디션, 데드락

P1 — 머지 전 수정 필수
├── 버그 (로직 에러, null 미처리)
├── 성능 문제 (N+1, 메모리 누수)
├── 에러 처리 누락
└── 테스트 미비

P2 — 권장 수정
├── 가독성 개선
├── 네이밍 개선
├── 중복 코드
└── 불필요한 복잡도

P3 — 선택 사항 (Nit)
├── 코드 스타일
├── 주석 개선
├── 대안 제안
└── 개인 선호
```

### 리뷰 코멘트 접두어 규칙

```typescript
// ✅ 심각도가 명확한 코멘트
// [P0] SQL Injection 취약점. 파라미터 바인딩 필수
// [P1] null 체크 누락으로 런타임 에러 발생 가능
// [P2] 이 함수명이 동작을 더 잘 설명할 것 같아요
// [Nit] 여기 빈 줄 하나 추가하면 가독성 좋아질 것 같아요
// [Q] 이 부분 의도가 궁금합니다 — 일부러 이렇게 한 건가요?

// ❌ 심각도 불명확한 코멘트
// 이거 고치세요
// 왜 이렇게 했어요?
```

## 3. 시간 관리

### 리뷰 시간 기준

```
목표: PR 제출 후 24시간(영업일) 이내 첫 리뷰
이상적: 4시간 이내

집중 리뷰 시간: 한 번에 60분 이내
├── 60분 초과 시 집중력 급락
├── 대형 PR은 여러 세션으로 분할
└── 리뷰 사이 최소 10분 휴식

하루 리뷰 시간: 총 2시간 이내 권장
├── 오전: 복잡한 로직 리뷰
└── 오후: 간단한 리뷰, 후속 확인
```

### 효율적인 리뷰 순서

```typescript
// 1단계: 맥락 파악 (5분)
// - PR 설명, 관련 이슈, 디자인 문서 읽기
// - 변경 파일 목록 훑어보기

// 2단계: 아키텍처 수준 검토 (10분)
// - 파일 구조, 의존성 방향 확인
// - 새로운 모듈/패턴 도입 여부

// 3단계: 핵심 로직 검토 (20분)
// - 비즈니스 로직 정확성
// - 엣지 케이스 처리
// - 에러 처리

// 4단계: 세부 사항 (10분)
// - 네이밍, 가독성
// - 테스트 커버리지
// - 문서 업데이트
```

## 4. 리뷰 단계별 상세

### 4.1 사전 검토 (Pre-Review)

```typescript
// ✅ 사전 검토 체크리스트
interface PreReviewChecklist {
  ciPassed: boolean;        // CI/CD 파이프라인 통과 여부
  conflictsResolved: boolean; // 머지 충돌 해결 여부
  prDescriptionExists: boolean; // PR 설명 작성 여부
  linkedIssue: boolean;     // 관련 이슈 연결 여부
  selfReviewed: boolean;    // 작성자 셀프 리뷰 여부
}

// CI 실패 상태에서 리뷰 시작하지 않기
// — 빌드 에러, 린트 에러는 자동화로 잡아야 한다
```

### 4.2 구조 검토 (Structural Review)

```typescript
// ✅ 구조 리뷰 관점
// - 파일이 올바른 디렉토리에 위치하는가?
// - 모듈 간 의존성 방향이 올바른가?
// - 순환 참조가 발생하지 않는가?

// ❌ 잘못된 의존성 방향
// presentation → domain → infrastructure (올바름)
// domain → infrastructure (위반)
import { UserRepository } from '../infrastructure/user.repository'; // domain 레이어에서

// ✅ 올바른 의존성 방향
import { IUserRepository } from './ports/user-repository.interface'; // 인터페이스 의존
```

### 4.3 로직 검토 (Logic Review)

```typescript
// ✅ 로직 리뷰 핵심 질문
// 1. 이 코드가 요구사항을 정확히 구현하는가?
// 2. 엣지 케이스를 처리하는가?
// 3. 실패 시나리오에서 어떻게 동작하는가?
// 4. 동시성 문제가 있는가?

// 예시: 할인 계산 로직 리뷰
function calculateDiscount(price: number, discountPercent: number): number {
  return price * (discountPercent / 100); // 리뷰 포인트:
  // [P1] price가 음수이면? discountPercent가 100 초과이면?
  // [P1] 부동소수점 계산 — 금액은 정수(원 단위)로 처리해야
  // [P2] 반환값이 음수가 될 수 있음 — Math.max(0, result) 필요
}

// ✅ 개선된 버전
function calculateDiscount(price: number, discountPercent: number): number {
  if (price < 0) throw new Error('Price must be non-negative');
  const clampedDiscount = Math.min(Math.max(discountPercent, 0), 100);
  const discountAmount = Math.floor(price * clampedDiscount / 100); // 정수 연산
  return Math.max(0, discountAmount);
}
```

### 4.4 테스트 검토 (Test Review)

```typescript
// ✅ 테스트 리뷰 관점
// - 변경된 로직에 대한 테스트가 있는가?
// - Happy path만 테스트하고 있지 않은가?
// - 경계값 테스트가 있는가?
// - 테스트가 구현 세부사항에 의존하지 않는가?

// ❌ 구현 세부사항에 의존하는 테스트
it('should call repository.save', async () => {
  await service.createUser(dto);
  expect(mockRepository.save).toHaveBeenCalledTimes(1); // 내부 구현에 결합
});

// ✅ 행동 기반 테스트
it('should create user and return with id', async () => {
  const result = await service.createUser(dto);
  expect(result.id).toBeDefined();
  expect(result.email).toBe(dto.email);
});
```

## 5. 리뷰 완료 기준

### 승인(Approve) 조건

```
모든 P0, P1 이슈가 해결됨
├── 보안 취약점 없음
├── 명확한 버그 없음
├── 테스트 커버리지 충분
└── CI 통과

P2 이슈는 후속 작업으로 추적 가능
Nit은 작성자 재량에 맡김
```

### 리뷰 결과 분류

```typescript
type ReviewDecision =
  | 'approve'              // 즉시 머지 가능
  | 'approve_with_nits'    // Nit 수정 후 머지 (재리뷰 불필요)
  | 'request_changes'      // 수정 후 재리뷰 필요
  | 'needs_discussion';    // 설계 논의 필요 — 동기식 미팅 권장
```

## 6. 리뷰어 관점 종합 체크리스트

- [ ] PR 설명과 관련 이슈를 읽었는가?
- [ ] CI가 통과했는가?
- [ ] 보안 취약점이 없는가? (P0)
- [ ] 데이터 손실 가능성이 없는가? (P0)
- [ ] 로직 에러가 없는가? (P1)
- [ ] 에러 처리가 적절한가? (P1)
- [ ] 테스트가 충분한가? (P1)
- [ ] 성능 문제가 없는가? (P1)
- [ ] 가독성이 양호한가? (P2)
- [ ] 네이밍이 명확한가? (P2)
- [ ] 아키텍처 원칙을 준수하는가? (P2)
- [ ] 코멘트에 심각도를 표시했는가?
- [ ] 건설적인 톤으로 작성했는가?
