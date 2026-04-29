# 프론트엔드 리뷰

> 참조 링크: https://react.dev/reference/react, https://web.dev/accessibility/, https://nextjs.org/docs

---

## 개요

프론트엔드 코드 리뷰는 불필요한 리렌더링, 접근성(a11y), 반응형 대응, XSS 방어, 상태 관리 적절성을 중심으로 검토한다. 사용자 경험과 직결되는 영역이므로 성능과 보안 모두 중요하다.

## 1. 리렌더링

### 불필요한 리렌더링 원인

```tsx
// ❌ 매 렌더마다 새 객체/배열 생성 → 자식 컴포넌트 불필요 리렌더
function ParentComponent() {
  const style = { color: 'red', fontSize: 16 }; // 매번 새 객체
  const items = ['a', 'b', 'c'];                 // 매번 새 배열

  return <ChildComponent style={style} items={items} />;
}

// ❌ 인라인 함수 → 매 렌더마다 새 참조
function TodoList({ todos }: Props) {
  return todos.map(todo => (
    <TodoItem
      key={todo.id}
      todo={todo}
      onDelete={() => deleteTodo(todo.id)} // 매번 새 함수
    />
  ));
}

// ✅ useMemo/useCallback으로 참조 안정화
function ParentComponent() {
  const style = useMemo(() => ({ color: 'red', fontSize: 16 }), []);
  const items = useMemo(() => ['a', 'b', 'c'], []);

  return <ChildComponent style={style} items={items} />;
}

function TodoList({ todos }: Props) {
  const handleDelete = useCallback((id: string) => {
    deleteTodo(id);
  }, []);

  return todos.map(todo => (
    <TodoItem
      key={todo.id}
      todo={todo}
      onDelete={handleDelete}
    />
  ));
}
```

### 리렌더링 최적화

```tsx
// ❌ 상위 상태 변경이 무관한 자식도 리렌더
function App() {
  const [count, setCount] = useState(0); // count 변경 → HeavyList도 리렌더

  return (
    <div>
      <button onClick={() => setCount(c => c + 1)}>Count: {count}</button>
      <HeavyList items={items} /> {/* count와 무관한데 매번 리렌더 */}
    </div>
  );
}

// ✅ React.memo로 불필요 리렌더 방지
const HeavyList = React.memo(({ items }: { items: Item[] }) => {
  return items.map(item => <ItemRow key={item.id} item={item} />);
});

// ✅ 상태를 사용하는 곳으로 내리기 (State Colocation)
function App() {
  return (
    <div>
      <Counter /> {/* count 상태를 여기에 격리 */}
      <HeavyList items={items} />
    </div>
  );
}

function Counter() {
  const [count, setCount] = useState(0);
  return <button onClick={() => setCount(c => c + 1)}>Count: {count}</button>;
}
```

### 리렌더링 체크리스트

- [ ] JSX 내에 인라인 객체/배열 리터럴이 있는가?
- [ ] 이벤트 핸들러가 인라인 화살표 함수로 전달되는가? (리스트 렌더 시 특히 주의)
- [ ] 비싼 계산이 useMemo 없이 매 렌더마다 실행되는가?
- [ ] 상태가 필요 이상으로 상위 컴포넌트에 위치하는가?
- [ ] React.memo가 필요한 무거운 컴포넌트에 적용되어 있는가?

## 2. 접근성 (a11y)

### 시맨틱 HTML

```tsx
// ❌ div로 모든 것을 만듦
<div onClick={handleClick}>제출</div>
<div className="header">페이지 제목</div>
<div className="nav-item" onClick={goToHome}>홈</div>

// ✅ 시맨틱 요소 사용
<button onClick={handleClick}>제출</button>
<h1>페이지 제목</h1>
<nav>
  <a href="/" onClick={goToHome}>홈</a>
</nav>
```

### ARIA 속성

