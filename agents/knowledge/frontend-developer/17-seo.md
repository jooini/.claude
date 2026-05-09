# SEO

> 원본: https://ironact.gitbook.io/ironact-docs/CrEhRPJQJpia3xh9iqbi/knowledge-fe/seo

---

## 1. Next.js Metadata API

```tsx
// app/layout.tsx — 기본 메타데이터
import { Metadata } from 'next'

export const metadata: Metadata = {
  title: {
    template: '%s | 서비스명',  // 페이지 title | 사이트명
    default: '서비스명',
  },
  description: '서비스 설명 (160자 이내)',
  keywords: ['키워드1', '키워드2'],
  authors: [{ name: '작성자' }],
  robots: {
    index: true,
    follow: true,
  },
  openGraph: {
    type: 'website',
    locale: 'ko_KR',
    url: 'https://example.com',
    siteName: '서비스명',
    images: [{ url: '/og-image.png', width: 1200, height: 630 }],
  },
  twitter: {
    card: 'summary_large_image',
    site: '@handle',
  },
}

// app/blog/[slug]/page.tsx — 동적 메타데이터
export async function generateMetadata({ params }: Props): Promise<Metadata> {
  const post = await getPost(params.slug)

  return {
    title: post.title,
    description: post.excerpt,
    openGraph: {
      title: post.title,
      description: post.excerpt,
      images: [{ url: post.coverImage }],
      type: 'article',
      publishedTime: post.createdAt,
    },
  }
}
```

---

## 2. 구조화 데이터 (JSON-LD)

검색엔진이 콘텐츠를 더 잘 이해하도록 돕는 스키마.

```tsx
// 조직 스키마
export default function RootLayout({ children }: { children: ReactNode }) {
  const jsonLd = {
    '@context': 'https://schema.org',
    '@type': 'Organization',
    name: '서비스명',
    url: 'https://example.com',
    logo: 'https://example.com/logo.png',
  }

  return (
    <html>
      <body>
        <script
          type="application/ld+json"
          dangerouslySetInnerHTML={{ __html: JSON.stringify(jsonLd) }}
        />
        {children}
      </body>
    </html>
  )
}

// 블로그 포스트 스키마
const articleJsonLd = {
  '@context': 'https://schema.org',
  '@type': 'Article',
  headline: post.title,
  datePublished: post.createdAt,
  dateModified: post.updatedAt,
  author: { '@type': 'Person', name: post.author },
  image: post.coverImage,
}

// 제품 스키마
const productJsonLd = {
  '@context': 'https://schema.org',
  '@type': 'Product',
  name: product.name,
  description: product.description,
  offers: {
    '@type': 'Offer',
    price: product.price,
    priceCurrency: 'KRW',
    availability: 'https://schema.org/InStock',
  },
}
```

---

## 3. sitemap.xml

```ts
// app/sitemap.ts
import { MetadataRoute } from 'next'

export default async function sitemap(): Promise<MetadataRoute.Sitemap> {
  const posts = await getPosts()

  const postEntries = posts.map(post => ({
    url: `https://example.com/blog/${post.slug}`,
    lastModified: post.updatedAt,
    changeFrequency: 'weekly' as const,
    priority: 0.7,
  }))

  return [
    {
      url: 'https://example.com',
      lastModified: new Date(),
      changeFrequency: 'daily',
      priority: 1,
    },
    {
      url: 'https://example.com/blog',
      changeFrequency: 'daily',
      priority: 0.8,
    },
    ...postEntries,
  ]
}
```

---

## 4. robots.txt

```ts
// app/robots.ts
import { MetadataRoute } from 'next'

export default function robots(): MetadataRoute.Robots {
  return {
    rules: [
      {
        userAgent: '*',
        allow: '/',
        disallow: ['/admin/', '/api/', '/private/'],
      },
    ],
    sitemap: 'https://example.com/sitemap.xml',
  }
}
```

---

## 5. 기술적 SEO 체크리스트

### URL 구조
```
✅ https://example.com/blog/how-to-use-react  (의미 있는 slug)
❌ https://example.com/post?id=123            (쿼리 파라미터)
❌ https://example.com/p/abc123              (의미 없는 ID)
```

### 표준 URL (Canonical)
```tsx
export const metadata: Metadata = {
  alternates: {
    canonical: 'https://example.com/blog/original-post',
    languages: {
      'ko': 'https://example.com/ko/blog/post',
      'en': 'https://example.com/en/blog/post',
    },
  },
}
```

### Core Web Vitals
SEO 랭킹 팩터 — 성능 섹션 참고.

### 404 처리
```tsx
// app/not-found.tsx
export default function NotFound() {
  return (
    <div>
      <h1>페이지를 찾을 수 없습니다</h1>
      <p>요청하신 페이지가 존재하지 않습니다.</p>
      <Link href="/">홈으로 돌아가기</Link>
    </div>
  )
}
```

---

## 6. 안티패턴

- **클라이언트 렌더링만**: 검색 엔진은 JS 실행 느림 → Server Component로
- **중복 title/description**: 모든 페이지 고유하게
- **이미지 alt 누락**: 이미지 SEO + 접근성
- **내부 링크 `<a>` 대신 `onClick`**: 크롤러가 따라가지 못함
- **`noindex` 운영 배포**: staging/dev에는 noindex, 운영에는 제거 확인
