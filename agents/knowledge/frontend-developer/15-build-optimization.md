# Build Optimization

> 원본: https://ironact.gitbook.io/ironact-docs/CrEhRPJQJpia3xh9iqbi/knowledge-fe/build-optimization

---

## 1. 번들 분석

```bash
# Next.js 번들 분석
npm install @next/bundle-analyzer

# next.config.ts
import bundleAnalyzer from '@next/bundle-analyzer'

const withBundleAnalyzer = bundleAnalyzer({
  enabled: process.env.ANALYZE === 'true',
})

export default withBundleAnalyzer({
  // next config
})

# 실행
ANALYZE=true npm run build
```

**번들 분석 체크포인트:**
- 중복 라이브러리 (lodash + lodash-es 등)
- 불필요하게 큰 의존성
- 공통 chunk 분리 여부
- Tree shaking 안 되는 import

---

## 2. Tree Shaking

빌드 시 사용하지 않는 코드 제거.

```ts
// ❌ 전체 import — tree shaking 불가
import _ from 'lodash'
import * as Icons from 'lucide-react'

// ✅ named import — tree shaking 가능
import { debounce } from 'lodash-es'   // ESM 버전 사용
import { Search, User } from 'lucide-react'

// ❌ 사이드 이펙트가 있는 barrel export
// index.ts에서 모든 컴포넌트 re-export → 전체 포함
import { Button } from '@/components'

// ✅ 직접 import
import { Button } from '@/components/Button'
```

### package.json sideEffects 설정

```json
// 라이브러리 제작 시
{
  "sideEffects": false,        // 모든 파일 tree shaking 가능
  // 또는
  "sideEffects": ["*.css", "./src/polyfills.js"]  // 예외 지정
}
```

---

## 3. 코드 스플리팅 전략

```ts
// next.config.ts
export default {
  experimental: {
    optimizePackageImports: [
      'lucide-react',     // 아이콘 라이브러리
      '@radix-ui/react-icons',
      'date-fns',
    ],
  },
}
```

### Chunk 분리 전략

```ts
// 벤더 청크 분리 — 자주 바뀌지 않는 라이브러리
// Next.js는 자동으로 처리하지만 커스터마이징 가능
export default {
  webpack: (config) => {
    config.optimization.splitChunks = {
      chunks: 'all',
      cacheGroups: {
        vendor: {
          test: /[\\/]node_modules[\\/]/,
          name: 'vendors',
          priority: 10,
        },
        common: {
          minChunks: 2,
          name: 'common',
          priority: 5,
        },
      },
    }
    return config
  },
}
```

---

## 4. 이미지/폰트 최적화

### 폰트

```tsx
// app/layout.tsx — Next.js Font Optimization
import { Inter } from 'next/font/google'

const inter = Inter({
  subsets: ['latin'],
  display: 'swap',       // FOUT 방지
  variable: '--font-inter',  // CSS variable로 사용
})

export default function RootLayout({ children }: { children: ReactNode }) {
  return (
    <html lang="ko" className={inter.variable}>
      <body>{children}</body>
    </html>
  )
}
```

**로컬 폰트:**
```tsx
import localFont from 'next/font/local'

const pretendard = localFont({
  src: './fonts/PretendardVariable.woff2',
  display: 'swap',
  weight: '100 900',  // variable font
})
```

### SVG 최적화

```bash
# SVGO로 SVG 최적화
npx svgo --folder=public/icons --recursive
```

```tsx
// SVG를 React 컴포넌트로 — SVGR
// next.config.ts
export default {
  webpack: (config) => {
    config.module.rules.push({
      test: /\.svg$/,
      use: ['@svgr/webpack'],
    })
    return config
  },
}

// 사용
import SearchIcon from '@/icons/search.svg'
<SearchIcon className="h-4 w-4" />
```

---

## 5. 캐싱 전략

### Next.js 캐싱 계층

```
브라우저 캐시
  └── CDN/Edge 캐시 (Vercel Edge Network)
        └── Next.js Router Cache (클라이언트)
              └── Next.js Full Route Cache (빌드 시)
                    └── Next.js Data Cache (fetch 캐시)
                          └── React 서버 컴포넌트 캐시
```

```ts
// 데이터 캐시 세분화
// 정적 — 빌드 시 생성, CDN 캐시
fetch('/api/config', { cache: 'force-cache' })

// ISR — 주기적 재검증
fetch('/api/products', { next: { revalidate: 3600 } })  // 1시간

// 동적 — 캐시 없음
fetch('/api/cart', { cache: 'no-store' })

// On-demand revalidation
import { revalidateTag } from 'next/cache'
export async function updateProduct(id: string) {
  await db.product.update(...)
  revalidateTag('products')  // products 태그 캐시 무효화
}
```

---

## 6. 환경별 최적화

```ts
// next.config.ts
const config = {
  compress: true,               // gzip 압축

  images: {
    formats: ['image/avif', 'image/webp'],  // 최신 포맷 우선
    minimumCacheTTL: 60 * 60 * 24 * 7,     // 7일 캐시
  },

  headers: async () => [
    {
      source: '/:all*(svg|jpg|png)',
      headers: [
        { key: 'Cache-Control', value: 'public, max-age=31536000, immutable' },
      ],
    },
  ],

  // 불필요한 polyfill 제거
  experimental: {
    browsersListForSwc: true,
  },
}
```

---

## 7. 성능 예산 (Performance Budget)

```json
// .lighthouserc.json
{
  "ci": {
    "assert": {
      "assertions": {
        "categories:performance": ["error", { "minScore": 0.9 }],
        "first-contentful-paint": ["error", { "maxNumericValue": 1800 }],
        "largest-contentful-paint": ["error", { "maxNumericValue": 2500 }],
        "total-blocking-time": ["error", { "maxNumericValue": 300 }],
        "cumulative-layout-shift": ["error", { "maxNumericValue": 0.1 }]
      }
    }
  }
}
```

CI에서 Lighthouse CI 실행 → 성능 회귀 자동 감지.

---

## 8. 안티패턴

- **모든 라이브러리 전체 import**: named import + tree shaking
- **최적화 없는 이미지**: Next.js Image 컴포넌트 사용
- **개발 의존성이 번들에 포함**: `devDependencies` 올바르게 분리
- **Source map 운영 배포**: `productionBrowserSourceMaps: false`
- **성능 측정 없는 최적화**: 먼저 병목 지점 파악 후 최적화
