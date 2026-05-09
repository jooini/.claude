# 메모리 이슈

> 메모리 문제는 순간 에러보다 추세가 중요하다. 한 장의 스냅샷보다 시간에 따른 증가를 본다.

---

## 1. 대표 증상

메모리 이슈는 OOM으로만 나타나지 않는다.
GC 압박, latency 증가, 프로세스 재시작, swap 사용 증가처럼 간접 증상으로 먼저 나타난다.

신호:

- [ ] RSS가 계속 증가한다.
- [ ] heap used가 요청 이후 내려오지 않는다.
- [ ] GC pause가 길어진다.
- [ ] 컨테이너 OOMKilled가 발생한다.
- [ ] 특정 API 호출 후 메모리가 계단식 증가한다.
- [ ] 파일 디스크립터나 socket이 함께 증가한다.

---

## 2. 메모리 지표 구분

| 지표 | 의미 | 해석 |
|------|------|------|
| RSS | 프로세스가 OS에서 점유한 메모리 | 컨테이너 limit과 비교 |
| Heap used | 런타임 heap 사용량 | 객체 누수 후보 |
| Heap total | 런타임이 확보한 heap | 즉시 반환되지 않을 수 있음 |
| External | native buffer, addon | Node Buffer 누수 |
| GC pause | GC에 소요된 시간 | latency 영향 |
| OOMKilled | 커널/컨테이너 kill | limit 초과 |

---

## 3. Node.js 메모리 계측

```typescript
setInterval(() => {
    const memory = process.memoryUsage();
    console.info({
        event: 'runtime.memory',
        rssMb: Math.round(memory.rss / 1024 / 1024),
        heapUsedMb: Math.round(memory.heapUsed / 1024 / 1024),
        heapTotalMb: Math.round(memory.heapTotal / 1024 / 1024),
        externalMb: Math.round(memory.external / 1024 / 1024),
    });
}, 30_000);
```

```bash
node --trace-gc dist/main.js 2> /tmp/gc.log
rg "Mark-sweep|Scavenge|allocation failure" /tmp/gc.log
```

GC 로그는 개발/스테이징에서 먼저 사용한다.
운영에서는 로그량과 성능 영향을 확인한다.

---

## 4. Python 메모리 계측

```python
import os
import psutil
import tracemalloc

tracemalloc.start()
process = psutil.Process(os.getpid())

def log_memory(label: str):
    current, peak = tracemalloc.get_traced_memory()
    rss = process.memory_info().rss
    print({
        "event": "memory.snapshot",
        "label": label,
        "rss_mb": round(rss / 1024 / 1024, 2),
        "tracemalloc_current_mb": round(current / 1024 / 1024, 2),
        "tracemalloc_peak_mb": round(peak / 1024 / 1024, 2),
    })
```

`tracemalloc`은 Python heap 중심이다.
native extension, numpy, image 처리 메모리는 RSS와 함께 봐야 한다.

---

## 5. OOM 원인 확인

```bash
dmesg | rg -i "killed process|out of memory" -C 3
docker inspect "$CONTAINER_ID" --format '{{.State.OOMKilled}}'
kubectl describe pod "$POD" | rg -i "oom|killed|reason" -C 3
```

OOMKilled가 있으면 애플리케이션 로그에 에러가 남지 않을 수 있다.
프로세스가 죽기 전에 마지막으로 증가한 지표를 찾아야 한다.

---

## 6. 누수 재현

```bash
BASE_URL="${BASE_URL:-http://localhost:3000}"

for i in $(seq 1 500); do
    curl -sS "$BASE_URL/api/reports/heavy?debugRun=$i" >/dev/null
    if [ $((i % 25)) -eq 0 ]; then
        curl -sS "$BASE_URL/debug/memory" | jq .
    fi
done
```

요청 수와 메모리 증가량을 함께 기록한다.
요청이 끝난 뒤 GC 후에도 내려오지 않으면 누수 가능성이 높다.

---

## 7. 흔한 누수 패턴

| 패턴 | 예시 | 수정 |
|------|------|------|
| 전역 배열 축적 | request log를 배열에 저장 | bounded buffer |
| 이벤트 리스너 누적 | 요청마다 listener 등록 | once/removeListener |
| cache TTL 없음 | key 무한 증가 | max size/TTL |
| stream 미종료 | file/socket close 누락 | finally cleanup |
| closure 보관 | 큰 객체 캡처 | 필요한 값만 복사 |
| ORM session 유지 | entity manager 장기 보관 | request scope 종료 |

---

## 8. Node heap snapshot

```typescript
import v8 from 'v8';
import { randomUUID } from 'crypto';

export function writeHeapSnapshot(label: string) {
    const filename = `/tmp/heap-${label}-${Date.now()}-${randomUUID()}.heapsnapshot`;
    v8.writeHeapSnapshot(filename);
    console.info({ event: 'heap.snapshot.written', filename });
    return filename;
}
```

스냅샷은 크고 민감정보를 포함할 수 있다.
공유 전 보안 범위를 확인한다.

---

## 9. GC 압박과 성능

메모리 누수가 없어도 allocation이 많으면 GC가 자주 돌며 latency가 튄다.

```typescript
function buildRows(items: Item[]) {
    return items.map((item) => ({
        id: item.id,
        price: item.price,
        tags: [...item.tags],
    }));
}
```

큰 배열을 반복 복사하는 코드는 CPU와 메모리 모두에 부담을 준다.
프로파일링으로 allocation hotspot을 확인한다.

---

## 10. 메모리 분석 기록

```markdown
| 시각 | 요청 수 | RSS MB | Heap Used MB | 비고 |
|------|---------|--------|--------------|------|
| 10:00 | 0 | 180 | 95 | baseline |
| 10:05 | 100 | 260 | 140 | report API |
| 10:10 | 200 | 350 | 210 | GC 후에도 유지 |
| 10:15 | 300 | 440 | 285 | leak suspected |
```

시간별 표는 스냅샷보다 설득력이 높다.

---

## 11. 수정 체크리스트

- [ ] 재현 요청과 증가 지표를 연결했다.
- [ ] heap/RSS/external 중 어느 영역인지 구분했다.
- [ ] snapshot 또는 allocation profile을 확보했다.
- [ ] 누수 객체의 소유자를 찾았다.
- [ ] cleanup, TTL, max size를 적용했다.
- [ ] 장시간 반복 테스트로 증가가 멈췄다.

---

## 12. 완료 기준

- [ ] OOM 또는 증가 추세를 재현했다.
- [ ] 메모리 증가 원인을 코드 위치로 설명한다.
- [ ] 수정 후 동일 부하에서 메모리가 안정화된다.
- [ ] 메모리 관련 회귀 테스트 또는 모니터링이 추가되었다.
