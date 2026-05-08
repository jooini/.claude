# Test Environments

> 원본: https://ironact.gitbook.io/ironact-docs/CrEhRPJQJpia3xh9iqbi/knowledge-qa/test-environments

---

## 1. 환경 계층

```
로컬 (Local)
  개발자 개인 환경
  목적: 개발 + 단위 테스트
  DB: 로컬 Docker 또는 in-memory

개발 (Development / Dev)
  팀 공유 개발 환경
  목적: 통합 확인, 기능 데모
  배포: feature 브랜치 자동 배포

스테이징 (Staging / QA)
  운영과 동일한 구성
  목적: QA 테스트, E2E, 성능 테스트
  배포: develop 브랜치

운영 (Production)
  실제 사용자 환경
  목적: 서비스 제공
  배포: main 브랜치 (승인 후)
```

---

## 2. 환경 구성 관리

```yaml
# docker-compose.test.yml
version: '3.8'
services:
  api:
    build:
      context: .
      target: test
    environment:
      NODE_ENV: test
      DATABASE_URL: postgresql://test:test@db:5432/testdb
      REDIS_URL: redis://redis:6379
      JWT_SECRET: test-secret-do-not-use-in-production

  db:
    image: postgres:16-alpine
    environment:
      POSTGRES_DB: testdb
      POSTGRES_USER: test
      POSTGRES_PASSWORD: test
    tmpfs:
      - /var/lib/postgresql/data  # 메모리 사용 → 빠름, 재시작 시 초기화

  redis:
    image: redis:7-alpine
    command: redis-server --save ""  # 영속성 비활성화
```

---

## 3. 환경별 설정 관리

```ts
// config/env.ts
const envSchema = z.object({
  NODE_ENV: z.enum(['development', 'test', 'staging', 'production']),
  DATABASE_URL: z.string().url(),
  REDIS_URL: z.string().url(),
  JWT_ACCESS_SECRET: z.string().min(32),
  JWT_REFRESH_SECRET: z.string().min(32),
  // 환경별 선택 설정
  PAYMENT_MODE: z.enum(['test', 'live']).default('test'),
  LOG_LEVEL: z.enum(['debug', 'info', 'warn', 'error']).default('info'),
  SENTRY_DSN: z.string().url().optional(),
})

export const env = envSchema.parse(process.env)

// 환경별 기본값
const defaults: Record<string, Partial<z.infer<typeof envSchema>>> = {
  test:        { LOG_LEVEL: 'error', PAYMENT_MODE: 'test' },
  staging:     { LOG_LEVEL: 'debug', PAYMENT_MODE: 'test' },
  production:  { LOG_LEVEL: 'warn',  PAYMENT_MODE: 'live' },
}
```

---

## 4. 테스트 데이터 관리

```ts
// 환경별 시드 데이터
// scripts/seed.ts

async function seed(env: string) {
  if (env === 'production') {
    throw new Error('운영 환경에서 시드 실행 불가')
  }

  // 공통 시드
  await seedRoles()
  await seedSystemConfig()

  // 환경별 시드
  if (env === 'test') {
    await seedTestUsers()     // 테스트용 계정
  }

  if (env === 'staging') {
    await seedDemoData()      // 데모용 데이터
    await seedPerformanceData()  // 성능 테스트용 대용량 데이터
  }
}

// 테스트 계정 규칙
const testAccounts = {
  admin:    { email: 'admin@test.com',    role: 'admin' },
  user:     { email: 'user@test.com',     role: 'user' },
  vipUser:  { email: 'vip@test.com',      role: 'user', grade: 'VIP' },
  banned:   { email: 'banned@test.com',   status: 'banned' },
}
```

---

## 5. 환경 격리

```ts
// 테스트 격리 전략

// 1. 스키마 분리 (병렬 실행 시)
const schema = `test_worker_${process.env.JEST_WORKER_ID ?? 1}`
await db.query(`CREATE SCHEMA IF NOT EXISTS "${schema}"`)
await db.query(`SET search_path TO "${schema}"`)

// 2. 트랜잭션 롤백
beforeEach(async () => {
  await db.query('BEGIN')
})
afterEach(async () => {
  await db.query('ROLLBACK')
})

// 3. TRUNCATE
afterEach(async () => {
  await db.query(`
    TRUNCATE users, orders, order_items, payments
    RESTART IDENTITY CASCADE
  `)
})
```

---

## 6. 스테이징 환경 체크리스트

```markdown
## 스테이징 환경 검증 체크리스트

인프라:
  [ ] 운영과 동일한 서버 스펙 (또는 최소 80%)
  [ ] 동일한 DB 버전, 설정
  [ ] 동일한 캐시 설정
  [ ] 동일한 외부 서비스 연동 (결제 테스트 모드)

데이터:
  [ ] 운영 데이터 마스킹본 또는 대용량 더미 데이터
  [ ] 테스트 계정 준비 완료

배포:
  [ ] CI/CD 파이프라인 동일
  [ ] 환경 변수 완전히 분리
  [ ] 운영 배포와 동일한 프로세스로 배포
```

---

## 7. 안티패턴

- **로컬에서만 통과**: "내 컴퓨터에선 돼요" → 환경 표준화
- **스테이징-운영 설정 불일치**: 스테이징 통과 → 운영 실패
- **테스트 데이터 운영 노출**: 테스트 계정이 운영에 있으면 보안 위험
- **환경 변수 하드코딩**: 코드에 비밀 정보 포함
- **공유 테스트 DB**: 테스트 간 데이터 충돌 → 격리 필수
