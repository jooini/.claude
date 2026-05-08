# Performance Testing

> 원본: https://ironact.gitbook.io/ironact-docs/CrEhRPJQJpia3xh9iqbi/knowledge-qa/performance-testing

---

## 1. 성능 테스트 유형

| 유형 | 목적 | 방법 |
|------|------|------|
| **부하 테스트 (Load)** | 예상 트래픽에서 정상 동작 확인 | 목표 사용자 수 유지 |
| **스트레스 테스트 (Stress)** | 시스템 한계 파악 | 한계까지 점진적 증가 |
| **스파이크 테스트 (Spike)** | 갑작스러운 트래픽 급증 대응 | 순간 트래픽 급증 |
| **내구성 테스트 (Soak)** | 장시간 운영 시 메모리 누수 등 | 낮은 부하로 장시간 |
| **볼륨 테스트 (Volume)** | 대용량 데이터 처리 능력 | 대량 데이터 삽입 후 테스트 |

---

## 2. k6 기본 사용

```js
// k6/load-test.js
import http from 'k6/http'
import { check, sleep } from 'k6'
import { Rate, Trend } from 'k6/metrics'

// 커스텀 메트릭
const errorRate    = new Rate('error_rate')
const apiDuration  = new Trend('api_duration')

export const options = {
  // 부하 테스트 시나리오
  stages: [
    { duration: '1m',  target: 50  },  // 워밍업
    { duration: '3m',  target: 100 },  // 목표 부하 유지
    { duration: '1m',  target: 200 },  // 피크 트래픽
    { duration: '1m',  target: 0   },  // 쿨다운
  ],

  // 성공 기준 (SLO)
  thresholds: {
    http_req_duration: [
      'p(95)<500',   // 95%가 500ms 이내
      'p(99)<1000',  // 99%가 1초 이내
    ],
    error_rate: ['rate<0.01'],  // 에러율 1% 미만
    http_req_failed: ['rate<0.01'],
  },
}

// 테스트 데이터
const BASE_URL = __ENV.BASE_URL || 'https://staging.example.com'
const USERS = JSON.parse(open('./users.json'))

export function setup() {
  // 테스트 시작 전 한 번 실행 — 토큰 발급
  const res = http.post(`${BASE_URL}/auth/login`, JSON.stringify({
    email: 'loadtest@example.com',
    password: 'TestPass1!',
  }), { headers: { 'Content-Type': 'application/json' } })

  return { token: res.json('data.accessToken') }
}

export default function(data) {
  const headers = {
    'Authorization': `Bearer ${data.token}`,
    'Content-Type': 'application/json',
  }

  // 시나리오 1: 상품 목록 조회 (70% 비중)
  if (Math.random() < 0.7) {
    const res = http.get(`${BASE_URL}/products?page=1&limit=20`, { headers })
    const success = check(res, {
      'status 200': r => r.status === 200,
      'has data': r => r.json('data') !== null,
    })
    errorRate.add(!success)
    apiDuration.add(res.timings.duration, { endpoint: 'GET /products' })
  }

  // 시나리오 2: 주문 생성 (30% 비중)
  else {
    const res = http.post(`${BASE_URL}/orders`, JSON.stringify({
      productId: 'test-product-id',
      quantity: 1,
    }), { headers })
    const success = check(res, {
      'status 201': r => r.status === 201,
    })
    errorRate.add(!success)
    apiDuration.add(res.timings.duration, { endpoint: 'POST /orders' })
  }

  sleep(1)  // 사용자 행동 시뮬레이션
}
```

```bash
# 실행
k6 run --env BASE_URL=https://staging.example.com k6/load-test.js

# 결과 Grafana로 전송
k6 run --out influxdb=http://localhost:8086/k6 k6/load-test.js
```

---

## 3. Artillery (Node.js 기반)

```yaml
# artillery/load-test.yml
config:
  target: "https://staging.example.com"
  phases:
    - duration: 60
      arrivalRate: 10
      name: "Warm up"
    - duration: 180
      arrivalRate: 50
      name: "Sustained load"
  defaults:
    headers:
      Content-Type: "application/json"

scenarios:
  - name: "User journey"
    weight: 70
    flow:
      - post:
          url: "/auth/login"
          json:
            email: "{{ $randomEmail }}"
            password: "TestPass1!"
          capture:
            - json: "$.data.accessToken"
              as: "token"
      - get:
          url: "/products"
          headers:
            Authorization: "Bearer {{ token }}"
          expect:
            - statusCode: 200

  - name: "Browse only"
    weight: 30
    flow:
      - get:
          url: "/products?page={{ $randomInt(1, 10) }}"
          expect:
            - statusCode: 200
```

---

## 4. 성능 테스트 메트릭

```
응답 시간:
  p50 (중앙값)  — 일반적인 경험
  p95           — 대부분의 사용자 경험
  p99           — 최악의 사례 (꼬리 지연)

처리량:
  RPS (Requests Per Second) — 초당 요청 수
  TPS (Transactions Per Second) — 초당 완료 트랜잭션

에러율:
  HTTP 에러 비율 (4xx, 5xx)
  타임아웃 비율

리소스:
  CPU 사용률
  메모리 사용률
  DB 커넥션 수
  DB 쿼리 시간
```

---

## 5. 성능 병목 분석

```ts
// APM 데이터와 연계
// 부하 테스트 중 DataDog/New Relic 모니터링

// 느린 쿼리 감지
TypeOrmModule.forRoot({
  logging: ['slow'],
  maxQueryExecutionTime: 500,  // 500ms 초과 쿼리 로깅
})

// 프로파일링
import { performance } from 'perf_hooks'

const start = performance.now()
const result = await heavyOperation()
const duration = performance.now() - start

if (duration > 200) {
  logger.warn({ event: 'slow_operation', duration, operation: 'heavyOperation' })
}
```

---

## 6. SLO (Service Level Objectives) 정의

```yaml
# 성능 SLO 예시
SLOs:
  - name: "API 응답 시간"
    metric: "p95 of http_req_duration"
    target: "< 500ms"
    window: "30 days"

  - name: "가용성"
    metric: "successful_requests / total_requests"
    target: "> 99.9%"
    window: "30 days"

  - name: "처리량"
    metric: "RPS under normal load"
    target: "> 100 RPS"
    condition: "CPU < 70%"
```

---

## 7. 안티패턴

- **운영 환경에서 부하 테스트**: 스테이징에서
- **SLO 없는 테스트**: 기준 없이 결과를 어떻게 판단?
- **단일 엔드포인트만 테스트**: 실제 사용자 패턴 믹스로
- **워밍업 없는 테스트**: 콜드 스타트 포함 시 왜곡
- **결과만 보고 원인 분석 안 함**: 느린 쿼리, 리소스 병목 확인
