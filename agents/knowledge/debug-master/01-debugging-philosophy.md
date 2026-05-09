# 디버깅 철학

> 슬로건: 추측하지 말고 증명하라.

---

## 1. 디버깅의 목적

디버깅은 코드를 고치는 행위가 아니라, 관찰된 현상과 실제 원인 사이의 거리를 줄이는 과정이다.
증거가 부족한 상태에서 수정하면 문제는 사라진 것처럼 보일 수 있지만, 원인은 그대로 남아 다음 장애로 돌아온다.

좋은 디버깅은 다음 질문에 답한다.

- [ ] 사용자가 본 증상이 무엇인가?
- [ ] 같은 증상을 내가 재현할 수 있는가?
- [ ] 실패 시점의 입력, 상태, 환경을 확보했는가?
- [ ] 원인을 설명하는 가설이 검증 가능한가?
- [ ] 수정이 원인을 제거한다는 증거가 있는가?
- [ ] 회귀 테스트가 같은 문제의 재발을 막는가?

---

## 2. 핵심 원칙

| 원칙 | 의미 | 금지 행동 |
|------|------|-----------|
| 증거 우선 | 로그, 재현, 계측으로 판단 | 느낌으로 코드 수정 |
| 한 번에 하나 | 변수를 하나씩 바꿔 원인 분리 | 여러 수정 동시 적용 |
| 계층 분리 | 네트워크, DB, 로직, 설정을 나눠 확인 | 전 계층을 한 번에 의심 |
| 재현 가능성 | 성공/실패 조건을 반복 확인 | 우연히 통과하면 완료 |
| 기록 유지 | 명령, 결과, 가설을 남김 | 기억에 의존 |

---

## 3. 7단계 프로세스

```
REPRODUCE  →  COLLECT  →  NARROW  →  HYPOTHESIZE  →  VERIFY  →  FIX  →  CONFIRM
재현           수집         범위축소       가설             검증        수정      확인
```

각 단계의 산출물은 명확해야 한다.

| 단계 | 산출물 | 실패 기준 |
|------|--------|-----------|
| REPRODUCE | 재현 명령, 입력값, 기대/실제 결과 | 증상을 설명만 함 |
| COLLECT | 로그, 스택트레이스, 메트릭, 환경 정보 | 단일 스크린샷만 있음 |
| NARROW | 의심 레이어와 제외된 레이어 | 전부 가능성 있음 |
| HYPOTHESIZE | 검증 가능한 원인 문장 | "아마 캐시 문제" |
| VERIFY | 가설을 지지/반박하는 실험 결과 | 코드부터 수정 |
| FIX | 원인에 닿는 최소 변경 | 주변 리팩터 동반 |
| CONFIRM | 재현 케이스 통과, 회귀 테스트 | 로컬 한 번 성공 |

---

## 4. 추측 수정의 비용

추측 수정은 빠르게 보이지만 총 비용이 높다.

```
추측 수정 비용
├── 원인 미해결: 같은 장애 반복
├── 부작용 증가: 불필요한 변경으로 새 버그 생성
├── 지식 손실: 팀이 원인을 학습하지 못함
├── 리뷰 난이도 상승: 왜 바꿨는지 설명 불가
└── 신뢰 하락: "고쳤다"의 의미가 약해짐
```

예를 들어 로그인 실패가 발생했을 때 `timeout`을 5초에서 30초로 늘리는 수정은 증상을 늦출 뿐이다.
네트워크 지연, DB lock, 외부 인증 서버 응답, 토큰 검증 로직 중 어디가 느린지 먼저 증명해야 한다.

---

## 5. 좋은 디버깅 기록

```markdown
## 증상
- 2026-05-09 10:42 KST, `/api/orders` 500 증가
- 요청 `traceId=2f6c...` 에서 재현

## 재현
```bash
curl -sS -X POST http://localhost:3000/api/orders \
    -H 'content-type: application/json' \
    -d '{"userId":"u-1","items":[{"productId":"p-1","quantity":2}]}'
