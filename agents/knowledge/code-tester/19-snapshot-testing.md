# Snapshot Testing

> 참조 링크: https://jestjs.io/docs/snapshot-testing, https://vitest.dev/guide/snapshot.html

---

## 1. 스냅샷 테스트란

컴포넌트 또는 데이터의 출력을 **파일로 저장**하고, 이후 실행 시 **이전 스냅샷과 비교**하여 변경을 감지한다.

## 2. 기본 사용

### 컴포넌트 스냅샷

```typescript
import { render } from '@testing-library/react';
import { UserCard } from './user-card';

it('should match snapshot', () => {
  const { container } = render(
    <UserCard name="John" email="john@test.com" role="admin" />
  );
  expect(container).toMatchSnapshot();
});
```

생성되는 스냅샷 파일:

```
// __snapshots__/user-card.test.tsx.snap
exports[`should match snapshot 1`] = `
<div>
  <div
    class="user-card"
  >
    <h3>John</h3>
    <p>john@test.com</p>
    <span class="badge">admin</span>
  </div>
</div>
`;
```

### 인라인 스냅샷

파일 대신 테스트 코드 안에 스냅샷을 저장한다.

```typescript
it('should match inline snapshot', () => {
  const result = formatUser({ name: 'John', role: 'admin' });
  expect(result).toMatchInlineSnapshot(`"John (admin)"`);
  // 첫 실행 시 자동으로 값이 채워짐
});
```

### 데이터 스냅샷

UI가 아닌 데이터 구조에도 사용 가능하다.

```typescript
it('should match API response shape', () => {
  const response = buildApiResponse(mockUser);
  expect(response).toMatchSnapshot();
});

it('should match error format', () => {
  const error = formatError(new ValidationError('Invalid email'));
  expect(error).toMatchInlineSnapshot(`
    {
      "code": "VALIDATION_ERROR",
      "message": "Invalid email",
      "status": 400,
    }
  `);
});
```

## 3. 스냅샷 업데이트

```bash
# Jest — 모든 스냅샷 업데이트
npx jest --updateSnapshot
npx jest -u

# Vitest
npx vitest run --update

# 특정 테스트만
npx jest --updateSnapshot --testPathPattern="user-card"
```

### 업데이트 판단 기준

| 상황 | 판단 |
|------|------|
| 의도적 UI 변경 후 스냅샷 불일치 | ✅ 업데이트 |
| 리팩토링 후 출력 동일해야 하는데 불일치 | ❌ 코드 수정 |
| 의존성 업그레이드 후 스냅샷 변경 | ⚠️ 변경 내용 확인 후 판단 |
| CI에서 로컬과 스냅샷 불일치 | ❌ 환경 차이 조사 (줄바꿈, 타임존 등) |

## 4. 남용 방지

### 안티패턴

```typescript
// ❌ 너무 큰 스냅샷 — 변경 시 diff 리뷰가 무의미
it('should render entire page', () => {
  const { container } = render(<DashboardPage />);
  expect(container).toMatchSnapshot(); // 수백 줄 스냅샷
});

// ❌ 동적 데이터 포함 — 매번 스냅샷 변경
it('should match', () => {
  const result = { id: Math.random(), createdAt: new Date() };
  expect(result).toMatchSnapshot(); // 항상 실패
});

// ❌ 스냅샷으로 로직 테스트 대체
it('should calculate total', () => {
  expect(calculateTotal(items)).toMatchSnapshot();
  // 값이 맞는지 사람이 확인해야 함
});
```

### 올바른 사용

```typescript
// ✅ 작은 단위의 스냅샷
it('should render user badge', () => {
  const { container } = render(<Badge role="admin" />);
  expect(container.firstChild).toMatchSnapshot();
});

// ✅ 동적 값 제거
it('should match response shape', () => {
  const response = createResponse(mockData);
  expect(response).toMatchSnapshot({
    id: expect.any(Number),           // 동적 값 무시
    createdAt: expect.any(String),    // 동적 값 무시
  });
});

// ✅ 로직은 명시적 assertion으로
it('should calculate total', () => {
  expect(calculateTotal(items)).toBe(150);
});
```

## 5. 스냅샷 관리

### 사용되지 않는 스냅샷 정리

```bash
# Jest — 사용되지 않는 스냅샷 제거
npx jest --ci  # CI 모드에서 미사용 스냅샷 감지

# 수동 정리
npx jest --updateSnapshot  # 사용되지 않는 것 자동 제거
```

### 스냅샷 파일 구조

```
src/
├── components/
│   ├── user-card.tsx
│   ├── user-card.test.tsx
│   └── __snapshots__/
│       └── user-card.test.tsx.snap  ← 자동 생성
```

### PR 리뷰 시 스냅샷 확인

- 스냅샷 변경이 PR에 포함되면 **변경 내용을 반드시 리뷰**
- 의도하지 않은 UI 변경이 스냅샷 업데이트로 숨겨질 수 있음
- 큰 스냅샷 변경은 시각적 회귀 테스트(Chromatic 등)로 보완

## 6. 대안: Property-based Snapshot

```typescript
// 전체 HTML 대신 주요 속성만 스냅샷
it('should render correctly', () => {
  const { getByTestId } = render(<UserCard user={mockUser} />);

  expect({
    name: getByTestId('name').textContent,
    email: getByTestId('email').textContent,
    role: getByTestId('role').textContent,
  }).toMatchInlineSnapshot(`
    {
      "email": "john@test.com",
      "name": "John",
      "role": "admin",
    }
  `);
});
```

## 7. 스냅샷 vs 다른 테스트 방식

| 방식 | 장점 | 단점 | 적합한 경우 |
|------|------|------|-----------|
| Snapshot | 빠른 작성, 변경 감지 | 의도 불명확, 과도한 diff | UI 구조, 직렬화 형식 |
| Assertion | 명확한 의도, 정확한 검증 | 작성 시간 | 비즈니스 로직, 계산 |
| Visual (Chromatic) | 실제 렌더링 비교 | 느림, 비용 | 디자인 회귀 |
