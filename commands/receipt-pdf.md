# /receipt-pdf - 영수증 이미지를 A4 PDF로 정리

지정된 디렉토리의 영수증 이미지를 종류별/날짜별로 분류하여 A4 인쇄용 PDF로 합친다.

## 사용법

- `/organize-receipts /path/to/directory` - 해당 경로의 영수증 정리
- `/organize-receipts` - 경로를 물어본 후 진행

## 인자

$ARGUMENTS

## 수행 작업

### 1단계: 디렉토리 확인

- `$ARGUMENTS`가 있으면 해당 경로 사용, 없으면 사용자에게 경로 물어보기
- 디렉토리 내 이미지 파일 목록 확인 (jpeg, jpg, png)

### 2단계: 영수증 분석

디렉토리의 모든 이미지를 Read 도구로 읽어서 다음을 파악한다:

- **종류**: 택시, 식비, 교통비, 숙박비, 기타 등
- **날짜**: 영수증에 표기된 결제/승인 날짜
- **금액**: 결제 금액
- **쌍 여부**: 같은 거래의 거래확인증+이용상세 등 쌍이 있는지 파악

분석 결과를 사용자에게 보여주고 확인받기:

```
분석 결과:
- 택시 16건 (1월 7건, 2월 9건) — 거래확인증+이용상세 쌍
- 식비 3건 (2월 3건) — 단일 영수증

이대로 진행할까요?
```

### 3단계: JSON 설정 생성

분석 결과를 바탕으로 `~/.claude/scripts/combine_receipts.py`용 JSON 설정 파일을 `/tmp/receipt_config.json`에 생성한다.

**쌍이 있는 경우 (pairs):**
```json
{
  "src_dir": "/path/to/images",
  "out_dir": "/path/to/images/결과",
  "groups": {
    "택시_2026년1월": {
      "title": "택시 영수증 — 2026년 1월",
      "per_page": 4,
      "pairs": [
        { "left": "거래확인증.jpeg", "right": "이용상세.jpeg", "date": "01.14", "amount": "19,900원" }
      ]
    }
  }
}
```

**단일 영수증인 경우 (singles):**
```json
{
  "groups": {
    "식비_2026년1월": {
      "title": "식비 — 2026년 1월",
      "per_page": 6,
      "singles": [
        { "file": "receipt.jpeg", "date": "01.05", "amount": "12,000원" }
      ]
    }
  }
}
```

그룹핑 규칙:
- 종류별로 먼저 나누고, 그 안에서 월별로 나눈다
- 날짜순 정렬
- pairs: A4 한 장에 4건 (2x2)
- singles: A4 한 장에 6건 (3x2)

### 4단계: Python 스크립트 실행

Pillow가 필요하다. 없으면 venv로 설치:
```bash
python3 -m venv /tmp/receipt-venv && /tmp/receipt-venv/bin/pip install Pillow
```

스크립트 실행:
```bash
/tmp/receipt-venv/bin/python3 ~/.claude/scripts/combine_receipts.py /tmp/receipt_config.json
```

(이미 venv가 있으면 재사용)

### 5단계: 결과 확인

- 생성된 PDF 파일 목록과 페이지 수 보고
- `open` 명령으로 결과 폴더 열기
- 결과 요약 테이블 출력:

| 파일 | 종류 | 기간 | 건수 | 페이지 |
|------|------|------|------|--------|

## 참고

- 스크립트 위치: `~/.claude/scripts/combine_receipts.py`
- 출력: 원본 디렉토리 내 `결과/` 폴더
- A4 300DPI (2480x3508px) 규격
- 쌍 영수증은 한 셀에 나란히 배치, 단일 영수증은 셀 하나에 하나
