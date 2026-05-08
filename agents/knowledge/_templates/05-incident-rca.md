# [Incident Report] [한 줄 제목]

## 🚨 문제 상황 (Symptom)

- **발생일**: YYYY-MM-DD HH:MM
- **종료일**: YYYY-MM-DD HH:MM
- **영향**: (사용자 N명 / N% 트래픽 / 서비스 X 다운 등)
- **현상**: (관측된 외부 증상)
- **특징**: (특정 조건에서만 재현 / 랜덤 / 완전 다운 등)

## 🔍 원인 분석 (Root Cause)

### 실제 원인

(여기에 구체적 코드/설정/환경 변수 기술 — 누가 봐도 다시 안 만들도록)

```python
# 문제의 코드/설정 예시
CONFIG = {
    "PROD": "https://new.example.com",
    "DEFAULT": "https://old.example.com",  # ← 여기가 stale
}
```

### 발생 경로

1. 클라이언트가 X 호출
2. 서버는 환경변수로 분기 → DEFAULT 케이스 진입
3. DEFAULT URL이 구버전 → 응답 형식 다름 → 클라 파싱 실패

## 🛠️ 임시 조치 (Mitigation)

(즉시 적용한 hotfix — 원인 못 찾았어도 일단 막은 것)

## ✅ 영구 수정 (Fix)

- PR/커밋: #1234
- 변경 요약: ...
- 검증 방법: ...

## 📚 교훈 (Lessons Learned)

| 영역 | 교훈 |
|------|------|
| 코드 | "환경 분기는 default 안전한 쪽으로" |
| 운영 | "환경별 URL 변경 시 모든 분기 점검 체크리스트 필요" |
| 모니터링 | "응답 인코딩 unmatched 비율 알람 필요" |

## 🔗 관련 자료

- Slack 스레드: ...
- 관련 ADR: ...
- 후속 백로그: ...
