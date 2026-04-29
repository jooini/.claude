# Preexisting Errors

---

## 1. 개요

코드 변경 후 검증 실행 시 발견되는 에러 중, **변경 전부터 존재하던 에러**와 **새로 도입된 에러**를 구분해야 한다. 새 에러만 리포트하는 것이 핵심이다.

## 2. 변경 파일 식별

### git diff 기반

```bash
# 커밋되지 않은 변경 (staged + unstaged)
git diff --name-only HEAD

# staged만
git diff --name-only --cached

# 특정 커밋 대비
git diff --name-only main...HEAD

# 변경 유형별 필터
git diff --name-only --diff-filter=ACMR HEAD  # Added, Copied, Modified, Renamed만
# D(Deleted)는 제외 — 삭제된 파일은 검증 대상 아님
```

### 변경 라인 범위 추출

```bash
# unified diff에서 변경 라인 번호 추출
git diff -U0 HEAD -- src/user.service.ts | grep '^@@' | \
  sed -E 's/^@@ -[0-9,]+ \+([0-9]+)(,([0-9]+))? @@.*/\1 \3/'
# 출력: "15 3" → 15번째 줄부터 3줄 변경
```

```typescript
// 변경 라인 범위 파싱
interface ChangedRange {
  file: string;
  startLine: number;
  endLine: number;
}

// git diff 파싱하여 변경 라인 범위 목록 생성
// → 에러 발생 라인이 이 범위 안에 있으면 "새 에러"
```

## 3. 새 에러 vs 기존 에러 분류

### 분류 기준

| 조건 | 분류 |
|------|------|
| 변경된 파일의 변경된 라인에서 발생 | **새 에러** (높은 확신) |
| 변경된 파일의 변경되지 않은 라인에서 발생 | **기존 에러** (보통 확신) |
| 변경되지 않은 파일에서 발생 | **기존 에러** (높은 확신) |
| 변경된 파일에 의존하는 파일에서 발생 | **파생 에러** (확인 필요) |

### 파생 에러 판별

```
A.ts가 B.ts를 import하고 있을 때:
- B.ts의 export 시그니처를 변경하면 A.ts에서 타입 에러 발생
- A.ts는 변경되지 않았지만 이 에러는 "새 에러"로 분류해야 함

판별 방법:
1. B.ts가 변경된 파일 목록에 있는지 확인
2. A.ts의 에러가 B.ts에서 import한 심볼과 관련있는지 확인
3. 관련있으면 "새 에러(파생)"으로 분류
```

## 4. 도구별 적용

### ESLint

```bash
# 변경 파일만 린트
CHANGED=$(git diff --name-only --diff-filter=ACMR HEAD -- '*.ts' '*.tsx')
[ -n "$CHANGED" ] && npx eslint $CHANGED --format json > lint-new.json

# 전체 린트 결과에서 변경 파일 에러만 필터링
npx eslint . --format json | jq --argjson files "$(echo $CHANGED | jq -R -s 'split("\n") | map(select(. != ""))')" \
  '[.[] | select(.filePath as $f | $files | any(. == $f)) | select(.errorCount > 0)]'
```

### TypeScript (tsc)

tsc는 프로젝트 전체를 체크하므로 변경 파일만 체크할 수 없다.

```bash
# 전체 체크 후 변경 파일의 에러만 필터
npx tsc --noEmit 2>&1 | grep -E "^($(git diff --name-only HEAD | tr '\n' '|' | sed 's/|$//'))"
```

### Jest / Vitest

```bash
# 변경 관련 테스트만 실행
npx jest --changedSince=HEAD~1

# 특정 파일의 테스트만
npx jest --findRelatedTests src/user.service.ts
```

## 5. 베이스라인 비교 방식

### 방법 1: 변경 전 결과 캐싱

```bash
# 베이스라인 생성 (main 브랜치)
git stash
npx eslint . --format json > baseline-lint.json
npx tsc --noEmit 2>&1 > baseline-type.txt
git stash pop

# 현재 결과
npx eslint . --format json > current-lint.json
npx tsc --noEmit 2>&1 > current-type.txt

# diff
diff baseline-lint.json current-lint.json
diff baseline-type.txt current-type.txt
```

### 방법 2: 에러 fingerprint 비교

```typescript
// 에러를 고유하게 식별하는 fingerprint 생성
interface ErrorFingerprint {
  file: string;
  rule: string;      // ESLint rule 또는 TS 에러 코드
  message: string;   // 정규화된 메시지
  line?: number;     // 라인은 변경될 수 있으므로 보조 정보
}

// fingerprint 해시 비교로 새 에러 식별
// baseline에 없는 fingerprint = 새 에러
```

## 6. 리포트 형식

```markdown
## 검증 결과

### 🆕 새로 도입된 에러 (3건)
| 유형 | 파일 | 라인 | 내용 |
|------|------|------|------|
| Type | src/user.service.ts | 45 | TS2322: Type 'string' is not assignable |
| Lint | src/user.controller.ts | 12 | @typescript-eslint/no-explicit-any |
| Test | tests/user.spec.ts | 78 | Expected 200, received 404 |

### ⚠️ 기존 에러 (참고, 12건)
변경과 무관한 기존 에러입니다. 별도 수정이 필요합니다.

### ✅ 검증 통과 항목
- [x] 빌드 성공
- [x] 린트 (새 에러 없음: 0건)
- [ ] 타입 체크 (새 에러: 1건)
- [ ] 테스트 (실패: 1건)
```

## 7. 엣지 케이스

### 파일 이동/이름 변경

```bash
# git이 rename으로 감지한 경우
git diff --name-status HEAD
# R100	src/old.ts	src/new.ts  → 100% rename

# rename된 파일의 에러는 "기존 에러"로 분류
# 단, 이동 과정에서 내용도 변경되었으면 변경 라인의 에러만 "새 에러"
```

### 새 파일

새로 추가된 파일(`A` status)의 모든 에러는 "새 에러"다.

### 삭제된 코드

삭제된 라인에서 참조하던 다른 파일의 코드가 이제 미사용이 되어 린트 에러가 발생할 수 있다. 이 경우 "파생 에러"로 분류한다.
