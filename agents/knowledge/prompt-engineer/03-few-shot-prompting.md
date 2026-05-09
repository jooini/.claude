# Few-shot 프롬프팅

> 참조 링크: https://docs.anthropic.com/en/docs/build-with-claude/prompt-engineering/multishot-prompting, https://arxiv.org/abs/2005.14165

---

## Few-shot 프롬프팅 개요

Few-shot 프롬프팅은 원하는 입력-출력 패턴의 예시를 제공해서 모델의 응답 형태를 유도하는 기법이다. 명시적 지시보다 예시가 더 효과적인 경우가 많다.

### Zero-shot vs Few-shot vs Many-shot

- **Zero-shot**: 예시 없이 지시만으로 작업 수행
- **One-shot**: 예시 1개 제공
- **Few-shot**: 예시 2~5개 제공
- **Many-shot**: 예시 10개 이상 제공 (토큰 비용 증가)

## 예시 선택 기준

### 1. 대표성 (Representativeness)

예시가 실제 사용 사례를 대표해야 한다.

```markdown
## 작업: API 엔드포인트 코드 리뷰

### 예시 1 — 보안 이슈
입력:
\```typescript
@Post('/login')
async login(@Body() body: any) {
  const user = await this.db.query(`SELECT * FROM users WHERE email = '${body.email}'`);
}
\```

출력:
- [심각] SQL Injection 취약점: 문자열 보간 대신 파라미터 바인딩 사용 필요
- [심각] DTO 타입 미정의: `any` 대신 LoginDto 클래스 사용 필요
- 수정 코드: (수정된 전체 코드)

### 예시 2 — 성능 이슈
입력:
\```typescript
@Get('/users')
async findAll() {
  const users = await this.userRepo.find({ relations: ['posts', 'comments', 'likes'] });
  return users;
}
\```

출력:
- [경고] N+1 쿼리 가능성: 3개 relation 동시 로드
- [권장] pagination 미적용: 대량 데이터 시 OOM 위험
- 수정 코드: (수정된 전체 코드)
```

### 2. 다양성 (Diversity)

예시가 다양한 케이스를 커버해야 한다. 비슷한 예시만 제공하면 모델이 패턴을 과도하게 학습한다.

```markdown
# 나쁜 예: 비슷한 케이스만
예시 1: React 버튼 컴포넌트 작성
예시 2: React 입력 컴포넌트 작성
예시 3: React 체크박스 컴포넌트 작성

# 좋은 예: 다양한 케이스
예시 1: React 버튼 컴포넌트 (기본 UI)
예시 2: React 데이터 테이블 (복잡한 상태 관리)
예시 3: React 인증 폼 (API 연동 + 에러 핸들링)
```

### 3. 난이도 균형

쉬운 케이스와 어려운 케이스를 섞는다.

### 4. 엣지 케이스 포함

일반적인 케이스뿐 아니라 경계 사례도 예시에 포함한다.

```markdown
### 예시 3 — 엣지 케이스 (빈 입력)
입력: ""
출력: { "error": "입력이 비어있습니다", "code": "EMPTY_INPUT" }

### 예시 4 — 엣지 케이스 (특수 문자)
입력: "<script>alert('xss')</script>"
출력: { "error": "허용되지 않는 문자가 포함되어 있습니다", "code": "INVALID_CHARS" }
```

## 예시 수 결정

### 권장 기준

| 작업 복잡도 | 권장 예시 수 | 근거 |
|-----------|------------|------|
| 단순 분류 | 2~3개 | 패턴이 단순해서 적은 예시로 충분 |
| 형식 변환 | 3~5개 | 다양한 입력 형태 커버 필요 |
| 복잡한 추론 | 5~8개 | 추론 과정의 다양한 경로 시연 |
| 코드 생성 | 2~3개 | 예시가 길어 토큰 비용 고려 |

### 수확 체감 법칙

예시 수를 늘릴수록 효과가 체감한다. 보통 3~5개에서 최적 균형점에 도달한다.

