# 스피킹맥스/맥스AI 명명 규칙

> 회사 결정 — 신입한테 사수가 알려줘야 하는 것.

## DB 테이블

| 영역 | 규칙 | 예시 | 비고 |
|------|------|------|------|
| 레거시 PHP (B2C) | `T_` prefix + PascalCase | `T_Member`, `T_Notice` | 새 테이블도 따라야 |
| 신규 NestJS | snake_case + plural | `users`, `notices` | `T_` 안 씀 |
| Identity Hub (Python/FastAPI) | snake_case + plural | `users`, `sessions`, `service_tokens` | - |

## ClickHouse DB (환경별)

| 환경 | DB명 | 호스트 | 비고 |
|------|------|--------|------|
| dev  | `dev_speakingmax` | `dev-wb-clickhouse` | - |
| qa   | `qa_speakingmax`  | `qa-wb-clickhouse`  | - |
| prod | `speakingmax`     | `prod-wb-clickhouse` | **prod만 prefix 없음** ⚠️ |

스키마 파일도 환경별 분리: `clickhouse/init.{dev|qa|prod}.sql`. `docker/{env}/.env`의 `CLICKHOUSE_DATABASE`가 DB명과 일치해야 함.

## 서비스 / 도메인

| 약어 | 풀네임 | 도메인 (LIVE) |
|------|-------|----------|
| B2C  | 일반 사용자 앱 | `b2c.maxaiapp.com` |
| B2B  | 기업 고객 앱   | ❓ 미확인 (`b2b.maxaiapp.com` 추정) |
| Hub  | Identity Hub  | `identity-hub.weaversbrain.com` |
| 회사 도메인 | weaversbrain (지주) / maxaiapp (서비스) / speakingmax (브랜드) | - |

## 환경 (5종)

| 약어 | 풀네임 | 비고 |
|------|-------|------|
| LOCAL | 개발자 로컬 | docker-compose |
| DEV   | 개발 | 자동 배포 |
| QA    | 품질 검증 | 자동 배포 |
| PP    | Pre-Production | 운영 직전 검증 |
| LIVE  | Production | 수동 승인 배포 |

## 환경 변수 형식

```
{ENV}_{COMPONENT}_{KEY}
예시: PROD_B2C_DB_HOST, QA_HUB_REDIS_URL
```

## 함정

- ⚠️ `prod` ClickHouse DB만 prefix 없음 — 환경 분기 코드에서 자주 실수
- ⚠️ 도메인 헷갈림: `weaversbrain.com` (회사) ≠ `maxaiapp.com` (B2C 서비스)
- ⚠️ STT 자동 받아쓰기는 사람 이름 정확도 낮음 → "현주"/"홍주" → 항상 **"현준"** 으로 정정
