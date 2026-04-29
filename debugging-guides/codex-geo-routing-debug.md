# 지리적 라우팅 디버깅 - Codex 실행 가이드

> **디버깅 타입**: Infrastructure + Code Logic
> **실행 방식**: 코드 검증 → 테스트 케이스 → 수정안 제시
> **시간 목표**: 30분 내 문제 특정 및 수정

## 🔧 Codex 실행 플로우

### Step 1: 코드 패턴 검증
```bash
# 즉시 실행할 검색 명령어들
grep -r -E "(country|region|KR|DEFAULT).*url" ~/Workspace/ --include="*.js" --include="*.kt" --include="*.ts"
find ~/Workspace -name "*lambda*" -type f -exec grep -l "viewerCountry\|CloudFront" {} \;
grep -r "maxaiapp\.com\|maxai\.co\.kr" ~/Workspace/ --include="*.js" --include="*.kt"
```

### Step 2: 분기 로직 코드 리뷰
의심 코드 패턴들을 찾아서 검증:

```javascript
// 🔍 패턴 1: Lambda@Edge 국가 분기
const response = {
    KR: 'https://kr-server.com',
    DEFAULT: 'https://global-server.com'  // ← 이 URL이 올바른가?
};
const url = viewerCountry === 'KR' ? response.KR : response.DEFAULT;

// 🔍 패턴 2: Android 환경별 분기
object Url {
    const val LIVE = "https://b2c.maxaiapp.com"
    const val QA = "https://qa-b2c.maxaiapp.com"
    fun getUrlByType(apiType: String): String {
        return when (apiType) {
            else -> LIVE  // ← 다른 케이스들이 누락되었나?
        }
    }
}

// 🔍 패턴 3: nginx upstream 분기
upstream backend {
    server kr-backend.com;
}
upstream backend_global {
    server global-backend.com;  // ← 이 서버가 동일한 버전인가?
}
```

### Step 3: 테스트 케이스 생성
```javascript
// 각 분기별 테스트 케이스
const testCases = [
    {
        name: "한국 사용자",
        input: { viewerCountry: "KR" },
        expected: "https://kr-server.com",
        test: () => getUrlByCountry("KR")
    },
    {
        name: "미국 사용자",
        input: { viewerCountry: "US" },
        expected: "https://kr-server.com",  // 같은 서버여야 함
        test: () => getUrlByCountry("US")
    },
    {
        name: "일본 사용자",
        input: { viewerCountry: "JP" },
        expected: "https://kr-server.com",  // 같은 서버여야 함
        test: () => getUrlByCountry("JP")
    },
    {
        name: "undefined 국가",
        input: { viewerCountry: undefined },
        expected: "https://kr-server.com",  // 기본값
        test: () => getUrlByCountry(undefined)
    }
];
```

### Step 4: 버그 수정 코드 제안

#### 수정 전 (잘못된 코드):
```javascript
const B2C_LAUNCH_URLS = {
    KR: 'https://maxai-cdn.weaversbrain.com/MAXAI/b2c/',
    DEFAULT: 'https://b2c.maxaiapp.com/'  // ← 다른 서버!
};
```

#### 수정 후 (올바른 코드):
```javascript
const B2C_LAUNCH_URLS = {
    KR: 'https://maxai-cdn.weaversbrain.com/MAXAI/b2c/',
    DEFAULT: 'https://maxai-cdn.weaversbrain.com/MAXAI/b2c/'  // ← KR과 동일
};
```

### Step 5: 검증 스크립트
```bash
#!/bin/bash
# 지역별 검증 스크립트

echo "=== 지역별 엔드포인트 검증 ==="

# 각 국가 헤더로 테스트
countries=("KR" "US" "JP" "CN" "GB")
for country in "${countries[@]}"; do
    echo "Testing country: $country"
    response=$(curl -s -H "CloudFront-Viewer-Country: $country" https://settings.maxaiapp.com/)
    echo "Response: $response"
    echo "---"
done

# VPN 없이 로컬에서 헤더 시뮬레이션
curl -H "CloudFront-Viewer-Country: US" -H "User-Agent: TestBot" https://b2c.maxaiapp.com/
```

## 🧪 Codex 테스트 시나리오

### 시나리오 1: Lambda@Edge 분기 테스트
```javascript
// 테스트할 함수
function getServerByCountry(viewerCountry) {
    const servers = {
        KR: 'https://kr.example.com',
        DEFAULT: 'https://global.example.com'
    };
    return viewerCountry === 'KR' ? servers.KR : servers.DEFAULT;
}

// 테스트 실행
assert(getServerByCountry('KR') === 'https://kr.example.com');
assert(getServerByCountry('US') === 'https://global.example.com');
assert(getServerByCountry('JP') === 'https://global.example.com');
assert(getServerByCountry(undefined) === 'https://global.example.com');
```

### 시나리오 2: Android 환경 분기 테스트
```kotlin
// 테스트할 함수
fun getUrlByType(apiType: String): String {
    return when (apiType) {
        "DEV" -> "https://dev-b2c.maxaiapp.com"
        "QA" -> "https://qa-b2c.maxaiapp.com"
        else -> "https://b2c.maxaiapp.com"
    }
}

// 테스트 케이스
assert(getUrlByType("DEV") == "https://dev-b2c.maxaiapp.com")
assert(getUrlByType("PROD") == "https://b2c.maxaiapp.com")
assert(getUrlByType("") == "https://b2c.maxaiapp.com")
```

## 🚀 Codex 수정 제안 템플릿

### 1. 문제 식별:
- 파일: `[경로]`
- 라인: `[번호]`
- 문제: `[구체적 버그]`

### 2. 수정 코드:
```diff
- const DEFAULT: 'https://old-server.com'
+ const DEFAULT: 'https://new-server.com'
```

### 3. 테스트 방법:
```bash
curl -H "CloudFront-Viewer-Country: US" [URL]
```

### 4. 검증 기준:
- [ ] 모든 국가에서 동일한 응답
- [ ] 기존 한국 사용자 영향 없음
- [ ] 해외 사용자 정상 동작

---

**Codex 특화**: 코드 중심의 문제 해결. 테스트 케이스로 검증하고 구체적인 수정 코드 제안.
