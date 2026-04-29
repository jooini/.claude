# Debugging

> 원본: https://ironact.gitbook.io/ironact-docs/CrEhRPJQJpia3xh9iqbi/knowledge-be/debugging

---

## 1. Node.js 디버깅

### VS Code Debugger

```json
// .vscode/launch.json
{
  "configurations": [
    {
      "type": "node",
      "request": "launch",
      "name": "NestJS Debug",
      "runtimeExecutable": "npm",
      "runtimeArgs": ["run", "start:debug"],
      "sourceMaps": true,
      "envFile": "${workspaceFolder}/.env.local",
      "console": "integratedTerminal",
    },
    {
      "type": "node",
      "request": "attach",
      "name": "Attach to Process",
      "port": 9229,
      "sourceMaps": true,
      "skipFiles": ["<node_internals>/**"],
    }
  ]
}
```

```json
// package.json
"start:debug": "nest start --debug --watch"
```

### Chrome DevTools

```bash
node --inspect dist/main.js  # 포트 9229
# Chrome에서: chrome://inspect
```

---

## 2. 로그 기반 디버깅

```ts
// 구조화 로그로 문제 추적
logger.info({
  event: 'order.create.start',
  userId,
  itemCount: items.length,
  traceId: req.traceId,
})

// 타이밍 측정
const start = Date.now()
const result = await heavyOperation()
logger.debug({
  event: 'heavy_operation.done',
  duration: Date.now() - start,
  traceId: req.traceId,
})

// 에러 컨텍스트 풍부하게
try {
  await processOrder(orderId)
} catch (error) {
  logger.error({
    event: 'order.process.failed',
    orderId,
    userId,
    error: {
      name: error.name,
      message: error.message,
      stack: error.stack,
    },
    traceId: req.traceId,
  })
  throw error
}
```

---

## 3. 쿼리 디버깅

```ts
// TypeORM 쿼리 로깅
TypeOrmModule.forRoot({
  logging: process.env.NODE_ENV === 'development'
    ? ['query', 'error', 'warn', 'slow']
    : ['error'],
  maxQueryExecutionTime: 1000,  // 1초 초과 쿼리 slow log
})

// 특정 쿼리만 로깅
const result = await userRepo
  .createQueryBuilder('u')
  .where('u.id = :id', { id })
  .printSql()  // 쿼리 출력
  .getOne()

// 실행 계획 확인
const plan = await dataSource.query(`
  EXPLAIN (ANALYZE, BUFFERS)
  SELECT * FROM users WHERE email = $1
`, [email])
console.log(plan)
```

---

## 4. 메모리 누수 탐지

```ts
// 메모리 사용량 모니터링
setInterval(() => {
  const { heapUsed, heapTotal, external, rss } = process.memoryUsage()
  logger.debug({
    event: 'memory.usage',
    heapUsed:  Math.round(heapUsed  / 1024 / 1024),
    heapTotal: Math.round(heapTotal / 1024 / 1024),
    rss:       Math.round(rss       / 1024 / 1024),
  })
}, 30_000)

// 힙 스냅샷 생성
import v8 from 'v8'
import fs from 'fs'

app.get('/debug/heap-snapshot', (req, res) => {
  if (process.env.NODE_ENV === 'production') return res.status(403).end()
  const filename = `heap-${Date.now()}.heapsnapshot`
  const snapshot = v8.writeHeapSnapshot(filename)
  res.download(snapshot)
})

// Chrome DevTools Memory 탭에서 분석
```

---

## 5. 성능 프로파일링

```ts
// clinic.js — Node.js 성능 분석
// npm install -g clinic

// Flame Graph (CPU 병목)
// clinic flame -- node dist/main.js

// Bubble Chart (이벤트 루프 지연)
// clinic bubbleprof -- node dist/main.js

// Doctor (종합 진단)
// clinic doctor -- node dist/main.js
```

```ts
// 특정 코드 구간 측정
import { performance, PerformanceObserver } from 'perf_hooks'

function measureSync(name: string, fn: () => void) {
  performance.mark(`${name}:start`)
  fn()
  performance.mark(`${name}:end`)
  performance.measure(name, `${name}:start`, `${name}:end`)
  const [measure] = performance.getEntriesByName(name)
  console.log(`${name}: ${measure.duration.toFixed(2)}ms`)
}

async function measureAsync(name: string, fn: () => Promise<void>) {
  const start = performance.now()
  await fn()
  console.log(`${name}: ${(performance.now() - start).toFixed(2)}ms`)
}
```

---

## 6. 프로덕션 디버깅

```ts
// 로그 레벨 런타임 변경
// 운영에서 일시적으로 debug 레벨 활성화
app.post('/admin/log-level', adminGuard, (req, res) => {
  logger.level = req.body.level  // 'debug' | 'info' | 'warn'
  setTimeout(() => { logger.level = 'info' }, 5 * 60 * 1000)  // 5분 후 복구
  res.json({ level: logger.level })
})

// 특정 사용자 디버그 로깅
const shouldDebug = await redis.sismember('debug:users', userId)
if (shouldDebug) {
  logger.debug({ event: 'request.detail', userId, body: req.body })
}
```

---

## 7. 공통 버그 패턴

```ts
// 1. 비동기 에러 미처리
// ❌
router.get('/users', (req, res) => {
  getUsers().then(users => res.json(users))  // 에러 처리 없음
})

// ✅
router.get('/users', async (req, res, next) => {
  try {
    const users = await getUsers()
    res.json(users)
  } catch (err) {
    next(err)
  }
})

// 2. 타입 강제 변환
const id = req.params.id  // string
await repo.findById(id)   // UUID 컬럼이면 타입 불일치 에러 가능
// ParseUUIDPipe 또는 명시적 변환 사용

// 3. null/undefined 참조
const user = await userRepo.findOne({ where: { id } })
user.name  // user가 null이면 TypeError
// if (!user) throw new NotFoundException() 선행
```

---

## 8. 안티패턴

- **console.log 디버깅 후 미제거**: 구조화 로거 + 로그 레벨 활용
- **운영 DB에서 직접 디버깅**: 읽기 전용 복제본 사용
- **에러 삼키기**: `catch(e) {}` → 반드시 로깅 또는 throw
- **스택 트레이스 없는 에러 전파**: `throw error`가 아닌 `throw new Error(msg)` → 원인 소실
