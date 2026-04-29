# 지리적 라우팅 디버깅 - Claude 전용 가이드

> **패턴 ID**: `GEO_ROUTING_DEBUG`
> **트리거**: "일부 사용자만 영향" + "재현 안됨" + "재설치 효과없음"
> **우선순위**: 🚨 HIGH (13시간 삽질 방지)

## 🤖 Claude 행동 매뉴얼

### 1단계: 패턴 인식 (즉시)
```
사용자가 이런 표현을 쓰면 → 즉시 이 가이드 적용:
✅ "일부 사용자만"
✅ "부분적으로만 문제"
✅ "재현이 안됨"
✅ "내부에서는 정상"
✅ "랜덤하게 발생"
✅ "재설치해도 안됨"
```

### 2단계: 즉시 질문 (코드 보기 전에)
```
❓ "혹시 해외에 계신 사용자분들인가요?"
❓ "VPN 사용하시는 분들은 없나요?"
❓ "국가별 서버 분기 설정이 있나요?"
❓ "CDN이나 CloudFront 사용 중인가요?"
🚨 "엑세스 로그가 확인 가능한가요?" # 없으면 즉시 CDN/서버리스 의심
```

### 3단계: 즉시 검색 실행
```bash
# 1순위 - 국가 분기 찾기
grep -r -i "country\\|region\\|KR\\|DEFAULT" ~/Workspace/ | grep -i "url\\|domain"

# 2순위 - Lambda@Edge 함수
find ~/Workspace -name "*lambda*" -o -name "*edge*" | grep -i "b2c\\|settings"

# 3순위 - 도메인 분기
grep -r "maxaiapp\\.com\\|maxai\\.co\\.kr" ~/Workspace/
```

### 4단계: VPN 테스트 즉시 제안
```
🔧 "VPN으로 미국/일본 IP 테스트해보세요"
🔧 "개발자도구에서 CloudFront-Viewer-Country: US 헤더 추가해보세요"
🔧 "curl -H 'CloudFront-Viewer-Country: JP' [URL] 로 테스트해보세요"
```

### 5단계: 체크할 파일들
- [ ] `wb-aws-lambda/maxai-b2c-settings/index-*.js`
- [ ] `maxai-android/**/AppConstants.kt`
- [ ] `nginx.conf`, `server.conf`
- [ ] `.env` 파일들의 환경별 URL

### 6단계: 일반적 버그 패턴 확인
```javascript
// ❌ 이런 패턴 발견하면 즉시 의심
const API_URLS = {
    KR: 'https://new-server.com',
    DEFAULT: 'https://old-server.com'  // ← 구버전 서버!
};

// ❌ 조건 로직 오류
const url = country === 'KR' ? NEW_SERVER : OLD_SERVER;
```

## 🚫 절대 하지 말 것

```
❌ 바로 코드 분석부터 시작
❌ "캐시 문제일 것"이라고 단정
❌ 로컬 환경에서만 테스트
❌ 인코딩/디코딩 체인 먼저 분석
```

## ✅ 반드시 할 것

```
✅ 지역/IP 분기부터 의심
✅ VPN 테스트 먼저 제안
✅ 해외 사용자 여부 먼저 확인
✅ Lambda@Edge, CDN 설정 우선 체크
```

## 🔗 연계 스킬

이 패턴 감지 시 사용할 스킬들:
- `systematic-debugging` - 체계적 디버깅 플로우
- `mem-search` - 과거 유사 사례 검색
- `ask-gemini` - 코드베이스 전체 스캔 위임
- `ask-codex` - 분기 로직 코드 리뷰 위임

## 📋 타임라인 (총 1시간 목표)

- **0-15분**: 패턴 인식 → 즉시 질문 → VPN 테스트
- **15-30분**: 분기 설정 파일 찾기 → 로직 분석
- **30-45분**: 버그 특정 → 임시 수정
- **45-60분**: 검증 → 영구 수정 → 모니터링 설정

## 🎯 성공 기준

- [ ] 모든 지역에서 동일한 동작
- [ ] VPN 테스트로 각국 IP 검증 완료
- [ ] 실제 해외 사용자 피드백 정상

---

**Remember**: 2026-04-14에 13시간 삽질한 사례. "일부 사용자만" = 지역 분기부터 의심!