```tsx
// ❌ 접근성 정보 부재
<img src="/logo.png" />
<input type="text" />
<div className="modal">...</div>
<span className="spinner" />

// ✅ 적절한 ARIA 속성
<img src="/logo.png" alt="회사 로고" />
<input type="text" aria-label="검색어 입력" placeholder="검색..." />
<div role="dialog" aria-modal="true" aria-labelledby="modal-title">
  <h2 id="modal-title">설정</h2>
  ...
</div>
<span className="spinner" role="status" aria-label="로딩 중" />

// 아이콘 버튼에 레이블
// ❌
<button onClick={onClose}><CloseIcon /></button>

// ✅
<button onClick={onClose} aria-label="닫기"><CloseIcon aria-hidden="true" /></button>
```

### 키보드 접근성

```tsx
// ❌ 마우스만 고려
<div onClick={handleSelect} className="option">
  옵션 1
</div>

// ✅ 키보드 접근 가능
<div
  role="option"
  tabIndex={0}
  onClick={handleSelect}
  onKeyDown={(e) => {
    if (e.key === 'Enter' || e.key === ' ') handleSelect();
  }}
  aria-selected={isSelected}
>
  옵션 1
</div>

// 더 나은 방법: 네이티브 요소 사용
<button onClick={handleSelect} aria-pressed={isSelected}>
  옵션 1
</button>
```

### 접근성 체크리스트

- [ ] `<img>`에 의미 있는 `alt` 텍스트가 있는가? (장식용이면 `alt=""`)
- [ ] 클릭 가능한 요소가 `<button>` 또는 `<a>`인가? (div onClick 지양)
- [ ] 모든 폼 입력에 label이 연결되어 있는가?
- [ ] 모달/드롭다운에 focus trap과 ESC 닫기가 있는가?
- [ ] 색상 대비가 WCAG 2.1 AA 기준(4.5:1)을 충족하는가?
- [ ] 키보드만으로 모든 기능을 사용할 수 있는가?

## 3. 반응형

### 미디어 쿼리 / 컨테이너 쿼리

```tsx
// ❌ 고정 픽셀, 모바일 미고려
<div style={{ width: '1200px', padding: '40px' }}>
  <div style={{ display: 'flex', gap: '20px' }}>
    <div style={{ width: '800px' }}>메인</div>
    <div style={{ width: '380px' }}>사이드바</div>
  </div>
</div>

// ✅ 반응형 레이아웃 (Tailwind 예시)
<div className="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8">
  <div className="flex flex-col md:flex-row gap-4 md:gap-6">
    <main className="flex-1">메인</main>
    <aside className="w-full md:w-80">사이드바</aside>
  </div>
</div>
```

### 반응형 체크리스트

- [ ] 모바일(320px ~)에서 레이아웃이 깨지지 않는가?
- [ ] 고정 너비(px)가 아닌 상대 단위(%, rem, vw)를 사용하는가?
- [ ] 터치 타겟이 최소 44x44px인가? (모바일 탭 영역)
- [ ] 이미지가 뷰포트에 맞게 반응하는가? (`max-width: 100%`)
- [ ] 텍스트가 줄바꿈 없이 잘리는 곳이 없는가?

## 4. XSS

### XSS 취약 패턴

```tsx
// ❌ dangerouslySetInnerHTML 무분별 사용
function Comment({ content }: { content: string }) {
  return <div dangerouslySetInnerHTML={{ __html: content }} />;
  // content에 <script>alert('xss')</script> 포함 가능
}

// ❌ URL에 사용자 입력 직접 삽입
function UserLink({ url }: { url: string }) {
  return <a href={url}>링크</a>;
  // url = "javascript:alert('xss')" 가능
}

// ✅ 사용자 입력은 반드시 새니타이징
import DOMPurify from 'dompurify';

function Comment({ content }: { content: string }) {
  const sanitized = DOMPurify.sanitize(content);
  return <div dangerouslySetInnerHTML={{ __html: sanitized }} />;
}

// ✅ URL 검증
function UserLink({ url }: { url: string }) {
  const isValid = url.startsWith('https://') || url.startsWith('http://');
  if (!isValid) return null;
  return <a href={url} rel="noopener noreferrer" target="_blank">링크</a>;
}
```

