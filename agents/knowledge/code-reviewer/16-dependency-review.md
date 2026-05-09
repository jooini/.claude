# 의존성 리뷰

> 참조 링크: https://docs.npmjs.com/cli/v10/configuring-npm/package-json, https://snyk.io/advisor/

---

## 개요

외부 의존성(라이브러리)은 개발 속도를 높이지만, 보안 취약점, 라이선스 리스크, 유지보수 부담, 번들 크기 증가를 동반한다. 리뷰어는 새 의존성 추가 시 이런 측면을 함께 검토해야 한다.

## 1. 라이브러리 선택 기준

### 평가 항목

```typescript
// 라이브러리 선택 시 검토할 기준
interface LibraryEvaluation {
  name: string;
  weeklyDownloads: number;     // npm 주간 다운로드 (최소 10만+ 권장)
  lastPublished: Date;         // 최근 배포일 (6개월 이내 권장)
  openIssues: number;          // 미해결 이슈 수
  maintainers: number;         // 메인테이너 수 (1명 = bus factor 위험)
  typeSupport: 'built-in' | '@types' | 'none'; // TypeScript 지원
  license: string;             // 라이선스 종류
  bundleSize: string;          // gzip 크기
  alternatives: string[];      // 대안 라이브러리
}
```

### 좋은 선택 vs 위험한 선택

```
✅ 좋은 의존성 신호
- 주간 다운로드 100만+ (생태계 검증)
- TypeScript built-in 지원
- 최근 6개월 내 릴리즈
- 메인테이너 3명 이상
- MIT / Apache-2.0 라이선스
- 명확한 CHANGELOG

❌ 위험한 의존성 신호
- 주간 다운로드 1000 미만 (검증 부족)
- 마지막 업데이트 2년 전
- 메인테이너 1명 (bus factor)
- 미해결 이슈 100개+ (방치)
- README에 "WIP" / "experimental"
- 타입 정의 없음
```

### 불필요한 의존성

```typescript
// ❌ 직접 구현 가능한 것에 라이브러리 추가
import leftPad from 'left-pad';       // String.padStart() 사용
import isEven from 'is-even';         // n % 2 === 0
import isArray from 'is-array';       // Array.isArray()
import { sleep } from 'sleep-promise'; // new Promise(r => setTimeout(r, ms))

// ✅ 네이티브 API 또는 간단한 유틸 함수
const padded = '5'.padStart(3, '0');   // '005'
const isEven = (n: number) => n % 2 === 0;
const sleep = (ms: number) => new Promise(resolve => setTimeout(resolve, ms));
```

### 선택 기준 체크리스트

- [ ] 같은 기능을 네이티브 API로 구현할 수 있는가?
- [ ] 기존 프로젝트에 이미 비슷한 기능을 하는 라이브러리가 있는가?
- [ ] npm trends에서 다운로드 추이와 대안을 비교했는가?
- [ ] TypeScript 타입이 지원되는가?
- [ ] 최근 6개월 이내에 업데이트된 활성 프로젝트인가?

## 2. 라이선스

### 라이선스 분류

```
✅ 허용적 (Permissive) — 상업적 사용 자유
- MIT: 가장 자유로움. 저작권 표기만 유지
- Apache-2.0: MIT + 특허 보호
- BSD-2-Clause, BSD-3-Clause: MIT 유사
- ISC: MIT 유사

⚠️ 약한 카피레프트 — 수정 시 공개 의무
- LGPL-2.1, LGPL-3.0: 라이브러리 수정 시 수정분 공개
- MPL-2.0: 수정한 파일만 공개

❌ 강한 카피레프트 — 전체 소스 공개 의무 (주의!)
- GPL-2.0, GPL-3.0: 이 코드를 사용한 프로그램 전체 공개 의무
- AGPL-3.0: GPL + 네트워크 사용도 해당 (SaaS 서비스도 공개 의무!)

🚫 사용 불가
- SSPL: MongoDB 등. 서비스 전체 스택 공개 의무
- 라이선스 없음 (UNLICENSED): 저작권법에 의해 사용 불가
```

### 라이선스 체크리스트

- [ ] 추가된 라이브러리의 라이선스를 확인했는가?
- [ ] GPL/AGPL 라이선스가 아닌가? (상업 프로젝트에서 위험)
- [ ] 라이선스 없는(UNLICENSED) 패키지가 아닌가?
- [ ] 간접 의존성(transitive dependency)의 라이선스도 확인했는가?

## 3. 보안 취약점

### 취약점 확인 방법

```bash
# npm 내장 감사
npm audit

# 심각도별 필터
npm audit --audit-level=high

# Snyk 사용 (더 포괄적)
npx snyk test

# GitHub Dependabot 알림 확인
# Settings → Security → Dependabot alerts
```

### 취약점 대응

