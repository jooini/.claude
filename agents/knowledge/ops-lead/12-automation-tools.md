# Automation Tools

> 원본: https://ironact.gitbook.io/ironact-docs/CrEhRPJQJpia3xh9iqbi/knowledge-ops-lead/automation-tools

---

## 1. 자동화 우선순위 결정

```
자동화 가치 = (절약 시간 × 빈도) - (구축 시간 + 유지 시간)

자동화 적합 조건:
  ✅ 반복적 (주 3회 이상)
  ✅ 규칙 기반 (판단 불필요)
  ✅ 오류 발생하면 비용이 큰 작업
  ✅ 수동으로 지루하고 시간이 오래 걸리는 것

자동화 부적합:
  ❌ 한 번만 하는 작업
  ❌ 창의적 판단 필요
  ❌ 결과 품질 검토가 항상 필요한 것
```

---

## 2. Zapier / Make (Integromat) 활용

```
자동화 시나리오 예시:

1. 클라이언트 리포트 자동 발송
   트리거: 매월 5일 오전 9시
   액션: Google Sheets 데이터 → PDF 생성 → 이메일 발송

2. 신규 리드 알림
   트리거: 폼 제출 (Typeform)
   액션: 슬랙 채널 알림 + Notion DB 추가 + 담당자 이메일

3. 콘텐츠 발행 알림
   트리거: WordPress 신규 포스트 발행
   액션: 슬랙 알림 + SNS 공유 예약

4. 클라이언트 피드백 수집
   트리거: 작업물 납품 (이메일 발송)
   3일 후 → 피드백 폼 자동 발송
```

---

## 3. Google Sheets 자동화

```javascript
// Apps Script — 월간 리포트 자동 생성
function generateMonthlyReport() {
  const sheet = SpreadsheetApp.getActiveSheet()
  const data = sheet.getDataRange().getValues()

  // 데이터 집계
  const summary = {
    totalPosts: data.filter(row => row[2] === '블로그').length,
    totalSNS: data.filter(row => row[2] === 'SNS').length,
    onTime: data.filter(row => row[5] === '완료' && row[4] <= row[3]).length,
  }

  // 리포트 시트에 작성
  const reportSheet = SpreadsheetApp.getActiveSpreadsheet()
    .getSheetByName('Monthly Report')
  reportSheet.getRange('B2').setValue(summary.totalPosts)
  reportSheet.getRange('B3').setValue(summary.totalSNS)

  // 이메일 발송
  MailApp.sendEmail({
    to: 'client@example.com',
    subject: `[${new Date().toLocaleDateString('ko-KR', {month: 'long'})}] 월간 성과 리포트`,
    htmlBody: generateEmailBody(summary),
    attachments: [SpreadsheetApp.getActiveSpreadsheet().getAs('application/pdf')],
  })
}

// 매월 5일 실행 트리거 설정
function setTrigger() {
  ScriptApp.newTrigger('generateMonthlyReport')
    .timeBased()
    .onMonthDay(5)
    .atHour(9)
    .create()
}
```

---

## 4. 슬랙 자동화

```
/remind 커맨드:
  /remind @홍길동 "A사 월간 리포트 발송" every month on the 5th

슬랙 워크플로:
  트리거: 특정 채널에 메시지 → 자동 체크리스트 생성
  트리거: 신규 팀원 채널 참여 → 온보딩 안내 DM 발송

Slack API + 스크립트:
  납품 완료 시 자동으로 클라이언트 채널에 알림
  정기 스탠드업 요청 메시지 발송
```

---

## 5. AI 자동화 도구

```
Claude API / ChatGPT API 활용:
  - 초안 작성 지원 (브리프 → 초안)
  - 콘텐츠 리라이팅 (톤 조정, 교정)
  - 키워드 리서치 보조
  - 리포트 텍스트 자동 생성

주의사항:
  - AI 출력물은 반드시 사람이 검토
  - 클라이언트에게 AI 활용 여부 투명하게 공개
  - 민감한 클라이언트 정보 AI에 입력 금지
```

---

## 6. 안티패턴

- **자동화를 위한 자동화**: 실제 시간 절약 측정 없이 도구 도입
- **복잡한 자동화 구축 후 방치**: 유지보수 없이 오류 발생
- **자동화 = 품질 무시**: 자동 발송 이메일에 오류 → 브랜드 손상
- **팀 공유 없는 자동화**: 혼자만 아는 자동화 → 퇴사 후 마비
- **모든 것을 자동화**: 판단이 필요한 것까지 자동화 시도