### XSS 체크리스트

- [ ] `dangerouslySetInnerHTML` 사용 시 DOMPurify 등으로 새니타이징하는가?
- [ ] 사용자 입력이 URL(`href`, `src`)에 직접 삽입되지 않는가?
- [ ] `eval()`, `new Function()`, `innerHTML` 직접 사용이 없는가?
- [ ] 외부 링크에 `rel="noopener noreferrer"`가 있는가?
- [ ] CSP(Content Security Policy) 헤더가 설정되어 있는가?

## 5. 상태 관리

### 상태 위치 판단

```tsx
// ❌ 모든 상태를 전역(Redux/Zustand)에 넣음
// store.ts
interface GlobalState {
  user: User;                    // 전역 적절
  theme: 'light' | 'dark';      // 전역 적절
  isModalOpen: boolean;          // 이건 로컬이면 충분
  searchQuery: string;           // 이것도 로컬
  selectedTab: number;           // 이것도 로컬
  formData: FormData;            // 이것도 로컬
}

// ✅ 상태 위치 기준
// 전역 상태: 여러 페이지/컴포넌트에서 공유
// - 인증 정보 (user, token)
// - 테마, 언어 설정
// - 장바구니 (여러 페이지에서 접근)

// 로컬 상태: 컴포넌트 내부에서만 사용
// - 모달 열림/닫힘
// - 폼 입력값
// - 토글/탭 상태
// - 호버/포커스 상태

// 서버 상태: API 데이터 (React Query/SWR)
// - 사용자 목록
// - 주문 내역
// - 상품 정보
```

### 불필요한 상태

```tsx
// ❌ 파생 가능한 값을 상태로 관리
function CartSummary({ items }: Props) {
  const [total, setTotal] = useState(0);
  const [itemCount, setItemCount] = useState(0);

  useEffect(() => {
    setTotal(items.reduce((sum, item) => sum + item.price * item.qty, 0));
    setItemCount(items.reduce((sum, item) => sum + item.qty, 0));
  }, [items]);

  return <div>{itemCount}개 상품, 합계: {total}원</div>;
}

// ✅ 파생 값은 계산으로 처리
function CartSummary({ items }: Props) {
  const total = useMemo(
    () => items.reduce((sum, item) => sum + item.price * item.qty, 0),
    [items],
  );
  const itemCount = useMemo(
    () => items.reduce((sum, item) => sum + item.qty, 0),
    [items],
  );

  return <div>{itemCount}개 상품, 합계: {total}원</div>;
}
```

### 상태 관리 체크리스트

- [ ] 로컬 상태로 충분한 것이 전역에 있지 않은가?
- [ ] 파생 가능한 값을 별도 상태로 관리하지 않는가?
- [ ] useEffect로 상태를 동기화하는 패턴이 있는가? (상태 파생으로 대체 가능)
- [ ] 서버 데이터를 React Query/SWR로 관리하는가? (직접 fetch + useState 지양)
- [ ] 폼 상태가 적절한 라이브러리(React Hook Form 등)로 관리되는가?
- [ ] 상태 업데이트가 불변성을 유지하는가?

## 리뷰어 종합 체크리스트

| 항목 | 확인 내용 | 심각도 |
|------|----------|--------|
| XSS | dangerouslySetInnerHTML 미새니타이징 | P0 |
| XSS | 사용자 입력 URL 직접 삽입 | P0 |
| 접근성 | 클릭 요소에 키보드/스크린리더 미지원 | P1 |
| 리렌더링 | 리스트 렌더에서 인라인 함수 전달 | P1 |
| 반응형 | 모바일 레이아웃 미지원 | P1 |
| 상태 위치 | 로컬이면 충분한 상태가 전역에 존재 | P2 |
| 파생 상태 | useEffect로 상태 동기화 | P2 |
| alt 텍스트 | img에 alt 누락 | P2 |
