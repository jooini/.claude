# Node.js Internals

> 원본: https://ironact.gitbook.io/ironact-docs/CrEhRPJQJpia3xh9iqbi/knowledge-be/nodejs-internals

---

## 1. 이벤트 루프

Node.js는 싱글 스레드 + 이벤트 루프로 동작.

```
   ┌──────────────────────────┐
┌─>│       timers             │  setTimeout, setInterval 콜백
│  └──────────────────────────┘
│  ┌──────────────────────────┐
│  │  pending callbacks       │  이전 루프의 I/O 에러 콜백
│  └──────────────────────────┘
│  ┌──────────────────────────┐
│  │       idle, prepare      │  내부 사용
│  └──────────────────────────┘
│  ┌──────────────────────────┐
│  │         poll             │  I/O 이벤트 대기 및 처리 ← 대부분의 시간
│  └──────────────────────────┘
│  ┌──────────────────────────┐
│  │         check            │  setImmediate 콜백
│  └──────────────────────────┘
│  ┌──────────────────────────┐
└──│    close callbacks       │  socket.on('close') 등
   └──────────────────────────┘

각 페이즈 전후: process.nextTick, Promise 마이크로태스크 처리
```

---

## 2. 이벤트 루프 블로킹

```ts
// ❌ 이벤트 루프 블로킹 — 다른 요청 처리 불가
app.get('/heavy', (req, res) => {
  // CPU 집약 작업이 이벤트 루프를 점유
  const result = heavyComputation()  // 5초 걸리면 다른 요청 5초 대기
  res.json(result)
})

// ✅ Worker Thread로 분리
import { Worker, isMainThread, parentPort, workerData } from 'worker_threads'

function runInWorker(data: unknown): Promise<unknown> {
  return new Promise((resolve, reject) => {
    const worker = new Worker('./heavy-computation.worker.js', { workerData: data })
    worker.on('message', resolve)
    worker.on('error', reject)
  })
}

app.get('/heavy', async (req, res) => {
  const result = await runInWorker(req.body)  // 워커에서 처리, 루프 비블로킹
  res.json(result)
})

// heavy-computation.worker.js
const result = heavyComputation(workerData)
parentPort?.postMessage(result)
```

---

## 3. 마이크로태스크 vs 매크로태스크

```ts
// 실행 순서 이해
console.log('1')

setTimeout(() => console.log('2'), 0)       // 매크로태스크
setImmediate(() => console.log('3'))         // check 페이즈

Promise.resolve().then(() => console.log('4'))  // 마이크로태스크
process.nextTick(() => console.log('5'))     // 마이크로태스크 (최우선)

console.log('6')

// 출력: 1 → 6 → 5 → 4 → 2 → 3
// (nextTick > Promise > setImmediate ≈ setTimeout)
```

---

## 4. 메모리 관리

```ts
// 메모리 누수 원인

// 1. 이벤트 리스너 미제거
const emitter = new EventEmitter()
function handler() { ... }
emitter.on('event', handler)
// 제거 안 하면 메모리 누수
emitter.off('event', handler)  // 또는 emitter.once('event', handler)

// 2. 클로저가 큰 객체 참조
function createHandler() {
  const bigData = loadBigData()  // 수십 MB

  return function handler(req, res) {
    // bigData를 참조하면 핸들러가 살아있는 한 bigData도 유지
    res.json(bigData.find(req.params.id))
  }
}

// 3. 캐시 크기 제한 안 함
const cache = new Map()
cache.set(key, value)  // 계속 증가
// → LRU 캐시 사용 또는 size 제한

// 메모리 사용량 모니터링
setInterval(() => {
  const { heapUsed, heapTotal } = process.memoryUsage()
  logger.debug(`Heap: ${Math.round(heapUsed / 1024 / 1024)}MB / ${Math.round(heapTotal / 1024 / 1024)}MB`)
}, 10000)
```

---

## 5. 스트림 (Streams)

대용량 데이터 처리 — 메모리에 전부 올리지 않고 청크 단위 처리.

```ts
import { pipeline } from 'stream/promises'
import { createReadStream, createWriteStream } from 'fs'
import { createGzip } from 'zlib'

// 파일 압축 — 메모리 효율적
async function compressFile(input: string, output: string) {
  await pipeline(
    createReadStream(input),
    createGzip(),
    createWriteStream(output),
  )
}

// DB 결과 스트리밍
async function exportToCsv(res: Response) {
  const stream = await dataSource
    .createQueryBuilder(UserEntity, 'u')
    .stream()

  const transform = new Transform({
    objectMode: true,
    transform(row, _, callback) {
      callback(null, `${row.id},${row.name},${row.email}\n`)
    },
  })

  await pipeline(stream, transform, res)
}
```

---

## 6. 클러스터 & PM2

```ts
// cluster.ts — CPU 코어 수만큼 워커 프로세스
import cluster from 'cluster'
import os from 'os'

if (cluster.isPrimary) {
  const numCPUs = os.cpus().length
  for (let i = 0; i < numCPUs; i++) {
    cluster.fork()
  }
  cluster.on('exit', (worker) => {
    console.log(`Worker ${worker.id} died, restarting...`)
    cluster.fork()
  })
} else {
  // 워커 프로세스 — NestJS 앱 실행
  bootstrap()
}
```

```yaml
# ecosystem.config.js (PM2)
module.exports = {
  apps: [{
    name: 'api',
    script: './dist/main.js',
    instances: 'max',      # CPU 코어 수
    exec_mode: 'cluster',
    max_memory_restart: '500M',
    env_production: {
      NODE_ENV: 'production',
    },
  }],
}
```

---

## 7. 환경 설정 최적화

```ts
// V8 힙 크기 설정
// package.json
"start:prod": "node --max-old-space-size=2048 dist/main.js"

// UV_THREADPOOL_SIZE — libuv 스레드 풀 (파일 I/O, DNS 등)
// 기본값 4, CPU 코어 수만큼 늘리기
process.env.UV_THREADPOOL_SIZE = String(os.cpus().length)
```

---

## 8. 안티패턴

- **CPU 집약 작업을 메인 스레드에서**: Worker Thread로
- **동기 파일 I/O**: `fs.readFileSync` → `fs.promises.readFile`
- **이벤트 리스너 미제거**: 메모리 누수
- **무한 재귀 Promise**: 스택 오버플로우
- **process.nextTick 남용**: 마이크로태스크 큐 과부하 → I/O 기아 현상
