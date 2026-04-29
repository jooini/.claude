# Cost Optimization

> 원본: https://ironact.gitbook.io/ironact-docs/CrEhRPJQJpia3xh9iqbi/knowledge-be/cost-optimization

---

## 1. 비용 구조 파악

```
컴퓨팅     — EC2, ECS, Lambda, GKE
스토리지   — S3, RDS, ElastiCache
네트워크   — 데이터 전송, NAT Gateway
데이터베이스 — RDS, DynamoDB
모니터링   — CloudWatch, Datadog
```

**측정 먼저**: 추정이 아닌 실제 비용 데이터 기반으로 최적화.

---

## 2. 컴퓨팅 최적화

```ts
// Lambda (서버리스) — 사용한 만큼만 과금
// 적합: 간헐적 트래픽, 이벤트 처리, 배치 작업

// Cold Start 최소화
export const handler = async (event: APIGatewayEvent) => {
  // ✅ DB 연결을 핸들러 밖에서 초기화 (재사용)
  return processEvent(event)
}

// DB 연결을 핸들러 밖에서
const db = new DataSource({ ... })
await db.initialize()

// Lambda 메모리 설정 — 메모리 ↑ → CPU ↑ → 실행시간 ↓ → 비용 상쇄
// 128MB vs 512MB 실제 측정 후 결정
```

```yaml
# Kubernetes — 리소스 요청/제한 정확하게
resources:
  requests:
    cpu: 100m    # 실제 사용량에 맞게
    memory: 256Mi
  limits:
    cpu: 500m
    memory: 512Mi
# 과도한 requests → 노드 낭비
# 너무 작은 limits → OOM Kill
```

---

## 3. 데이터베이스 최적화

```ts
// 커넥션 풀 크기 최적화
// 너무 크면 → DB 메모리 낭비
// 너무 작으면 → 대기 시간 증가
// 공식: pool_size = (core_count * 2) + effective_spindle_count

TypeOrmModule.forRoot({
  extra: { max: 10 }  // 기본값부터 시작, 모니터링 후 조정
})

// Read Replica로 읽기 부하 분산
// → Master DB 사양 다운그레이드 가능
TypeOrmModule.forRoot({
  replication: {
    master: { ... },
    slaves: [{ ... }, { ... }],
  }
})

// RDS Proxy — 서버리스 환경에서 연결 풀 공유
// Lambda 인스턴스마다 DB 직접 연결 → 연결 수 폭발 방지
```

---

## 4. 캐싱으로 비용 절감

```ts
// DB 쿼리 → Redis 캐싱 (저렴)
// 자주 읽히는 데이터 캐싱 → RDS 조회 감소 → 낮은 사양 DB로 전환 가능

// CDN으로 오리진 서버 부하 감소
// 정적 자산, API 응답 캐싱
@Get('products')
@Header('Cache-Control', 'public, max-age=300, stale-while-revalidate=60')
async getProducts() { ... }
```

---

## 5. 스토리지 최적화

```ts
// S3 스토리지 클래스 자동 전환
// Standard → Standard-IA (30일 미접근) → Glacier (90일)
{
  Rules: [{
    Status: 'Enabled',
    Transitions: [
      { Days: 30,  StorageClass: 'STANDARD_IA' },
      { Days: 90,  StorageClass: 'GLACIER' },
      { Days: 365, StorageClass: 'DEEP_ARCHIVE' },
    ],
    Expiration: { Days: 2555 },  // 7년 후 삭제
  }]
}

// 이미지 최적화 — WebP 변환으로 용량 절감
// JPEG 대비 25~34% 작음
import sharp from 'sharp'

async function optimizeImage(buffer: Buffer): Promise<Buffer> {
  return sharp(buffer)
    .webp({ quality: 85 })
    .resize(1200, 1200, { fit: 'inside', withoutEnlargement: true })
    .toBuffer()
}

// 로그 보존 기간 설정
// CloudWatch: 비싸므로 30일 이후 S3로
```

---

## 6. 네트워크 비용

```ts
// ❌ 리전 간 데이터 전송 — 가장 비쌈
// 서비스를 같은 리전, 같은 AZ에

// NAT Gateway 비용 절감
// Lambda → S3 직접 VPC Endpoint 사용 (NAT 통과 안 함)

// 응답 압축
app.use(compression())  // gzip/brotli 압축 → 전송량 감소

// 페이로드 최소화
// 필요한 필드만 반환
return {
  id: user.id,
  name: user.name,
  // 불필요한 필드 제외
}
```

---

## 7. 비용 모니터링

```ts
// AWS Cost Anomaly Detection 설정
// 비용 급증 시 알림

// 태그 기반 비용 추적
// 서비스별, 환경별, 팀별 비용 파악
{
  Tags: [
    { Key: 'Service', Value: 'order-service' },
    { Key: 'Environment', Value: 'production' },
    { Key: 'Team', Value: 'backend' },
  ]
}

// 예산 알림
// 월 예산 초과 시 이메일/슬랙 알림
```

---

## 8. 안티패턴

- **사용하지 않는 리소스 방치**: 개발/스테이징 환경 스케줄 정지
- **과도한 로그 보존**: CloudWatch는 비쌈 → S3로 아카이브
- **리전 간 불필요한 데이터 전송**: 같은 리전 내 서비스 배치
- **측정 없는 최적화**: 비용 분석 먼저, 최적화 나중
- **Spot Instance 미활용**: 배치 작업, 스테이징은 Spot으로
