# 지리적 라우팅 디버깅 명령어 레퍼런스

> **용도**: "일부 사용자만 영향" 패턴 발생 시 즉시 실행할 명령어들
> **기반**: 2026-04-14 STT 외계어 이슈 13시간 삽질 사례

## 🚨 즉시 실행 - 골든 커맨드

### 패턴 감지 후 바로 실행 (5분 내)
```bash
# 1단계: Lambda@Edge 파일 찾기 (가장 중요!)
find ~/Workspace -name "*lambda*" -type f
find ~/Workspace -name "*edge*" -type f
find ~/Workspace -path "*lambda*" -name "*.js"

# 2단계: 국가별 분기 설정 찾기
grep -r -i "country\|region\|KR\|DEFAULT" ~/Workspace/ | grep -i "url\|domain"
grep -r "viewerCountry\|geo" ~/Workspace/

# 3단계: 도메인 분기 즉시 확인
grep -r "maxaiapp\.com\|maxai\.co\.kr" ~/Workspace/
grep -r "b2c\.maxaiapp\|maxai-cdn" ~/Workspace/
```

### 국가별 실제 테스트 (핵심!)
```bash
# CloudFront 헤더 시뮬레이션
curl -H "CloudFront-Viewer-Country: KR" https://settings.maxaiapp.com/
curl -H "CloudFront-Viewer-Country: US" https://settings.maxaiapp.com/
curl -H "CloudFront-Viewer-Country: JP" https://settings.maxaiapp.com/

# 응답 차이 확인
diff <(curl -s -H "CloudFront-Viewer-Country: KR" https://settings.maxaiapp.com/) \
     <(curl -s -H "CloudFront-Viewer-Country: US" https://settings.maxaiapp.com/)
```

## 🔍 문제 특정 명령어들

### Lambda@Edge 추적
```bash
# Lambda 함수 파일 위치
find ~/Workspace -name "*lambda*" -type d
ls -la ~/Workspace/wb-aws-lambda/

# Lambda@Edge 코드 확인
find ~/Workspace -path "*lambda*" -name "*.js" -exec grep -l "viewerCountry\|CloudFront" {} \;

# 환경별 Lambda 함수 비교
ls ~/Workspace/wb-aws-lambda/maxai-b2c-settings/index-*.js
```

### CloudFront/CDN 관련
```bash
# CloudFront 관련 설정 찾기
grep -r "CloudFront\|cloudfront" ~/Workspace/
grep -r "viewerCountry\|viewer-country" ~/Workspace/
grep -r "Lambda.*Edge\|lambda.*edge" ~/Workspace/

# CDN 분기 로직 찾기
grep -r -A10 -B5 "viewerCountry.*KR" ~/Workspace/
```

### 국가/지역 분기 설정
```bash
# 국가별 URL 매핑
grep -r -i "country.*url\|region.*url" ~/Workspace/
grep -r "KR.*DEFAULT\|DEFAULT.*KR" ~/Workspace/

# 환경별 분기 패턴
grep -r "PROD.*DEV\|QA.*LIVE" ~/Workspace/ | grep -i url
```

## 🌍 지역별 테스트 명령어

### VPN 없이 국가 시뮬레이션
```bash
# 주요 국가별 CloudFront 헤더 테스트
countries=("KR" "US" "JP" "CN" "GB" "DE")
for country in "${countries[@]}"; do
    echo "=== Testing Country: $country ==="
    curl -s -H "CloudFront-Viewer-Country: $country" https://settings.maxaiapp.com/
    echo -e "\n"
done
```

### IP 기반 테스트
```bash
# 해외 IP 시뮬레이션
curl -H "X-Forwarded-For: 8.8.8.8" https://b2c.maxaiapp.com/        # 미국
curl -H "X-Forwarded-For: 1.1.1.1" https://b2c.maxaiapp.com/        # CloudFlare
curl -H "X-Forwarded-For: 208.67.222.222" https://b2c.maxaiapp.com/  # OpenDNS

# 한국 vs 해외 응답 비교
echo "=== 한국 IP 응답 ==="
curl -s -H "X-Forwarded-For: 203.248.252.2" https://settings.maxaiapp.com/  # 네이버

echo -e "\n=== 해외 IP 응답 ==="
curl -s -H "X-Forwarded-For: 8.8.8.8" https://settings.maxaiapp.com/      # 구글
```

### 도메인별 응답 비교
```bash
# 두 도메인 응답 시간 비교
echo "=== b2c.maxaiapp.com ==="
time curl -s https://b2c.maxaiapp.com/ > /dev/null

echo "=== maxai-cdn.weaversbrain.com ==="
time curl -s https://maxai-cdn.weaversbrain.com/MAXAI/b2c/ > /dev/null

# DNS 확인
echo "=== DNS 정보 ==="
nslookup b2c.maxaiapp.com
nslookup maxai-cdn.weaversbrain.com
```

## 📱 모바일/앱 관련 명령어

### Android 앱 상수 확인
```bash
# Android 환경별 URL 설정
find ~/Workspace -name "AppConstants*" -exec grep -A10 -B5 "Url\|URL" {} \;
find ~/Workspace -path "*android*" -name "*.kt" -exec grep -l "maxaiapp\|maxai-cdn" {} \;

# WebView 브릿지 설정
grep -r "receiveBridgeMessage\|BridgeManager" ~/Workspace/ --include="*.kt"
```

