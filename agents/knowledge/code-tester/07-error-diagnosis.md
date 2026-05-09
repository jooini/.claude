# Error Diagnosis

---

## 1. 에러 진단 절차

```
1. 에러 메시지 전체 읽기 (첫 줄 ≠ 근본 원인인 경우 많음)
2. 에러 유형 분류 (린트 / 타입 / 빌드 / 런타임 / 테스트)
3. 에러 발생 위치 확인 (파일:라인)
4. 스택 트레이스 역추적 (있는 경우)
5. 최근 변경 사항과 연관 분석 (git diff)
6. 재현 조건 확인
```

## 2. Node.js / TypeScript 에러

### 모듈 관련

| 에러 | 원인 | 해결 |
|------|------|------|
| `Cannot find module 'X'` | 패키지 미설치 또는 경로 오류 | `npm install X` 또는 경로 수정 |
| `ERR_MODULE_NOT_FOUND` | ESM 모듈 해석 실패 | 확장자 명시 (.js) 또는 package.json `type` 확인 |
| `ERR_REQUIRE_ESM` | CJS에서 ESM 모듈 require | dynamic import 사용 또는 패키지 다운그레이드 |
| `SyntaxError: Cannot use import statement outside a module` | ESM 문법을 CJS 환경에서 사용 | `"type": "module"` 추가 또는 빌드 설정 수정 |
| `ERR_UNKNOWN_FILE_EXTENSION` | ts 파일 직접 실행 | tsx, ts-node 사용 또는 빌드 후 실행 |

### 런타임 에러

| 에러 | 원인 | 해결 |
|------|------|------|
| `TypeError: X is not a function` | import 오류 또는 undefined 호출 | export/import 확인, default vs named |
| `TypeError: Cannot read properties of undefined` | null/undefined 접근 | optional chaining 또는 null 체크 |
| `RangeError: Maximum call stack size exceeded` | 무한 재귀 | 재귀 종료 조건 확인 |
| `EADDRINUSE` | 포트 충돌 | 기존 프로세스 종료 또는 포트 변경 |
| `ECONNREFUSED` | 연결 대상 미기동 | DB/서비스 기동 확인 |
| `ENOMEM` | 메모리 부족 | `--max-old-space-size` 조정 |

### 의존성 에러

| 에러 | 원인 | 해결 |
|------|------|------|
| `ERESOLVE unable to resolve dependency tree` | 의존성 충돌 | `--legacy-peer-deps` 또는 버전 조정 |
| `peer dep missing` | 피어 의존성 미설치 | 명시적 설치 |
| `ENOENT: no such file or directory` | node_modules 손상 | `rm -rf node_modules && npm install` |

## 3. Python 에러

### Import 관련

| 에러 | 원인 | 해결 |
|------|------|------|
| `ModuleNotFoundError: No module named 'X'` | 패키지 미설치 또는 가상환경 불일치 | `pip install X` 또는 venv 활성화 확인 |
| `ImportError: cannot import name 'X' from 'Y'` | 존재하지 않는 이름 import | 패키지 버전 확인 (API 변경) |
| `ImportError: attempted relative import with no known parent package` | 상대 import 오류 | 패키지 구조 확인, `-m` 플래그로 실행 |

### 런타임 에러

| 에러 | 원인 | 해결 |
|------|------|------|
| `AttributeError: 'NoneType' has no attribute 'X'` | None 객체 속성 접근 | None 체크 추가 |
| `KeyError: 'X'` | dict에 키 없음 | `.get('X', default)` 사용 |
| `RecursionError` | 무한 재귀 | 종료 조건 확인 |
| `PermissionError` | 파일/디렉토리 권한 | chmod 또는 sudo |

## 4. 빌드 에러 패턴

### Webpack / Vite

| 에러 | 원인 | 해결 |
|------|------|------|
| `Module parse failed: Unexpected token` | loader 미설정 | 해당 파일 유형의 loader/plugin 추가 |
| `Chunk loading failed` | 코드 스플리팅 오류 | chunk 이름 충돌 확인, publicPath 설정 |
| `FATAL ERROR: CALL_AND_RETRY_LAST Allocation failed` | 빌드 메모리 부족 | `NODE_OPTIONS=--max-old-space-size=4096` |

### Docker 빌드

| 에러 | 원인 | 해결 |
|------|------|------|
| `COPY failed: file not found` | 파일 경로 오류 또는 .dockerignore | 경로 확인, .dockerignore 검토 |
| `returned a non-zero code: 1` | RUN 명령 실패 | 해당 RUN 명령 독립 실행으로 디버깅 |
| `no space left on device` | 디스크 공간 부족 | `docker system prune` |

## 5. 테스트 에러 패턴

### 비동기 관련

```typescript
// ❌ 흔한 실수 — await 누락
it('should fetch user', () => {
  const user = service.findOne(1); // Promise 반환
  expect(user).toBeDefined(); // Promise 객체 자체를 검사
});

// ✅ 수정
it('should fetch user', async () => {
  const user = await service.findOne(1);
  expect(user).toBeDefined();
});
```

### Mock 관련

```typescript
// ❌ mock이 원본을 완전히 대체하지 못함
jest.mock('./userService'); // 모든 메서드가 undefined 반환

// ✅ 필요한 메서드만 mock
jest.mock('./userService', () => ({
  findOne: jest.fn().mockResolvedValue({ id: 1, name: 'Test' }),
}));
```

### 환경 의존성

```
❌ 테스트가 특정 순서에서만 통과 → 테스트 간 상태 공유
❌ 로컬에서만 통과, CI에서 실패 → 환경 변수, 타임존, 파일 경로
❌ 간헐적 실패 → 타이밍 의존성, 레이스 컨디션
```

## 6. 에러 메시지에서 정보 추출

### 스택 트레이스 읽기

```
Error: Connection refused
    at TCPConnectWrap.afterConnect [as oncomplete] (net.js:1141:16)  ← 내부
    at Socket.connect (net.js:996:12)                                 ← 내부
    at DatabaseClient.connect (src/database.ts:45:12)                 ← 우리 코드 ★
    at UserService.findAll (src/user.service.ts:23:5)                 ← 호출 지점 ★
    at UserController.getUsers (src/user.controller.ts:15:10)         ← 진입점
```

**우리 코드**에서 가장 안쪽(아래쪽) 프레임이 실제 에러 발생 지점이다.

### 에러 코드 활용

```bash
# Node.js 에러 코드
# ERR_ prefix → Node.js 내장 에러
# E prefix → OS 레벨 에러 (ENOENT, EACCES, ECONNREFUSED)

# TypeScript 에러 코드
# TS + 숫자 → tsc 에러 (TS2322, TS2345 등)

# ESLint 에러 코드
# 플러그인/규칙명 → @typescript-eslint/no-unused-vars
```

## 7. 연쇄 에러 처리

한 에러가 수십 개의 후속 에러를 유발하는 경우:

1. **첫 번째 에러**만 수정 — 나머지는 파생 에러일 가능성 높음
2. **타입 에러 cascade** — 하나의 타입 수정으로 다수 에러 해소
3. **import 에러** — 모듈 미발견 시 해당 모듈의 모든 export가 에러
4. 수정 후 재실행하여 남은 에러 확인
