# Flaky Test Detection

---

## 1. Flaky 테스트란

동일한 코드에서 **실행할 때마다 결과가 달라지는** 테스트. 통과/실패가 비결정적이다.

## 2. 주요 원인

### 시간 의존성

```typescript
// ❌ 현재 시각에 의존
it('should be valid', () => {
  const token = createToken({ expiresIn: '1h' });
  expect(isValid(token)).toBe(true);
  // 자정 직전에 실행하면 실패할 수 있음
});

// ✅ 시간을 고정
it('should be valid', () => {
  jest.useFakeTimers();
  jest.setSystemTime(new Date('2024-01-15T12:00:00Z'));
  const token = createToken({ expiresIn: '1h' });
  expect(isValid(token)).toBe(true);
  jest.useRealTimers();
});
```

### 순서 의존성

```typescript
// ❌ 테스트 A가 먼저 실행되어야 B가 통과
describe('UserService', () => {
  it('A: should create user', async () => {
    await service.create({ name: 'John' }); // DB에 데이터 삽입
  });
  it('B: should find user', async () => {
    const user = await service.findByName('John'); // A에서 삽입한 데이터 의존
    expect(user).toBeDefined();
  });
});

// ✅ 각 테스트가 독립적
describe('UserService', () => {
  beforeEach(async () => {
    await db.clean(); // 매 테스트 전 초기화
  });
  it('should find user', async () => {
    await service.create({ name: 'John' }); // 자체적으로 데이터 준비
    const user = await service.findByName('John');
    expect(user).toBeDefined();
  });
});
```

### 비동기 타이밍

```typescript
// ❌ setTimeout에 의존
it('should debounce', () => {
  const fn = jest.fn();
  const debounced = debounce(fn, 100);
  debounced();
  setTimeout(() => {
    expect(fn).toHaveBeenCalled(); // 타이밍에 따라 실패
  }, 150);
});

// ✅ fake timer 사용
it('should debounce', () => {
  jest.useFakeTimers();
  const fn = jest.fn();
  const debounced = debounce(fn, 100);
  debounced();
  jest.advanceTimersByTime(100);
  expect(fn).toHaveBeenCalled();
  jest.useRealTimers();
});
```

### 외부 서비스 의존

```typescript
// ❌ 실제 API 호출
it('should fetch weather', async () => {
  const result = await fetchWeather('Seoul');
  expect(result.temp).toBeGreaterThan(-50); // API 다운 시 실패
});

// ✅ Mock 사용
it('should fetch weather', async () => {
  jest.spyOn(httpClient, 'get').mockResolvedValue({ temp: 22 });
  const result = await fetchWeather('Seoul');
  expect(result.temp).toBe(22);
});
```

### 공유 상태

```typescript
// ❌ 전역 변수 공유
let counter = 0;
it('test 1', () => { counter++; expect(counter).toBe(1); });
it('test 2', () => { counter++; expect(counter).toBe(2); }); // 실행 순서에 의존

// ✅ 각 테스트에서 초기화
let counter: number;
beforeEach(() => { counter = 0; });
it('test 1', () => { counter++; expect(counter).toBe(1); });
it('test 2', () => { counter++; expect(counter).toBe(1); });
```

### 랜덤/비결정적 데이터

```typescript
// ❌ 랜덤 데이터에 의존
it('should sort', () => {
  const arr = Array.from({ length: 10 }, () => Math.random());
  // 특정 패턴에서만 실패할 수 있음
});

// ✅ 시드 고정 또는 고정 데이터
it('should sort', () => {
  const arr = [3, 1, 4, 1, 5, 9, 2, 6];
  const sorted = mySort(arr);
  expect(sorted).toEqual([1, 1, 2, 3, 4, 5, 6, 9]);
});
```

## 3. 감지 방법

### 반복 실행

```bash
# Jest — 같은 테스트 N번 반복
npx jest --testPathPattern="user" --repeat=10

# Vitest
npx vitest run --repeat=10

# pytest — pytest-repeat
pytest --count=10

# Go
go test -count=10 ./...

# 스크립트로 반복
for i in $(seq 1 10); do npx jest 2>&1 | tail -1; done
```

### CI 이력 분석

```bash
# GitHub Actions 실패 이력에서 flaky 패턴
# - 같은 커밋에서 성공/실패가 섞여 있으면 flaky
# - 재실행 시 통과하면 flaky

# Jest JSON 출력으로 실패 테스트 수집
npx jest --json | jq '.testResults[] | select(.status == "failed") | .name'
```

## 4. 격리 전략

### 테스트 격리 체크리스트

- [ ] 각 테스트가 `beforeEach`/`afterEach`로 상태 초기화
- [ ] DB 테스트는 트랜잭션 롤백 또는 테이블 클리어
- [ ] 외부 API는 mock/stub 처리
- [ ] 시간 의존 코드는 fake timer 사용
- [ ] 파일 시스템 작업은 임시 디렉토리 사용
- [ ] 환경 변수는 테스트 내에서 설정/복원
- [ ] 포트 바인딩은 랜덤 포트 사용

### Flaky 테스트 마킹

```typescript
// Jest — 일시적 skip
it.skip('flaky: should handle concurrent requests', () => { ... });

// 또는 마커로 분리
it.todo('fix flaky: timing issue in debounce test');
```

```python
# pytest — flaky 마커
@pytest.mark.flaky(reruns=3, reruns_delay=1)
def test_external_api():
    ...

# 또는 skip
@pytest.mark.skip(reason="flaky: depends on network timing")
def test_websocket():
    ...
```

## 5. 재시도 전략

```yaml
# GitHub Actions — 테스트 재시도
- name: Test with retry
  uses: nick-fields/retry@v3
  with:
    max_attempts: 3
    command: npx jest
```

```bash
# Jest — 재시도 (jest.retryTimes)
# jest.config.ts
{
  retryTimes: 2,  // 실패 시 2번 재시도
}
```

**주의**: 재시도는 임시 방편이다. 근본 원인을 수정하는 것이 우선이다.

## 6. 근본 해결 우선순위

1. **외부 의존성 Mock** — 가장 흔한 원인이므로 최우선
2. **시간 고정** — fake timer 도입
3. **DB 격리** — 트랜잭션 롤백 패턴
4. **순서 독립성** — beforeEach로 상태 초기화
5. **타이밍 제거** — waitFor/polling 대신 이벤트 기반
