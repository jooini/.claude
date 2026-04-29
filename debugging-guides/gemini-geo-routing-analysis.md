# 지리적 라우팅 디버깅 - Gemini 분석 가이드

> **분석 대상**: 지역별 사용자 이슈 - 일부만 영향, 재현 불가 패턴
> **분석 목적**: 대규모 코드베이스에서 지리적 분기 로직 찾기 및 검증
> **우선순위**: Infrastructure > Code Logic > Cache

## 📊 Gemini 분석 접근법

### Phase 1: 코드베이스 전체 스캔
```
목적: 지리적/환경별 분기 설정 모든 위치 파악
범위: ~/Workspace/ 전체 (1M+ 토큰 처리 가능)
패턴: country, region, geo, KR, DEFAULT, viewerCountry, CloudFront
```

#### 검색해야 할 키워드 패턴:
```
1차: "country", "region", "KR", "DEFAULT", "viewerCountry"
2차: "maxaiapp.com", "maxai.co.kr", ".com", ".co.kr"
3차: "Lambda", "Edge", "CloudFront", "CDN"
4차: "upstream", "geo $", "map $remote_addr"
```

### Phase 2: 설정 파일 우선 분석
분석 순서:
1. **AWS Lambda@Edge**: `wb-aws-lambda/maxai-b2c-settings/`
2. **Android 상수**: `maxai-android/**/AppConstants.kt`
3. **Nginx 설정**: `*.conf`, nginx 관련 파일
4. **환경 변수**: `.env`, `config/`
5. **프론트엔드 설정**: `next.config.js`, 환경별 설정

### Phase 3: 분기 로직 검증 분석
각 분기에서 확인할 항목:
```javascript
// 패턴 1: 조건부 URL 매핑
const URLS = {
    KR: 'server1.com',
    DEFAULT: 'server2.com'  // ← 이 서버가 올바른가?
};

// 패턴 2: 조건문 로직
const server = condition ? A : B;  // ← 조건과 결과가 맞는가?

// 패턴 3: 스위치문
switch(country) {
    case 'KR': return url1;
    default: return url2;  // ← default 케이스가 올바른가?
}
```

### Phase 4: 환경별 일관성 검증
| 환경 | 한국 사용자 | 해외 사용자 | 일관성 체크 |
|------|-------------|-------------|-------------|
| PROD | server-kr.com | server-global.com | ✓ 버전 동일? |
| DEV  | dev-kr.com | dev-global.com | ✓ 버전 동일? |
| QA   | qa-kr.com | qa-global.com | ✓ 버전 동일? |

### Phase 5: 의존성 체인 분석
```
CloudFront → Lambda@Edge → 분기 로직 → 백엔드 서버
    ↓            ↓            ↓          ↓
국가 헤더    분기 함수     URL 선택    서버 응답

각 단계별 데이터 흐름과 변환 과정 분석
```

## 🔍 Gemini가 특별히 확인해야 할 사항

1. **패턴 매칭**: 유사한 분기 로직이 여러 곳에 중복되어 있는가?
2. **버전 불일치**: 같은 기능이 다른 버전으로 구현되어 있는가?
3. **설정 충돌**: 여러 레이어에서 서로 다른 분기 규칙을 사용하는가?
4. **누락된 케이스**: 예상하지 못한 국가/지역 코드가 있는가?

## 📈 분석 결과 리포트 형식

### 발견된 분기 로직 요약:
- 위치: [파일 경로]
- 패턴: [분기 방식]
- 문제: [의심 지점]
- 영향도: [HIGH/MEDIUM/LOW]

### 권장 조치:
1. 즉시 수정: [긴급 패치]
2. 임시 조치: [우회 방안]
3. 장기 개선: [구조 개선]

### 검증 방법:
- VPN 테스트 시나리오
- 각 분기별 예상 동작
- 모니터링 포인트

## 🚨 Gemini 알림: 이런 패턴 발견 시 즉시 보고

```javascript
❌ DEFAULT가 구버전 서버를 가리킴
❌ 조건문에서 !==와 ===를 잘못 사용
❌ 환경 변수가 설정되지 않아 undefined 반환
❌ 국가 코드 대소문자 불일치 (kr vs KR)
❌ 분기 로직이 여러 곳에 분산되어 일관성 없음
```

---

**Gemini 역할**: 코드베이스 전체 스캔으로 분기 로직을 찾고, 패턴 분석으로 문제를 특정하여 Claude에게 정확한 분석 결과 제공
