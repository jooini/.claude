# Git Workflow

> 원본: https://ironact.gitbook.io/ironact-docs/CrEhRPJQJpia3xh9iqbi/knowledge-fe/git-workflow

---

## 1. 커밋 메시지 컨벤션 (Conventional Commits)

```
<type>(<scope>): <subject>

<body>

<footer>
```

**type:**
| 타입 | 설명 |
|------|------|
| `feat` | 새 기능 |
| `fix` | 버그 수정 |
| `refactor` | 리팩토링 (기능 변경 없음) |
| `style` | 포맷, 세미콜론 등 (로직 변경 없음) |
| `test` | 테스트 추가/수정 |
| `docs` | 문서 수정 |
| `chore` | 빌드, 의존성 등 기타 |
| `perf` | 성능 개선 |
| `ci` | CI 설정 변경 |

```bash
feat(auth): 소셜 로그인 구글 연동
fix(payment): 결제 완료 후 재고 미감소 버그 수정
refactor(user): useUser 훅 타입 정의 개선
chore: @tanstack/react-query 5.0으로 업그레이드
```

---

## 2. 브랜치 네이밍

```
feature/{이슈번호}-{설명}    feature/123-add-google-login
fix/{이슈번호}-{설명}        fix/456-payment-stock-bug
refactor/{설명}              refactor/user-hook-types
chore/{설명}                 chore/upgrade-react-query
hotfix/{설명}                hotfix/critical-auth-bypass
```

---

## 3. 커밋 관련 도구

### Commitlint

```bash
npm install -D @commitlint/cli @commitlint/config-conventional
```

```js
// commitlint.config.js
export default {
  extends: ['@commitlint/config-conventional'],
  rules: {
    'scope-enum': [2, 'always', ['auth', 'payment', 'user', 'ui', 'api']],
    'subject-max-length': [2, 'always', 72],
  },
}
```

### Husky + lint-staged

```bash
npm install -D husky lint-staged
npx husky init
```

```json
// package.json
{
  "lint-staged": {
    "*.{ts,tsx}": ["eslint --fix", "prettier --write"],
    "*.{json,md,css}": ["prettier --write"]
  }
}
```

```sh
# .husky/pre-commit
npx lint-staged

# .husky/commit-msg
npx --no -- commitlint --edit $1
```

---

## 4. PR 작성 템플릿

```markdown
<!-- .github/pull_request_template.md -->
## 변경 사항

<!-- 무엇을 왜 변경했는지 -->

## 관련 이슈

Closes #이슈번호

## 스크린샷 (UI 변경 시)

| Before | After |
|--------|-------|
| 이미지 | 이미지 |

## 체크리스트

- [ ] 테스트 추가/업데이트
- [ ] 스토리북 업데이트 (UI 변경 시)
- [ ] 타입 에러 없음
- [ ] 접근성 확인
```

---

## 5. 유용한 Git 명령어

```bash
# 인터랙티브 rebase — 커밋 정리
git rebase -i HEAD~3

# 특정 커밋만 가져오기
git cherry-pick <commit-hash>

# 변경사항 임시 저장
git stash
git stash pop

# 브랜치 최신 main으로 rebase
git fetch origin
git rebase origin/main

# 잘못된 커밋 되돌리기 (운영 브랜치에서는 revert 사용)
git revert <commit-hash>  # 새 커밋으로 되돌림 (히스토리 보존)
git reset --hard HEAD~1   # 로컬에서만 사용, 운영 금지
```

---

## 6. 코드 리뷰 프로세스

```
1. 개발자 PR 생성
   └── 자동: CI 실행 (lint, test, build)
   └── 자동: Preview 배포

2. 리뷰어 리뷰
   └── Approve: 1명 이상 필요
   └── Request Changes: 수정 후 재요청

3. 머지 (스쿼시 머지 권장)
   └── feature/* → develop (스쿼시)
   └── develop → main (머지 커밋)
```

---

## 7. 안티패턴

- **main에 직접 push**: PR을 통해서만
- **거대한 PR (1000줄+)**: 작게 쪼개기 (기능 단위)
- **의미 없는 커밋 메시지**: `fix`, `update`, `wip` → 구체적으로
- **테스트 없는 PR**: 기능 추가/수정에는 테스트 필수
- **오래된 브랜치 방치**: 머지 후 브랜치 삭제, 주기적 정리
