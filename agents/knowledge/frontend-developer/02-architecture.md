# Architecture

> 원본: https://ironact.gitbook.io/ironact-docs/CrEhRPJQJpia3xh9iqbi/knowledge-fe/architecture

---

## 1. FE 아키텍처의 목표

- **변경 비용 최소화**: 기능 추가/수정이 다른 곳을 건드리지 않게
- **팀 확장 가능성**: 여러 팀이 독립적으로 개발 가능하게
- **테스트 용이성**: 비즈니스 로직이 UI와 분리되어야 테스트 가능

---

## 2. 폴더 구조 패턴

### Feature-based 구조 (권장)

```
src/
  features/
    auth/
      components/
        LoginForm.tsx
      hooks/
        useAuth.ts
      api/
        auth.api.ts
      types/
        auth.types.ts
      index.ts         # public API — 외부에 공개할 것만 export
    dashboard/
    payment/

  shared/              # 도메인 무관 공통 모듈
    components/
      Button/
      Input/
    hooks/
      useDebounce.ts
    utils/
      format.ts
    types/
      common.types.ts

  app/                 # 라우팅, 레이아웃, 진입점
```

**핵심 규칙:**
- feature 간 직접 import 금지 → `index.ts` public API를 통해서만
- shared는 feature에 의존하지 않음
- feature는 shared에만 의존 가능

### Layer-based 구조 (소규모에 적합)

```
src/
  components/
  hooks/
  pages/
  services/
  store/
  utils/
  types/
```

규모가 커지면 각 레이어 내 파일이 혼잡해짐 → feature-based로 전환 고려

---

## 3. 컴포넌트 계층

```
Pages / Routes
  └── Feature Components  (비즈니스 로직 포함)
        └── UI Components  (순수 프레젠테이션)
              └── Primitive Components  (Button, Input 등)
```

**UI Component 원칙:**
- 비즈니스 로직 없음
- 외부 상태(store) 직접 접근 없음
- props로만 데이터 수신
- Storybook으로 독립 개발/문서화 가능

```tsx
// ✅ 순수 UI 컴포넌트
interface UserCardProps {
  name: string
  avatar: string
  role: string
  onEdit: () => void
}

export function UserCard({ name, avatar, role, onEdit }: UserCardProps) {
  return (
    <div className="user-card">
      <img src={avatar} alt={name} />
      <h3>{name}</h3>
      <span>{role}</span>
      <button onClick={onEdit}>편집</button>
    </div>
  )
}
```

---

## 4. 의존성 방향

```
UI Layer
    ↓ (단방향)
Business Logic Layer  (hooks, services)
    ↓
Data Layer  (API, store)
```

상위 레이어가 하위 레이어에 의존. 역방향 의존 금지.

---

## 5. 모듈 경계 (Barrel export)

```ts
// features/auth/index.ts — public API만 노출
export { LoginForm } from './components/LoginForm'
export { useAuth } from './hooks/useAuth'
export type { AuthUser } from './types/auth.types'
// 내부 구현(api, 내부 유틸 등)은 export 안 함
```

외부에서는 `import { useAuth } from '@/features/auth'`로만 접근.

---

## 6. Next.js App Router 구조

```
app/
  (auth)/              # route group — URL에 포함 안 됨
    login/
      page.tsx
    signup/
      page.tsx
  (dashboard)/
    layout.tsx         # 대시보드 공통 레이아웃
    page.tsx
    settings/
      page.tsx
  api/                 # Route Handlers
    users/
      route.ts

  layout.tsx           # root layout
  globals.css
```

**Server vs Client Component 원칙:**
- 기본은 Server Component (데이터 fetching, SEO)
- 인터랙션/상태 필요할 때만 `'use client'`
- Client Component는 트리의 말단(leaf)에 위치시키기

---

## 7. 안티패턴

- **Prop drilling 남용**: 3단계 이상이면 Context 또는 상태 관리
- **Feature 간 직접 import**: `import { X } from '../other-feature/internal'`
- **God page**: 페이지 컴포넌트에 모든 로직 → feature 컴포넌트로 분리
- **순환 의존**: A → B → A
- **shared에 비즈니스 로직**: shared는 도메인 무관해야 함
