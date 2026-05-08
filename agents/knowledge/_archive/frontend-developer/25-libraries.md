# Libraries

> 원본: https://ironact.gitbook.io/ironact-docs/CrEhRPJQJpia3xh9iqbi/knowledge-fe/libraries

---

## 1. 라이브러리 선택 기준

- **번들 크기**: bundlephobia.com에서 확인
- **유지보수**: 최근 커밋, 이슈 응답 속도, 다운로드 수
- **TypeScript 지원**: 공식 타입 제공 여부
- **라이선스**: MIT/Apache 2.0 권장
- **대체 가능성**: 직접 구현 vs 라이브러리 트레이드오프

---

## 2. 카테고리별 권장 라이브러리

### UI 컴포넌트
| 라이브러리 | 특징 |
|-----------|------|
| **shadcn/ui** | Copy-paste, Radix 기반, 완전 커스터마이징 |
| **Radix UI** | Headless, 접근성 내장, 스타일 자유 |
| **Headless UI** | Tailwind Labs 제작, 간단한 컴포넌트 |

### 상태 관리
| 라이브러리 | 특징 |
|-----------|------|
| **TanStack Query** | 서버 상태. 캐싱/동기화/재시도 자동화 |
| **Zustand** | 클라이언트 전역 상태. 가볍고 직관적 |
| **Jotai** | 원자(atom) 기반. 세밀한 상태 관리 |

### 폼
| 라이브러리 | 특징 |
|-----------|------|
| **React Hook Form** | 비제어 방식, 성능 우수 |
| **Zod** | TypeScript 우선 스키마 검증 |

### 테이블/데이터
| 라이브러리 | 특징 |
|-----------|------|
| **TanStack Table** | Headless. 정렬/필터/페이지네이션 |
| **TanStack Virtual** | 가상화. 대용량 리스트/그리드 |

### 날짜
| 라이브러리 | 특징 |
|-----------|------|
| **date-fns** | 함수형, tree shaking 우수 |
| **Day.js** | Moment.js 대체, 가벼움 (2KB) |

### 애니메이션
| 라이브러리 | 특징 |
|-----------|------|
| **Framer Motion** | 선언적, 강력한 애니메이션 |
| **Auto Animate** | 1줄로 레이아웃 애니메이션 |
| **CSS Transitions** | 간단한 hover, 상태 전환은 CSS로 |

### 차트
| 라이브러리 | 특징 |
|-----------|------|
| **Recharts** | React 친화적, 간단한 차트 |
| **Victory** | 컴포넌트 기반 |
| **D3.js** | 커스텀 시각화 (러닝 커브 높음) |

### 유틸리티
| 라이브러리 | 특징 |
|-----------|------|
| **clsx** | 조건부 클래스 조합 |
| **tailwind-merge** | Tailwind 클래스 충돌 해결 |
| **lodash-es** | 유틸 함수 (ESM, tree shaking) |
| **nanoid** | 고유 ID 생성 |
| **zod** | 런타임 타입 검증 |

### 알림/토스트
| 라이브러리 | 특징 |
|-----------|------|
| **Sonner** | 심플하고 예쁜 토스트 |
| **React Hot Toast** | 가볍고 커스터마이징 쉬움 |

---

## 3. 설치 전 번들 크기 확인

```bash
# bundlephobia에서 확인 또는 직접 측정
npx bundlesize

# 라이브러리별 번들 크기 예시
# date-fns:      41KB (tree shaking 적용 시 실제 더 작음)
# lodash-es:     72KB (tree shaking 적용 시 실제 더 작음)
# framer-motion: 47KB
# recharts:     135KB
# zustand:        8KB ← 가볍다
# zod:           53KB
```

---

## 4. 업데이트 관리

```bash
# 업데이트 가능한 패키지 확인
npx npm-check-updates

# 마이너/패치만 업데이트
npx npm-check-updates -u --target minor
npm install

# 특정 패키지 업데이트
npm install react-query@latest
```

**업데이트 전략:**
- Patch: 즉시 업데이트
- Minor: CI 통과 후 업데이트
- Major: 마이그레이션 가이드 확인, 브랜치에서 테스트

---

## 5. 직접 구현 vs 라이브러리

**직접 구현을 고려할 때:**
- 라이브러리가 필요한 기능의 10%만 사용
- 번들 크기가 기능 대비 너무 큼
- 의존성 추가가 보안/라이선스 문제 발생

```ts
// 예: debounce는 직접 구현 가능 (lodash 불필요)
function debounce<T extends (...args: unknown[]) => unknown>(
  fn: T,
  delay: number
): (...args: Parameters<T>) => void {
  let timer: ReturnType<typeof setTimeout>
  return (...args) => {
    clearTimeout(timer)
    timer = setTimeout(() => fn(...args), delay)
  }
}
```

---

## 6. 안티패턴

- **의존성 과다**: 간단한 기능에 무거운 라이브러리
- **버전 고정 안 함**: `npm install X` → lockfile 커밋 필수
- **라이선스 확인 안 함**: GPL 라이선스는 상업용 제품에 위험
- **deprecated 라이브러리**: Moment.js → date-fns/Day.js
- **유사 기능 라이브러리 중복**: axios + fetch, moment + date-fns 동시 사용
