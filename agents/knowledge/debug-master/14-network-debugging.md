# 네트워크 디버깅

> 네트워크 문제는 "안 됨"으로 보이지만 DNS, TCP, TLS, HTTP, 애플리케이션 계약 중 하나에서 실패한다.

---

## 1. 네트워크 계층

```
Application
  ↓ HTTP status, body, headers
TLS
  ↓ certificate, handshake
TCP
  ↓ connect, reset, timeout
DNS
  ↓ name resolution
Routing
  ↓ gateway, firewall, security group
```

어느 계층에서 실패하는지 먼저 나눈다.
HTTP 500과 TCP timeout은 같은 "호출 실패"가 아니다.

---

## 2. 기본 점검

```bash
TARGET="https://api.example.com/health"

date -Is
curl -sv --connect-timeout 3 --max-time 10 "$TARGET" -o /tmp/health.out
cat /tmp/health.out
```

curl verbose에서 볼 것:

- [ ] DNS resolve 결과
- [ ] connect 성공 여부
- [ ] TLS handshake
- [ ] request headers
- [ ] response status
- [ ] total time

---

## 3. curl 타이밍

```bash
curl -sS -o /dev/null \
    -w 'dns=%{time_namelookup} connect=%{time_connect} tls=%{time_appconnect} starttransfer=%{time_starttransfer} total=%{time_total} status=%{http_code}\n' \
    https://api.example.com/health
```

해석:

| 값 | 의미 |
|----|------|
| `time_namelookup` | DNS 지연 |
| `time_connect` | TCP 연결 지연 |
| `time_appconnect` | TLS 완료 시간 |
| `time_starttransfer` | 서버 처리 후 첫 바이트 |
| `time_total` | 전체 시간 |

---

## 4. DNS 확인

```bash
dig api.example.com
dig api.example.com A +short
dig api.example.com AAAA +short
```

문제 패턴:

- [ ] NXDOMAIN
- [ ] 내부/외부 DNS 결과 차이
- [ ] IPv6 주소만 실패
- [ ] TTL이 너무 길어 변경 반영 지연
- [ ] split-horizon DNS 설정 누락

---

## 5. TCP 연결

```bash
nc -vz api.example.com 443
```

```bash
traceroute api.example.com
```

TCP connect가 안 되면 애플리케이션 코드를 보기 전에 방화벽, 보안 그룹, 라우팅, 포트 리스닝 상태를 확인한다.

서버 측:

```bash
ss -ltnp | rg ':443|:3000'
ss -tan state established | wc -l
```

---

## 6. TLS 확인

```bash
openssl s_client -connect api.example.com:443 -servername api.example.com </dev/null
```

확인할 항목:

- [ ] 인증서 만료일
- [ ] SNI 일치
- [ ] chain 검증
- [ ] 지원 TLS 버전
- [ ] hostname mismatch

인증서 오류는 클라이언트 런타임의 CA bundle 차이로 환경별로 다르게 나타날 수 있다.

---

## 7. HTTP 계약 확인

```bash
curl -sv -X POST https://api.example.com/orders \
    -H "content-type: application/json" \
    -H "authorization: Bearer $TOKEN" \
    -d '{"productId":"p-1","quantity":1}'
```

HTTP 레벨에서 볼 것:

- [ ] status code
- [ ] response body error code
- [ ] required header 누락
- [ ] content-type mismatch
- [ ] proxy가 header를 제거하는지
- [ ] redirect 처리 여부

---

## 8. Node.js timeout 구분

```typescript
const controller = new AbortController();
const timeout = setTimeout(() => controller.abort(), 5000);

try {
    const response = await fetch(url, { signal: controller.signal });
    logger.info({ event: 'http.done', status: response.status });
} catch (error) {
    logger.error({
        event: 'http.failed',
        name: error.name,
        message: error.message,
    });
} finally {
    clearTimeout(timeout);
}
```

connect timeout, read timeout, application timeout을 구분해서 기록한다.

---

## 9. 패킷 캡처

```bash
sudo tcpdump -i any host api.example.com and port 443 -w /tmp/api-example.pcap
```

패킷 캡처는 강력하지만 민감정보를 포함할 수 있다.
운영에서는 승인, 범위 제한, 저장 위치를 명확히 한다.

텍스트 확인:

```bash
sudo tcpdump -i any -nn 'tcp port 5432' -c 50
```

---

## 10. 프록시와 로드밸런서

확인할 것:

- [ ] `X-Forwarded-For`, `X-Forwarded-Proto` 전달
- [ ] request body size limit
- [ ] idle timeout
- [ ] keep-alive 설정
- [ ] health check path
- [ ] upstream retry 정책

```bash
curl -sS -D - https://service.example.com/debug/headers -o /tmp/headers.json
jq . /tmp/headers.json
```

---

## 11. 네트워크 이슈 기록

```markdown
| 계층 | 결과 | 근거 |
|------|------|------|
| DNS | 정상 | A record resolves to 10.0.1.12 |
| TCP | 실패 | `nc -vz` timeout |
| TLS | 미검증 | TCP 실패로 진행 불가 |
| HTTP | 미검증 | TCP 실패로 진행 불가 |
| Routing | 의심 | staging subnet에서만 실패 |
```

---

## 12. 완료 기준

- [ ] 실패 계층을 특정했다.
- [ ] 클라이언트와 서버 양쪽 로그를 확인했다.
- [ ] DNS/TCP/TLS/HTTP를 분리했다.
- [ ] timeout 종류를 구분했다.
- [ ] 네트워크 설정 변경이 필요하면 롤백 방법이 있다.
