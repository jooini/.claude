# STT "외계어" 이슈 대응 가이드 - Claude 행동 매뉴얼

## 🚨 핵심 신호 인식

### 즉시 알람벨이 울려야 하는 패턴
```
✅ "일부 사용자만 영향"
✅ "앱 재설치/캐시 삭제로도 안됨"
✅ "내부에서 재현 안됨"
✅ "전일 패치 후 발생"
→ 100% 서버사이드 환경 의존적 이슈
```

## 1단계: 즉시 국가/IP 분기 의심 🌍

### 첫 번째 질문들
```
❓ "혹시 해외에 계신 사용자분들인가요?"
❓ "VPN 사용하시는 분들은 없나요?"
❓ "국가별 서버 분기 설정이 있나요?"
```

### 즉시 확인할 위치들
```bash
# 1순위: 국가별 분기 설정
grep -r -i "country\|region\|KR\|DEFAULT" ~/Workspace/ | grep -i "url\|domain"

# 2순위: Lambda@Edge 함수
find ~/Workspace -name "*lambda*" -o -name "*edge*" | grep -i "b2c\|settings"

# 3순위: 도메인 분기
grep -r "maxaiapp\.com\|maxai\.co\.kr" ~/Workspace/
```

## 2단계: 환경별 분기 로직 확인 🔀

### 체크리스트
- [ ] **AWS Lambda@Edge**: `wb-aws-lambda/maxai-b2c-settings/`
- [ ] **CloudFront 분산**: 국가 헤더 기반 라우팅
- [ ] **Android 앱 상수**: `AppConstants.kt` 환경별 URL
- [ ] **nginx 설정**: 국가별 upstream 분기

### 즉시 제안할 디버깅
```bash
# CloudFront 헤더 확인
curl -H "CloudFront-Viewer-Country: US" https://settings.maxaiapp.com/

# 실제 사용자 IP로 테스트
curl -H "X-Forwarded-For: [해외IP]" https://b2c.maxaiapp.com/
```

## 3단계: 지역별 테스트 환경 구성 🧪

### VPN 테스트 제안
```
🔧 "VPN으로 다른 국가 IP 테스트해보세요"
   - 미국/일본/유럽 IP로 접속
   - 각 지역별 STT 동작 확인

🔧 "CloudFront 캐시 무력화 테스트"
   - ?cache_bust=timestamp 파라미터 추가
   - 헤더에 Cache-Control: no-cache 추가
```

### 내부 재현 방법
```bash
# 개발자도구에서 국가 헤더 시뮬레이션
# Network → Response Headers 수정
CloudFront-Viewer-Country: JP
```

## 4단계: 분기 로직 오류 패턴 🐛

### 의심할 버그들
```javascript
// ❌ 잘못된 패턴: DEFAULT가 잘못된 서버 가리킴
const API_BASE_URLS = {
    KR: 'https://backend-b2c.maxai.co.kr',
    DEFAULT: 'https://OLD-API-SERVER.com'  // ← 구버전 서버
};

// ❌ 잘못된 패턴: 조건 로직 오류
const server = viewerCountry === 'KR' ? KR_SERVER : OLD_SERVER;
```

### 확인해야 할 파일들
1. **Lambda@Edge**: 국가별 URL 매핑
2. **Android Constants**: 환경별 엔드포인트
3. **nginx upstream**: 지역별 백엔드 분기
4. **CDN 설정**: 헤더 기반 라우팅 규칙

## 5단계: 즉시 대응 방안 ⚡

### 임시 조치 (5분 내)
```nginx
# 모든 사용자를 한국 서버로 강제 라우팅
# DEFAULT를 KR과 동일하게 설정
```

### 근본 해결 (30분 내)
```javascript
// Lambda@Edge 함수 수정
const B2C_LAUNCH_URLS = {
    KR: 'https://maxai-cdn.weaversbrain.com/MAXAI/b2c/',
    DEFAULT: 'https://maxai-cdn.weaversbrain.com/MAXAI/b2c/'  // ← KR과 동일
};
```

## 6단계: 검증 및 모니터링 📊

### 배포 후 확인
- [ ] VPN으로 각국 IP 테스트
- [ ] 실제 해외 사용자 피드백 수집
- [ ] CloudWatch 로그에서 분기 로직 동작 확인

## ⚠️ Claude가 절대 하지 말아야 할 것

```
❌ 바로 코드 분석부터 시작
❌ "앱 캐시 문제"라고 단정
❌ 인코딩 체인만 분석
❌ 로컬 환경에서만 테스트 시도
```

## ✅ Claude가 즉시 해야 할 것

```
✅ "국가별 분기 설정부터 확인하세요"
✅ "VPN으로 해외 IP 테스트 필요합니다"
✅ "Lambda@Edge 함수 확인하세요"
✅ "CloudFront 헤더 기반 라우팅 의심됩니다"
```

---

**핵심**: "일부 사용자만 + 재설치 안됨 + 내부 재현 불가" = 99% 지역/IP 의존적 서버사이드 이슈

## 실제 사례 참고

**2026-04-14 STT 외계어 이슈**:
- 증상: AOS/iOS STT 결과가 외계어로 표시
- 잘못된 접근: 인코딩 체인 분석, nginx 캐싱 의심
- 실제 원인: Lambda@Edge에서 해외 IP 사용자를 구버전 서버로 라우팅
- 해결: `DEFAULT` URL을 한국 서버와 동일하게 수정

슬랙 스레드: "허상호 → 박범열" 대화에서 "국가 아이피에 따라서 서버를 분기처리해주는 기능" 언급으로 최종 해결
