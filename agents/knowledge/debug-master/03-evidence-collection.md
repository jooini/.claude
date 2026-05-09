# 증거 수집

> Phase 2: COLLECT. 수집하지 않은 정보는 기억이 아니라 추측이다.

---

## 1. 수집의 목적

증거 수집은 실패 순간의 입력, 상태, 경로, 리소스를 보존하는 단계다.
이 단계에서 누락된 정보는 이후 가설을 약하게 만들고, 같은 질문을 반복하게 만든다.

기본 수집 대상은 다음과 같다.

- [ ] 사용자 증상과 발생 시각
- [ ] trace id, request id, correlation id
- [ ] 애플리케이션 로그
- [ ] 스택트레이스
- [ ] 메트릭과 리소스 사용량
- [ ] 배포 버전과 설정
- [ ] DB 상태와 쿼리
- [ ] 외부 의존성 응답

---

## 2. 수집 우선순위

| 우선순위 | 증거 | 이유 |
|----------|------|------|
| P0 | 실패 요청의 trace id | 모든 로그 연결점 |
| P0 | 에러 스택트레이스 | 실패 코드 위치 |
| P1 | 입력 payload | 재현과 데이터 패턴 확인 |
| P1 | 최근 배포/설정 변경 | 시간 축 상관관계 |
| P2 | CPU, 메모리, 커넥션 | 리소스 병목 확인 |
| P2 | 외부 API 응답 | 다운스트림 원인 확인 |

---

## 3. 로그 수집

```bash
TRACE_ID="${TRACE_ID:?TRACE_ID is required}"
LOG_FILE="${LOG_FILE:-./logs/app.log}"

rg "$TRACE_ID" "$LOG_FILE" -n -C 3
```

컨테이너 환경에서는 시간 범위를 좁혀 수집한다.

```bash
docker compose logs api \
    --since "2026-05-09T10:30:00+09:00" \
    --until "2026-05-09T10:45:00+09:00" \
    | rg "traceId=2f6c|order.create|ERROR"
```

로그를 수집할 때는 원본 순서를 유지한다.
필터링된 로그만 보면 실패 직전의 경고를 놓칠 수 있다.

---

## 4. 구조화 로그 필드

| 필드 | 예시 | 용도 |
|------|------|------|
| `timestamp` | `2026-05-09T01:30:00Z` | 시간순 정렬 |
| `level` | `error` | 심각도 필터 |
| `event` | `payment.authorize.failed` | 이벤트 분류 |
| `traceId` | `abc-123` | 요청 연결 |
| `userId` | `user-42` | 영향 사용자 |
| `durationMs` | `832` | 지연 분석 |
| `error.name` | `TimeoutError` | 예외 분류 |
| `error.stack` | stack text | 코드 위치 |

```typescript
logger.error({
    event: 'payment.authorize.failed',
    traceId: request.traceId,
    userId: request.user.id,
    orderId,
    provider: 'stripe',
    durationMs: Date.now() - startedAt,
    error: {
        name: error.name,
        message: error.message,
        stack: error.stack,
    },
});
```

---

## 5. 스택트레이스 보존

스택트레이스는 줄바꿈과 원본 프레임 순서가 중요하다.
로그 시스템에서 한 줄로 접히면 읽기 어렵기 때문에 JSON 필드 또는 첨부 파일로 보존한다.

```python
import logging

logger = logging.getLogger(__name__)

def process_order(order_id: str) -> None:
    try:
        reserve_inventory(order_id)
    except Exception:
        logger.exception(
            "order.reserve.failed",
            extra={"order_id": order_id},
        )
        raise
```

`logger.exception`은 현재 예외의 traceback을 자동으로 포함한다.
예외를 새로 던질 때 원인 체인을 끊지 않는다.

---

## 6. 시스템 상태 수집

```bash
date -Is
uname -a
uptime
df -h
free -m 2>/dev/null || vm_stat
ps aux | sort -nrk 3 | head -20
ps aux | sort -nrk 4 | head -20
```

Mac, Linux, 컨테이너마다 명령이 다를 수 있다.
명령 실패 자체도 환경 단서가 될 수 있으므로 출력과 에러를 함께 보관한다.

---

## 7. 네트워크와 외부 의존성

```bash
curl -sv --max-time 5 https://api.example.com/health \
    -H "x-debug-trace-id: dependency-check-001" \
    -o /tmp/dependency-health.json

cat /tmp/dependency-health.json | jq .
```

확인할 항목:

- [ ] DNS 해석 시간
- [ ] TCP 연결 시간
- [ ] TLS handshake
- [ ] HTTP status
- [ ] 응답 body의 error code
- [ ] timeout 위치

---

## 8. DB 증거 수집

```sql
SELECT now(), version();

SELECT pid, usename, state, wait_event_type, wait_event, query
FROM pg_stat_activity
WHERE state <> 'idle'
ORDER BY query_start;

SELECT relation::regclass, mode, granted, pid
FROM pg_locks
WHERE NOT granted OR mode LIKE '%Exclusive%'
ORDER BY pid;
```

DB 상태는 시간이 지나면 사라진다.
장애 중에는 스냅샷을 먼저 남기고, 분석은 그 다음에 한다.

---

## 9. 수집 기록 템플릿

```markdown
## Evidence Snapshot
- incident: login-500-2026-05-09
- collected_at: 2026-05-09T10:43:00+09:00
- collector: debug-master
- trace_id: 2f6c8a

## Files
- logs/api-2f6c8a.log
- db/pg-stat-activity.txt
- metrics/login-dashboard.png
- payload/request.json

## Notes
- failure starts after `auth.callback.received`
- no call to `token.exchange.done`
- Redis latency normal
```

---

## 10. 개인정보와 보안

증거 수집은 운영 데이터를 다루므로 노출 범위를 제한한다.

- [ ] 토큰, 세션, 쿠키는 마스킹한다.
- [ ] 이메일, 전화번호, 주소는 재현에 필요할 때만 해시 처리한다.
- [ ] 결제 정보는 원본 저장 금지.
- [ ] 로그 파일 공유 범위를 제한한다.
- [ ] 임시 파일 삭제 기준을 남긴다.

```bash
sed -E \
    -e 's/(Authorization: Bearer )[A-Za-z0-9._-]+/\1***REDACTED***/g' \
    -e 's/[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+/***EMAIL***/g' \
    /tmp/raw.log > /tmp/redacted.log
```

---

## 11. 수집 완료 기준

- [ ] 실패 요청을 식별할 수 있다.
- [ ] 실패 시점 전후의 로그가 있다.
- [ ] 스택트레이스 또는 에러 코드가 있다.
- [ ] 환경과 버전이 기록되었다.
- [ ] 리소스와 외부 의존성 상태가 있다.
- [ ] 민감정보가 마스킹되었다.
