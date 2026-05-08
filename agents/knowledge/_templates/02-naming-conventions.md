# [영역] 명명 규칙

> 회사 결정 — 신입한테 사수가 알려줘야 하는 것.

## DB 테이블

| 영역 | 규칙 | 예시 | 비고 |
|------|------|------|------|
| 레거시 PHP | `T_` prefix | `T_Member`, `T_Notice` | 새 테이블도 따라야 |
| 신규 NestJS | `users`, `notices` (snake, plural) | - | T_ 안 씀 |

## 데이터베이스 (환경별)

| 환경 | DB명 | 호스트 | 비고 |
|------|------|--------|------|
| dev  | `dev_speakingmax` | `dev-wb-clickhouse` | - |
| qa   | `qa_speakingmax`  | `qa-wb-clickhouse`  | - |
| prod | `speakingmax`     | `prod-wb-clickhouse` | **prod만 prefix 없음** |

## 서비스 / 도메인

| 약어 | 풀네임 | 도메인 |
|------|-------|--------|
| B2C  | 일반 사용자 앱 | `b2c.maxaiapp.com` |
| B2B  | 기업 고객 앱   | `b2b.maxaiapp.com` |
| Hub  | Identity Hub  | `identity-hub.weaversbrain.com` |

## 환경 변수

```
{ENV}_{COMPONENT}_{KEY}
예: PROD_B2C_DB_HOST, QA_HUB_REDIS_URL
```

## 함정

- ⚠️ `prod` 만 prefix 없음 — 환경 분기 코드에서 자주 실수
- ⚠️ 새 환경(`pp`/`stg`) 추가 시 명명 규칙 회의 필요