### STT/인코딩 관련 (원래 추적했던 것들)
```bash
# STT 관련 파일
find ~/Workspace -name "*stt*" -o -name "*whisper*" -type f
grep -r "decodeSttResult\|sttResult" ~/Workspace/

# base64 인코딩 관련
grep -r "base64\|atob\|btoa" ~/Workspace/ --include="*.js" --include="*.ts"
grep -r "URLEncoder\|encodeURIComponent" ~/Workspace/
```

## 🐛 실시간 디버깅

### 로그 모니터링
```bash
# Docker 컨테이너 로그
docker logs stt-container-name --tail 100 -f
docker logs identity-hub --tail 100 | grep -i "stt\|encoding"

# nginx 로그 (만약 있다면)
tail -f /var/log/nginx/access.log | grep "stt\|b2c"
tail -f /var/log/nginx/error.log

# 특정 시간대 로그 확인
journalctl --since "2026-04-14 09:00" --until "2026-04-14 22:00" | grep -i "stt\|error"
```

### 네트워크 모니터링
```bash
# HTTP 트래픽 실시간 모니터링
sudo tcpdump -i any -A -s 1500 'port 80 or port 443' | grep -i "maxai"

# 라우팅 경로 확인
traceroute b2c.maxaiapp.com
traceroute maxai-cdn.weaversbrain.com

# 연결 테스트
telnet b2c.maxaiapp.com 80
telnet maxai-cdn.weaversbrain.com 80
```

## 🔧 AWS CLI 명령어 (만약 권한이 있다면)

### CloudFront 확인
```bash
# CloudFront 배포 목록
aws cloudfront list-distributions | jq '.DistributionList.Items[] | {Id, DomainName}'

# Lambda@Edge 함수 목록
aws lambda list-functions --region us-east-1 | jq '.Functions[] | select(.FunctionName | contains("edge"))'
```

### CloudWatch 로그
```bash
# Lambda@Edge 로그 그룹
aws logs describe-log-groups | grep -i "lambda\|edge"

# 최근 로그 확인
aws logs filter-log-events --log-group-name "/aws/lambda/us-east-1.maxai-b2c-settings" --start-time $(date -d '1 hour ago' +%s)000
```

## 🚀 원샷 디버깅 스크립트

### geo-debug.sh (즉시 실행용)
```bash
#!/bin/bash
# 지리적 분기 문제 즉시 진단 스크립트

echo "🔍 지리적 분기 문제 진단 시작..."
echo "=================================="

echo -e "\n1️⃣ Lambda@Edge 파일 찾기"
echo "----------------------------"
find ~/Workspace -name "*lambda*" -o -name "*edge*" | grep -v node_modules | head -10

echo -e "\n2️⃣ 국가별 분기 설정 찾기"
echo "----------------------------"
grep -r -i "country.*url\|KR.*DEFAULT" ~/Workspace/ --include="*.js" --include="*.kt" | head -5

echo -e "\n3️⃣ 국가별 실제 응답 테스트"
echo "----------------------------"
for country in KR US JP; do
    echo "Testing $country:"
    response=$(curl -s -H "CloudFront-Viewer-Country: $country" https://settings.maxaiapp.com/ 2>/dev/null)
    if [ $? -eq 0 ]; then
        echo "$response" | head -c 100
    else
        echo "Request failed"
    fi
    echo -e "\n---"
done

echo -e "\n4️⃣ 도메인 분기 확인"
echo "----------------------------"
grep -r "b2c\.maxaiapp\|maxai-cdn" ~/Workspace/ | head -3

echo -e "\n✅ 진단 완료"
```

### country-test.sh (국가별 테스트)
```bash
#!/bin/bash
# 국가별 분기 테스트 스크립트

countries=("KR" "US" "JP" "CN" "GB" "DE")
endpoint="https://settings.maxaiapp.com/"

echo "🌍 국가별 분기 테스트"
echo "===================="

for country in "${countries[@]}"; do
    echo "Country: $country"

    response=$(curl -s -H "CloudFront-Viewer-Country: $country" "$endpoint")

    if echo "$response" | jq . >/dev/null 2>&1; then
        echo "$response" | jq -r '.b2cLaunchUrl'
    else
        echo "Invalid JSON response or request failed"
    fi

    echo "---"
done
```

## ⚡ 빠른 체크리스트

### "일부 사용자만" 들으면 즉시:
```bash
# 1. Lambda@Edge 확인 (30초)
find ~/Workspace -name "*lambda*" | head -5

# 2. 국가 분기 확인 (30초)
grep -r "country.*KR.*DEFAULT" ~/Workspace/ | head -3

# 3. VPN 테스트 제안 (즉시)
echo "VPN으로 미국/일본 IP 테스트해보세요!"

# 4. CloudFront 헤더 테스트 (1분)
curl -H "CloudFront-Viewer-Country: US" https://settings.maxaiapp.com/
```

---

## 📋 사용 가이드

### 🚨 긴급상황 (5분 안에)
1. **골든 커맨드** 섹션 명령어 순서대로 실행
2. `geo-debug.sh` 스크립트 실행
3. VPN 테스트 즉시 제안

### 🔍 상세 분석 (30분)
1. **문제 특정 명령어** 섹션 활용
2. **지역별 테스트** 철저히 실행
3. **실시간 디버깅** 도구로 모니터링

### 📊 후속 검증
1. 수정 후 **원샷 디버깅 스크립트** 재실행
2. **국가별 테스트 스크립트**로 전체 검증
3. **모니터링** 명령어로 지속 확인

---

**중요**: 이 명령어들은 2026-04-14 실제 13시간 삽질 사례를 바탕으로 작성됨. "일부 사용자만" 패턴 감지 시 즉시 활용하여 1시간 내 해결 목표.
