# Knowledge Templates — 사내 고유 정보 작성 양식

## 목적

knowledge가 효과를 내려면 **Claude/GPT가 모르는 사내 고유 정보**여야 한다. 이 디렉토리는 그 양식 모음.

## 원칙

| ✅ 적기 | ❌ 적지 말기 |
|---|---|
| 우리 회사/팀에서만 진실인 정보 | 위키피디아·OWASP·RFC에 있는 내용 |
| 사내 시스템 토폴로지 | "REST API는 명사+HTTP 메서드" |
| 사내 라이브러리 함수명 | "bcrypt cost 12" |
| Incident 회고 | "Saga 패턴이란..." |
| ADR (왜 그렇게 결정했나) | "TDD는 Red-Green-Refactor" |
| 운영 일정 (freeze, 릴리스 컷) | "DRY/KISS/SOLID" |
| 사람-역할 매핑 | "Circuit Breaker 패턴" |

## 검증

작성 후 `~/.claude/scripts/kb-classify.py 파일경로` 로 점수 확인. **3점 이상**이면 사내 고유로 인정.

## 템플릿 목록

| # | 파일 | 용도 |
|---|------|-----|
| 01 | `01-system-topology.md` | 시스템 컴포넌트, 호출 흐름 |
| 02 | `02-naming-conventions.md` | DB prefix, 환경별 명명 |
| 03 | `03-internal-libraries.md` | 사내 라이브러리/함수 카탈로그 |
| 04 | `04-team-roles.md` | 사람-역할-담당영역 매핑 |
| 05 | `05-incident-rca.md` | incident 회고 양식 |
| 06 | `06-adr.md` | Architecture Decision Record |
| 07 | `07-operations-calendar.md` | freeze/릴리스 일정 |
| 08 | `08-domain-glossary.md` | 제품 용어집 |
| 09 | `09-security-policy.md` | 회사 보안 결정 |
| 10 | `10-external-deps.md` | 외부 SDK/API 호환성 |

## 사용

각 템플릿을 복사하여 적절한 `knowledge/{role}/` 디렉토리에 배치:

```bash
cp _templates/05-incident-rca.md backend-developer/27-deploy-rollback-incident.md
# 내용 채워 넣기
```
