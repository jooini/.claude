# Test Design

> 원본: https://ironact.gitbook.io/ironact-docs/CrEhRPJQJpia3xh9iqbi/knowledge-qa/test-design

---

## 1. 테스트 설계란

테스트 목적을 달성하기 위한 테스트 케이스 구조 설계.
좋은 테스트 설계 = 최소한의 테스트로 최대한의 버그 발견.

---

## 2. 블랙박스 vs 화이트박스

```
블랙박스 테스트
  내부 구현 모름, 입력-출력만 확인
  → QA가 주로 담당
  → 사용자 관점

화이트박스 테스트
  내부 구현 알고 있음, 코드 경로 커버
  → 개발자가 주로 담당
  → 코드 커버리지 기반
```

---

## 3. 테스트 설계 기법

### 상태 전이 테스트 (State Transition)

상태가 있는 기능에 효과적.

```
주문 상태 다이어그램:

PENDING ──결제완료──→ PAID ──배송시작──→ SHIPPING
   │                   │                    │
취소                  취소               배송완료
   ↓                   ↓                    ↓
CANCELLED         CANCELLED           DELIVERED

테스트 케이스:
- PENDING → PAID: 결제 성공
- PENDING → CANCELLED: 주문 취소
- PAID → SHIPPING: 배송 시작
- PAID → CANCELLED: 결제 후 취소
- SHIPPING → DELIVERED: 배송 완료
- DELIVERED → CANCELLED: 배송 완료 후 취소 시도 (불가 검증)
```

### 유스케이스 테스트 (Use Case)

실제 사용자 시나리오 기반.

```markdown
유스케이스: 상품 검색 후 구매
액터: 비회원 사용자

메인 시나리오:
1. 검색창에 "노트북" 입력
2. 검색 결과에서 상품 선택
3. 장바구니 추가
4. 로그인 요구 → 로그인
5. 결제 정보 입력
6. 주문 완료

대안 시나리오:
3a. 품절 상품 → "품절" 표시, 장바구니 불가
4a. 회원 로그인 → 로그인 없이 장바구니 유지
5a. 잘못된 카드 → 오류 메시지, 재입력 요청
```

### 페어와이즈 테스트 (Pairwise)

모든 조합 대신 2개씩 조합 커버 → 테스트 수 대폭 감소.

```
파라미터:
OS: Windows, Mac, Linux
브라우저: Chrome, Firefox, Safari
해상도: 1080p, 4K

전체 조합: 3×3×2 = 18개
페어와이즈: 9개로 모든 2-조합 커버

도구: pairwise.js, PICT
```

---

## 4. 탐색적 테스트 (Exploratory Testing)

스크립트 없이 탐험하며 버그 발견. 계획된 테스트가 놓친 것을 잡음.

```markdown
# 탐색적 테스트 세션 차터

목적: 결제 플로우의 엣지 케이스 탐색
시간: 90분
범위: 결제 화면 ~ 주문 완료

탐색 아이디어:
- 결제 도중 뒤로가기
- 동일 상품 여러 탭에서 동시 구매
- 재고 1개 상품을 수량 2개로 구매 시도
- 네트워크 느린 환경 (DevTools throttling)
- 쿠폰 + 포인트 동시 사용
- 이미 사용한 쿠폰 재사용 시도

발견 사항:
[세션 중 실시간 기록]
```

---

## 5. 리스크 기반 테스트 설계

```
1. 리스크 식별
   - 복잡한 비즈니스 로직
   - 자주 변경되는 코드
   - 통합 포인트 (API, DB)
   - 과거 버그 발생 영역

2. 리스크 평가 (발생 확률 × 영향도)

3. 높은 리스크에 더 많은 테스트 케이스
   - P1 리스크: 5~10개 TC
   - P3 리스크: 1~2개 TC

4. 낮은 리스크는 스킵 또는 최소 테스트
```

---

## 6. 테스트 케이스 구조

```markdown
TC-ID: TC-ORDER-015
제목: 재고 초과 수량 주문 시도
우선순위: P1
카테고리: 주문 > 수량 검증
자동화 여부: 자동화 대상

사전 조건:
- 로그인 상태
- 대상 상품 재고 = 3개

입력:
- 상품: 테스트상품A (재고 3개)
- 수량: 5

테스트 단계:
1. 상품 상세 페이지 접근
2. 수량 입력창에 5 입력
3. 장바구니 담기 클릭

기대 결과:
- "재고 부족 (현재 재고: 3개)" 오류 메시지 표시
- 장바구니에 추가되지 않음
- 수량이 3으로 자동 수정 (선택적)

실제 결과: [테스트 시 기입]
Pass/Fail: [ ]
비고:
```

---

## 7. 테스트 데이터 설계

```ts
// 테스트 데이터 카테고리
const testData = {
  // 유효 데이터
  valid: {
    email: 'valid@example.com',
    password: 'Valid1234!',
    amount: 10000,
  },

  // 경계값
  boundary: {
    minAmount: 1,
    maxAmount: 9999999,
    minPasswordLen: 'Ab1!1234',  // 8자
    maxPasswordLen: 'Ab1!'.repeat(25).slice(0, 100),  // 100자
  },

  // 무효 데이터
  invalid: {
    emailNoAt: 'invalidemail',
    emailNoTld: 'test@domain',
    negativeAmount: -1,
    zeroAmount: 0,
  },

  // 특수 케이스
  special: {
    sqlInjection: "' OR '1'='1",
    xss: '<script>alert("xss")</script>',
    unicodeEmail: 'test@한글도메인.kr',
    emojiName: '홍길동🎉',
    longString: 'a'.repeat(1000),
  },
}
```

---

## 8. 안티패턴

- **Happy Path만 설계**: 에러/경계/특수 케이스 필수
- **중복 테스트 케이스**: 같은 것을 다른 방식으로 반복
- **너무 세분화된 TC**: 1개 기능에 100개 TC → 유지보수 불가
- **실행 불가능한 TC**: 사전 조건/환경 미비 → 실행 가능성 확인
- **자동화 고려 없는 설계**: 반복 TC는 자동화 염두에 두고 작성
