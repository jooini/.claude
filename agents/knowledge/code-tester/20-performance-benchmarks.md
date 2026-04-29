# Performance Benchmarks

---

## 1. 빌드 시간 측정

### Node.js 프로젝트

```bash
# 시간 측정
time npm run build

# Next.js 빌드 상세
NEXT_TELEMETRY_DEBUG=1 npx next build

# Vite 빌드 상세
npx vite build --logLevel info

# Turborepo 빌드 (캐시 여부 표시)
npx turbo build --summarize
```

### 빌드 시간 벤치마크 기준

| 프로젝트 규모 | 기대 빌드 시간 | 경고 기준 |
|-------------|-------------|---------|
| 소규모 (< 50 파일) | < 10s | > 30s |
| 중규모 (50-200 파일) | < 30s | > 60s |
| 대규모 (200+ 파일) | < 60s | > 120s |
| 모노레포 (전체) | < 120s | > 300s |

## 2. 테스트 실행 시간

### 측정

```bash
# Jest — 실행 시간 포함 출력
npx jest --verbose

# Jest — 느린 테스트 리포트
npx jest --verbose 2>&1 | sort -t'(' -k2 -rn | head -20

# Vitest — 벤치마크
npx vitest bench

# pytest — 느린 테스트 top 10
pytest --durations=10
```

### 느린 테스트 식별

```bash
# Jest JSON 출력에서 느린 테스트 추출
npx jest --json | jq '[.testResults[].testResults[] |
  select(.duration > 1000) |
  {name: .fullName, duration: .duration}] |
  sort_by(-.duration) | .[0:10]'
```

### 테스트 시간 기준

| 유형 | 목표 | 경고 |
|------|------|------|
| 단위 테스트 (개별) | < 100ms | > 500ms |
| 단위 테스트 (전체) | < 30s | > 60s |
| 통합 테스트 (개별) | < 2s | > 5s |
| E2E 테스트 (개별) | < 10s | > 30s |
| 전체 테스트 스위트 | < 5min | > 10min |

## 3. 병렬화

### Jest 병렬 실행

```bash
# 워커 수 조절
npx jest --maxWorkers=4      # 4개 워커
npx jest --maxWorkers=50%    # CPU의 50%
npx jest --runInBand         # 직렬 실행 (디버깅용)

# CI에서 메모리 부족 시
npx jest --maxWorkers=2 --workerIdleMemoryLimit=512MB
```

### Vitest 병렬 실행

```typescript
// vitest.config.ts
{
  test: {
    pool: 'threads',  // 또는 'forks'
    poolOptions: {
      threads: {
        maxThreads: 4,
        minThreads: 1,
      },
    },
  },
}
```

### pytest 병렬 실행

```bash
# pytest-xdist
pytest -n auto       # CPU 코어 수만큼
pytest -n 4          # 4개 프로세스
pytest -n auto --dist loadscope  # 모듈 단위 분배
```

### CI 매트릭스 분할

```yaml
# GitHub Actions — 테스트 분할
strategy:
  matrix:
    shard: [1, 2, 3]
steps:
  - run: npx jest --shard=${{ matrix.shard }}/3
```

## 4. 린트 성능

```bash
# ESLint 실행 시간 측정
TIMING=1 npx eslint .
# 규칙별 실행 시간 출력

# ESLint 캐시 사용
npx eslint . --cache
# 두 번째 실행부터 변경 파일만 검사

# Ruff (매우 빠름)
time ruff check .
# 대부분 < 1초
```

### 린트 성능 개선

| 방법 | 효과 |
|------|------|
| `--cache` | 변경 파일만 검사 (2-10x 빠름) |
| 변경 파일만 린트 | CI 시간 대폭 단축 |
| Biome/Ruff 전환 | ESLint 대비 10-100x 빠름 |
| 불필요한 규칙 제거 | 규칙 수에 비례하여 단축 |

## 5. 빌드 성능 개선

### Next.js

```javascript
// next.config.js
module.exports = {
  // SWC 사용 (Babel 대비 빠름) — 기본값
  swcMinify: true,

  // 빌드 시 린트 스킵 (별도 CI step에서 실행)
  eslint: { ignoreDuringBuilds: true },

  // 빌드 시 타입 체크 스킵 (별도 CI step에서 실행)
  typescript: { ignoreBuildErrors: true },
};
```

### Webpack / Vite

```bash
# 번들 분석
# Next.js
ANALYZE=true npx next build

# Vite
npx vite-bundle-visualizer

# Webpack
npx webpack-bundle-analyzer dist/stats.json
```

## 6. 성능 회귀 감지

### 빌드/테스트 시간 트래킹

```bash
# 빌드 시간 기록
BUILD_START=$(date +%s)
npm run build
BUILD_END=$(date +%s)
echo "Build time: $((BUILD_END - BUILD_START))s"

# 테스트 시간 기록
npx jest --json | jq '.startTime as $s | .testResults[-1].endTime as $e | ($e - $s) / 1000'
```

### CI에서 시간 비교

```yaml
# 빌드 시간이 기준 초과 시 경고
- name: Check build time
  run: |
    START=$(date +%s)
    npm run build
    DURATION=$(($(date +%s) - START))
    echo "Build took ${DURATION}s"
    if [ $DURATION -gt 120 ]; then
      echo "::warning::Build time exceeded 120s threshold (${DURATION}s)"
    fi
```

## 7. 메모리 사용량

```bash
# Node.js 메모리 사용량 추적
NODE_OPTIONS="--max-old-space-size=4096 --expose-gc" npx jest

# 힙 사용량 로깅
node -e "console.log(process.memoryUsage())"

# OOM 방지
NODE_OPTIONS="--max-old-space-size=4096" npm run build
```

### CI 메모리 관리

| 환경 | 기본 메모리 | 권장 설정 |
|------|-----------|---------|
| GitHub Actions | 7GB | `--max-old-space-size=4096` |
| GitLab CI (shared) | 2-4GB | `--max-old-space-size=2048` + `--maxWorkers=2` |
| Docker | 컨테이너 제한 | 컨테이너 메모리의 75% |

## 8. 성능 체크리스트

- [ ] 빌드 시간이 허용 기준 이내
- [ ] 테스트 전체 실행 5분 이내
- [ ] 느린 테스트(> 5s) 없음 또는 마킹됨
- [ ] 린트 캐시 활성화
- [ ] CI에서 불필요한 중복 실행 없음
- [ ] 모노레포 영향 범위 기반 실행
- [ ] 메모리 OOM 발생하지 않음
