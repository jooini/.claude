# Next.js Testing

> 참조 링크: https://nextjs.org/docs/app/building-your-application/testing

---

## 1. 테스트 환경 설정

### Vitest + React Testing Library

```typescript
// vitest.config.ts
import { defineConfig } from 'vitest/config';
import react from '@vitejs/plugin-react';
import path from 'path';

export default defineConfig({
  plugins: [react()],
  test: {
    environment: 'jsdom',
    globals: true,
    setupFiles: ['./test/setup.ts'],
    include: ['src/**/*.{test,spec}.{ts,tsx}'],
    alias: {
      '@': path.resolve(__dirname, './src'),
    },
  },
});
```

```typescript
// test/setup.ts
import '@testing-library/jest-dom/vitest';
import { cleanup } from '@testing-library/react';
import { afterEach } from 'vitest';

afterEach(() => {
  cleanup();
});
```

### Jest + React Testing Library

```typescript
// jest.config.ts
import nextJest from 'next/jest';

const createJestConfig = nextJest({ dir: './' });

const config = {
  testEnvironment: 'jsdom',
  setupFilesAfterSetup: ['<rootDir>/test/setup.ts'],
  moduleNameMapper: {
    '^@/(.*)$': '<rootDir>/src/$1',
  },
};

export default createJestConfig(config);
```

## 2. Client Component 테스트

```typescript
// src/components/counter.tsx
'use client';
import { useState } from 'react';

export function Counter({ initial = 0 }: { initial?: number }) {
  const [count, setCount] = useState(initial);
  return (
    <div>
      <span data-testid="count">{count}</span>
      <button onClick={() => setCount(c => c + 1)}>+</button>
      <button onClick={() => setCount(c => c - 1)}>-</button>
    </div>
  );
}
```

```typescript
// src/components/counter.test.tsx
import { render, screen, fireEvent } from '@testing-library/react';
import { Counter } from './counter';

describe('Counter', () => {
  it('should render initial count', () => {
    render(<Counter initial={5} />);
    expect(screen.getByTestId('count')).toHaveTextContent('5');
  });

  it('should increment on + click', () => {
    render(<Counter />);
    fireEvent.click(screen.getByText('+'));
    expect(screen.getByTestId('count')).toHaveTextContent('1');
  });

  it('should decrement on - click', () => {
    render(<Counter initial={3} />);
    fireEvent.click(screen.getByText('-'));
    expect(screen.getByTestId('count')).toHaveTextContent('2');
  });
});
```

## 3. Server Component 테스트

Server Component는 async 함수이므로 직접 호출하여 반환값을 테스트한다.

```typescript
// src/app/users/page.tsx
import { getUsers } from '@/lib/api';

export default async function UsersPage() {
  const users = await getUsers();
  return (
    <ul>
      {users.map(user => (
        <li key={user.id}>{user.name}</li>
      ))}
    </ul>
  );
}
```

```typescript
// src/app/users/page.test.tsx
import { render, screen } from '@testing-library/react';
import UsersPage from './page';

// API mock
vi.mock('@/lib/api', () => ({
  getUsers: vi.fn().mockResolvedValue([
    { id: 1, name: 'Alice' },
    { id: 2, name: 'Bob' },
  ]),
}));

describe('UsersPage', () => {
  it('should render user list', async () => {
    const page = await UsersPage();
    render(page);

    expect(screen.getByText('Alice')).toBeInTheDocument();
    expect(screen.getByText('Bob')).toBeInTheDocument();
  });
});
```

## 4. API Route 테스트

```typescript
// src/app/api/users/route.ts
import { NextRequest, NextResponse } from 'next/server';

export async function GET() {
  const users = await db.user.findMany();
  return NextResponse.json(users);
}

export async function POST(request: NextRequest) {
  const body = await request.json();
  const user = await db.user.create({ data: body });
  return NextResponse.json(user, { status: 201 });
}
```

```typescript
// src/app/api/users/route.test.ts
import { GET, POST } from './route';
import { NextRequest } from 'next/server';

vi.mock('@/lib/db', () => ({
  db: {
    user: {
      findMany: vi.fn(),
      create: vi.fn(),
    },
  },
}));

describe('GET /api/users', () => {
  it('should return users', async () => {
    const { db } = await import('@/lib/db');
    (db.user.findMany as any).mockResolvedValue([{ id: 1, name: 'Alice' }]);

    const response = await GET();
    const data = await response.json();

    expect(response.status).toBe(200);
    expect(data).toHaveLength(1);
  });
});

describe('POST /api/users', () => {
  it('should create user', async () => {
    const { db } = await import('@/lib/db');
    (db.user.create as any).mockResolvedValue({ id: 1, name: 'Alice' });

    const request = new NextRequest('http://localhost/api/users', {
      method: 'POST',
      body: JSON.stringify({ name: 'Alice' }),
    });

    const response = await POST(request);
    const data = await response.json();

    expect(response.status).toBe(201);
    expect(data.name).toBe('Alice');
  });
});
```

## 5. MSW (Mock Service Worker)

외부 API 호출을 인터셉트한다.

```typescript
// test/mocks/handlers.ts
import { http, HttpResponse } from 'msw';

export const handlers = [
  http.get('/api/users', () => {
    return HttpResponse.json([
      { id: 1, name: 'Alice' },
      { id: 2, name: 'Bob' },
    ]);
  }),
  http.post('/api/users', async ({ request }) => {
    const body = await request.json();
    return HttpResponse.json({ id: 3, ...body }, { status: 201 });
  }),
];
```

```typescript
// test/mocks/server.ts
import { setupServer } from 'msw/node';
import { handlers } from './handlers';

export const server = setupServer(...handlers);
```

```typescript
// test/setup.ts
import { server } from './mocks/server';

beforeAll(() => server.listen());
afterEach(() => server.resetHandlers());
afterAll(() => server.close());
```

## 6. Hook 테스트

```typescript
import { renderHook, act } from '@testing-library/react';
import { useDebounce } from './use-debounce';

describe('useDebounce', () => {
  beforeEach(() => { vi.useFakeTimers(); });
  afterEach(() => { vi.useRealTimers(); });

  it('should debounce value', () => {
    const { result, rerender } = renderHook(
      ({ value }) => useDebounce(value, 300),
      { initialProps: { value: 'hello' } },
    );

    expect(result.current).toBe('hello');

    rerender({ value: 'world' });
    expect(result.current).toBe('hello'); // 아직 변경 안됨

    act(() => { vi.advanceTimersByTime(300); });
    expect(result.current).toBe('world'); // 디바운스 후 변경
  });
});
```

## 7. E2E 테스트 (Playwright)

```typescript
// e2e/users.spec.ts
import { test, expect } from '@playwright/test';

test.describe('Users Page', () => {
  test('should display user list', async ({ page }) => {
    await page.goto('/users');
    await expect(page.getByRole('list')).toBeVisible();
    await expect(page.getByRole('listitem')).toHaveCount(3);
  });

  test('should create new user', async ({ page }) => {
    await page.goto('/users/new');
    await page.getByLabel('Name').fill('Alice');
    await page.getByLabel('Email').fill('alice@test.com');
    await page.getByRole('button', { name: 'Create' }).click();

    await expect(page).toHaveURL(/\/users\/\d+/);
    await expect(page.getByText('Alice')).toBeVisible();
  });
});
```