```

## 관찰
- API 로그: `inventory.reserve.failed`
- DB 로그: `deadlock detected`
- Redis 정상, 외부 결제 호출 전 실패

## 가설
- 주문 생성 트랜잭션과 재고 예약 트랜잭션의 row lock 순서가 반대다.

## 검증
- 두 요청을 병렬 실행하면 8/20회 deadlock 재현
- lock 순서 통일 패치 후 0/100회
```

---

## 6. 증거 수준

| 수준 | 예시 | 사용 가능 여부 |
|------|------|---------------|
| L0 느낌 | "최근 캐시를 바꿨으니 캐시 같음" | 금지 |
| L1 정황 | 특정 배포 이후 증가 | 가설 수립에만 사용 |
| L2 관찰 | 로그와 메트릭에서 실패 지점 확인 | 범위 축소 가능 |
| L3 재현 | 같은 입력으로 반복 실패 | 수정 전 필수 |
| L4 반증 | 조건 변경 시 실패가 사라짐 | 원인 주장 가능 |
| L5 회귀 테스트 | 자동화된 실패/성공 증명 | 완료 기준 |

---

## 7. 실전 로그 계측

```typescript
type DebugContext = {
    traceId: string;
    userId?: string;
    orderId?: string;
    phase: 'start' | 'validate' | 'persist' | 'publish' | 'done';
};

function debugEvent(context: DebugContext, extra: Record<string, unknown> = {}) {
    console.info(JSON.stringify({
        event: 'order.debug',
        timestamp: new Date().toISOString(),
        ...context,
        ...extra,
    }));
}

debugEvent({ traceId, userId, phase: 'validate' }, {
    itemCount: items.length,
    hasCoupon: Boolean(couponId),
});
```

```python
import logging
import time

logger = logging.getLogger("debug")

def measure_step(trace_id: str, step: str, func):
    started = time.perf_counter()
    try:
        return func()
    finally:
        logger.info(
            "debug.step",
            extra={
                "trace_id": trace_id,
                "step": step,
                "duration_ms": round((time.perf_counter() - started) * 1000, 2),
            },
        )
```

---

## 8. 디버깅 중 변경 규칙

- [ ] 재현 전 코드를 수정하지 않는다.
- [ ] 수정 전 현재 실패를 테스트나 스크립트로 고정한다.
- [ ] 한 번에 하나의 가설만 검증한다.
- [ ] 로그 추가와 로직 수정은 커밋 또는 diff에서 분리한다.
- [ ] 관찰용 로그는 운영 노출 범위와 개인정보를 검토한다.
- [ ] 임시 계측은 제거하거나 명시적으로 유지 이유를 남긴다.

---

## 9. 판단 문장 템플릿

나쁜 문장:

- 캐시 문제 같습니다.
- 타이밍 이슈라 timeout을 늘렸습니다.
- 로컬에서는 됩니다.

좋은 문장:

- `traceId=abc` 요청에서 Redis hit 후 DB update 이전에 실패합니다.
- 동시 요청 20개 실행 시 `users.id=42` row lock 대기 시간이 5초를 초과합니다.
- `FEATURE_NEW_PRICE=false` 에서는 실패하지 않고 `true` 에서만 실패합니다.

---

## 10. 완료 기준

디버깅 완료는 "에러가 안 보임"이 아니다.

- [ ] 원인 문장이 단일하게 설명된다.
- [ ] 원인을 지지하는 로그, 메트릭, 재현 결과가 있다.
- [ ] 수정은 원인에 직접 연결된다.
- [ ] 기존 재현 스크립트가 통과한다.
- [ ] 회귀 테스트가 추가되거나 기존 테스트로 증명된다.
- [ ] 운영 이슈라면 배포/롤백/모니터링 기준이 정해졌다.