```typescript
// package.json — 취약한 간접 의존성 강제 버전 업
{
  "overrides": {
    "vulnerable-package": ">=2.0.1" // 취약점 패치 버전으로 강제
  }
}

// .npmrc — 감사 레벨 설정
audit-level=high
```

### 버전 관리

```json
// ❌ 버전 범위가 너무 넓음
{
  "dependencies": {
    "express": "*",           // 모든 버전 허용
    "lodash": ">=4.0.0",     // 메이저 업그레이드까지 허용
    "axios": "^1.0.0"        // 마이너까지 허용 (일반적으로 OK)
  }
}

// ✅ 적절한 버전 고정
{
  "dependencies": {
    "express": "^4.18.2",    // 마이너/패치 자동 업데이트
    "lodash": "~4.17.21",   // 패치만 자동 업데이트 (안전)
    "typeorm": "0.3.20"     // 정확한 버전 고정 (ORM 등 크리티컬 의존성)
  }
}
```

### 보안 체크리스트

- [ ] `npm audit`에서 high/critical 취약점이 없는가?
- [ ] 새 의존성에 알려진 CVE가 없는가?
- [ ] `package-lock.json`이 커밋에 포함되어 있는가?
- [ ] `overrides`로 취약한 간접 의존성을 패치했는가?

## 4. 번들 크기

### 번들 영향 확인

```bash
# 패키지 크기 확인 (설치 전)
npx bundlephobia <package-name>

# 또는 웹사이트
# https://bundlephobia.com/package/<package-name>
```

### 번들 최적화

```typescript
// ❌ 전체 임포트 — 사용하지 않는 코드도 번들에 포함
import _ from 'lodash'; // 전체 lodash (~70KB gzip)
const result = _.pick(obj, ['a', 'b']);

// ✅ 필요한 함수만 임포트
import pick from 'lodash/pick'; // pick만 (~1KB)
const result = pick(obj, ['a', 'b']);

// ❌ moment.js (~70KB gzip, 로케일 포함)
import moment from 'moment';

// ✅ date-fns (~7KB tree-shakable) 또는 dayjs (~2KB)
import { format, parseISO } from 'date-fns';
import dayjs from 'dayjs';

// ❌ 서버 사이드에서만 쓰는 패키지가 클라이언트 번들에 포함
// next.config.js에서 externals 처리 필요
```

### 크기 기준 가이드

| 분류 | gzip 크기 | 판단 |
|------|----------|------|
| 마이크로 | < 5KB | 허용 |
| 소형 | 5 - 20KB | 대안 검토 |
| 중형 | 20 - 50KB | 정당한 사유 필요 |
| 대형 | 50KB+ | 강력한 사유 + tree-shaking 확인 |

### 번들 크기 체크리스트

- [ ] 새 의존성의 gzip 크기를 확인했는가?
- [ ] tree-shaking이 가능한 ESM 패키지인가?
- [ ] 더 가벼운 대안이 있는가? (moment → dayjs, lodash → lodash-es)
- [ ] 서버 전용 패키지가 클라이언트 번들에 포함되지 않는가?
- [ ] named import로 필요한 함수만 가져오는가?

## 5. 의존성 업데이트 관리

### 업데이트 전략

```
정기 업데이트 (주 1회 또는 월 1회):
1. npm outdated로 업데이트 가능 목록 확인
2. 패치/마이너 업데이트 일괄 적용
3. 테스트 스위트 실행
4. CHANGELOG 확인 후 머지

메이저 업데이트:
1. CHANGELOG에서 breaking changes 확인
2. 별도 브랜치에서 업그레이드
3. 마이그레이션 가이드 따라 코드 수정
4. 전체 테스트 + 수동 검증
```

### 의존성 업데이트 체크리스트

- [ ] Dependabot / Renovate가 설정되어 있는가?
- [ ] 메이저 업데이트 시 breaking changes를 확인했는가?
- [ ] 업데이트 후 테스트가 통과하는가?
- [ ] 더 이상 사용하지 않는 의존성(`unused dependencies`)이 있는가?

## 리뷰어 종합 체크리스트

| 항목 | 확인 내용 | 심각도 |
|------|----------|--------|
| 보안 취약점 | npm audit high/critical | P0 |
| GPL 라이선스 | 상업 프로젝트에 GPL 의존성 | P0 |
| 라이선스 없음 | UNLICENSED 패키지 사용 | P0 |
| 방치된 패키지 | 2년+ 업데이트 없음 | P1 |
| 번들 과대 | 50KB+ 의존성 (대안 미검토) | P1 |
| 불필요한 의존성 | 네이티브 API로 대체 가능 | P2 |
| 버전 미고정 | * 또는 >= 범위 사용 | P2 |
| lock 파일 누락 | package-lock.json 미커밋 | P1 |
