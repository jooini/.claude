# Build Verification

> 참조 링크: https://nextjs.org/docs/app/api-reference/cli/next#build, https://vitejs.dev/guide/build.html

---

## 1. 빌드 검증 목적

코드 변경 후 **프로덕션 빌드가 성공하는지** 확인한다. 타입 에러, import 누락, 환경 변수 미설정 등 개발 모드에서 드러나지 않는 문제를 잡는다.

## 2. Next.js 빌드

### 실행

```bash
# 프로덕션 빌드
npx next build

# 빌드 분석
ANALYZE=true npx next build  # @next/bundle-analyzer 필요

# 빌드 출력 상세
npx next build --debug
```

### 흔한 빌드 에러

| 에러 패턴 | 원인 | 해결 |
|-----------|------|------|
| `Type error: ...` | tsc 타입 에러 | 타입 수정 (빌드 시 타입 체크 실행됨) |
| `Module not found: Can't resolve 'X'` | import 경로 오류 또는 미설치 패키지 | 경로 확인, 패키지 설치 |
| `Dynamic server usage` | 정적 생성 페이지에서 동적 API 사용 | `export const dynamic = 'force-dynamic'` 추가 |
| `Collecting page data ... failed` | getStaticProps/generateStaticParams 에러 | 데이터 소스 확인 |
| `Image Optimization ... is not configured` | next/image 도메인 미설정 | `next.config.js`에 `images.domains` 추가 |
| `'client-only' cannot be imported from a Server Component` | 클라이언트 전용 코드가 서버에서 실행 | `'use client'` 디렉티브 추가 |
| `window is not defined` | SSR 중 브라우저 API 접근 | dynamic import 또는 useEffect 안으로 이동 |

### 빌드 출력 분석

```bash
# .next/ 디렉토리 구조
# ├── cache/          — 빌드 캐시
# ├── server/         — 서버 사이드 번들
# ├── static/         — 정적 에셋
# └── build-manifest.json — 페이지별 청크 매핑

# 페이지별 크기 확인 (빌드 로그에 출력됨)
# Route (app)             Size     First Load JS
# ┌ ○ /                   5.1 kB   89.2 kB
# ├ ○ /about              1.2 kB   85.3 kB
# └ λ /api/users          0 B      84.1 kB

# ○ = Static, λ = Dynamic(서버 렌더링)
```

## 3. Vite 빌드

### 실행

```bash
# 프로덕션 빌드
npx vite build

# 프리뷰 (빌드 결과 로컬 테스트)
npx vite preview

# SSR 빌드
npx vite build --ssr
```

### 흔한 빌드 에러

| 에러 패턴 | 원인 | 해결 |
|-----------|------|------|
| `Could not resolve 'X'` | import 경로 또는 패키지 오류 | 경로 확인, alias 설정 |
| `Top-level await is not available` | 구형 타겟 설정 | `build.target` 업데이트 |
| `Circular dependency` | 순환 참조 | 의존성 구조 리팩토링 |
| `[commonjs] Failed to resolve` | CJS/ESM 호환성 | `optimizeDeps.include`에 추가 |

## 4. NestJS 빌드

### 실행

```bash
# 프로덕션 빌드
npx nest build

# webpack 사용 시
npx nest build --webpack

# watch 모드
npx nest build --watch
```

### 흔한 빌드 에러

| 에러 패턴 | 원인 | 해결 |
|-----------|------|------|
| `Cannot find module 'X'` | 경로 alias 미해석 | `tsconfig.json` paths + `tsconfig-paths` |
| `Nest can't resolve dependencies of X` | DI 등록 누락 | `@Injectable()` + providers 등록 |
| `Circular dependency detected` | 서비스 간 순환 참조 | `forwardRef()` 또는 구조 변경 |
| `Metadata 'X' is not available` | 데코레이터 미적용 | `emitDecoratorMetadata: true` 확인 |

## 5. Python 빌드/패키징

```bash
# Poetry
poetry build
poetry install --no-dev  # 프로덕션 의존성만

# pip
pip install -e .
python -m build  # wheel/sdist 생성

# Docker 기반
docker build -t myapp .
```

## 6. 빌드 실패 진단 절차

```
1. 에러 메시지 첫 줄 확인 → 에러 유형 분류
2. 에러 발생 파일:라인 확인
3. git diff로 최근 변경과의 관계 파악
4. 의존성 변경 여부 확인 (lock 파일 diff)
5. 캐시 클리어 후 재시도
   - Next.js: rm -rf .next/
   - Vite: rm -rf node_modules/.vite/
   - NestJS: rm -rf dist/
   - 공통: rm -rf node_modules/ && npm install
6. 환경 변수 확인 (.env vs .env.example 비교)
```

## 7. 빌드 성능 측정

```bash
# 빌드 시간 측정
time npx next build

# Node.js 메모리 사용량 확인
NODE_OPTIONS="--max-old-space-size=4096" npx next build

# Vite 빌드 시간 (내장 로그)
npx vite build --logLevel info
```

### 빌드 캐시 활용

```bash
# Next.js — .next/cache 유지 시 증분 빌드
# Turborepo — 원격 캐시
npx turbo build --cache-dir=.turbo

# Docker — 레이어 캐시 최적화
# package.json + lock 파일 먼저 복사 → npm install → 소스 복사
```

## 8. CI 빌드 검증

```yaml
# GitHub Actions
- name: Build
  run: npm run build
  env:
    NODE_ENV: production
    # 빌드에 필요한 환경 변수
    NEXT_PUBLIC_API_URL: ${{ vars.API_URL }}

- name: Check build output
  run: |
    # 빌드 산출물 존재 확인
    test -d .next || test -d dist
```