## 형식 일관성

### 입출력 형식 통일

모든 예시의 입력/출력 형식이 동일해야 한다.

```markdown
# 나쁜 예: 형식 불일치
예시 1 입력: "사과" → 출력: fruit
예시 2 입력: dog → 출력: "동물"
예시 3: 자동차는 vehicle입니다

# 좋은 예: 형식 일치
예시 1 입력: "사과" → 출력: "fruit"
예시 2 입력: "강아지" → 출력: "animal"
예시 3 입력: "자동차" → 출력: "vehicle"
```

### 구분자 일관성

예시 간 구분을 명확히 한다.

```markdown
## 예시

<example>
H: 이 코드의 시간 복잡도는?
\```python
for i in range(n):
    for j in range(n):
        print(i, j)
\```
A: O(n^2) — 이중 루프로 n*n번 반복
</example>

<example>
H: 이 코드의 시간 복잡도는?
\```python
for i in range(n):
    print(i)
\```
A: O(n) — 단일 루프로 n번 반복
</example>
```

## 반례 (Negative Examples) 포함

### 반례의 효과

"이렇게 하지 마"를 보여주면 모델이 원치 않는 패턴을 명확히 인식한다.

```markdown
## 좋은 응답 예시
입력: "NestJS에서 인증을 어떻게 구현하나요?"
출력:
\```typescript
@Injectable()
export class AuthGuard implements CanActivate {
  // 전체 구현 코드
}
\```

## 나쁜 응답 예시 (이렇게 하지 마)
입력: "NestJS에서 인증을 어떻게 구현하나요?"
출력:
"인증은 매우 중요한 보안 요소입니다! NestJS에서는 여러 가지 방법이 있는데요,
Passport.js를 사용하는 방법, JWT를 직접 구현하는 방법, OAuth를 사용하는 방법...
(장황한 설명만 있고 코드 없음)"
```

### 반례 배치 위치

반례는 정례(positive example) 뒤에 배치한다. 정례를 먼저 보여줘야 모델이 "올바른 패턴"을 먼저 학습한다.

## 고급 패턴

### Chain-of-Thought와 결합

예시에 추론 과정을 포함하면 복잡한 작업의 품질이 올라간다.

```markdown
### 예시
입력: "이 쿼리가 느린 이유를 분석해줘"
\```sql
SELECT * FROM orders o
JOIN users u ON o.user_id = u.id
WHERE o.created_at > '2024-01-01'
ORDER BY o.total DESC;
\```

출력:
1. `SELECT *`는 불필요한 컬럼까지 조회 → 필요한 컬럼만 명시
2. `o.created_at` 필터 → created_at 인덱스 확인 필요
3. `ORDER BY o.total DESC` → total 컬럼 인덱스 또는 복합 인덱스 필요
4. JOIN 시 user_id FK 인덱스 확인 필요

권장 수정:
\```sql
SELECT o.id, o.total, o.created_at, u.name
FROM orders o
JOIN users u ON o.user_id = u.id
WHERE o.created_at > '2024-01-01'
ORDER BY o.total DESC
LIMIT 100;
\```
```

### 난이도 점진적 증가

예시를 쉬운 것부터 어려운 것 순서로 배치하면 모델이 패턴을 더 잘 학습한다.

```markdown
예시 1: 단순 CRUD (기본)
예시 2: 관계가 있는 CRUD (중간)
예시 3: 트랜잭션 + 에러 핸들링 (복잡)
```

## Few-shot 프롬프팅 체크리스트

- [ ] 예시가 실제 사용 사례를 대표하는가
- [ ] 다양한 케이스를 커버하는가
- [ ] 엣지 케이스가 포함되어 있는가
- [ ] 모든 예시의 형식이 일관적인가
- [ ] 반례가 포함되어 있는가
- [ ] 예시 수가 적절한가 (3~5개 권장)
- [ ] 토큰 비용 대비 효과가 합리적인가
