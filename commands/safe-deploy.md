# /safe-deploy - 배포 전 안전 통합 체크

배포 전 **서버 상태 + 환경 일관성 + 마이그레이션 상태**를 한 번에 검증하는 통합 명령.

## 사용법

- `/safe-deploy` — 기본 서버(dev2-backend) 전체 안전 체크
- `/safe-deploy dev2-backend` — 특정 서버
- `/safe-deploy prod` — 프로덕션 (🔴 사람 승인 필수)

## 수행 작업 (순차)

### 1단계: 서버 상태 (`Skill(check-server)`)

대상 서버의 Docker 컨테이너 상태:
- 모든 컨테이너 Up 상태인지
- Unhealthy 컨테이너 있는지
- 포트 매핑 정상인지
- 메모리/CPU 사용량 비정상 없는지

**Fail 조건**: Unhealthy 또는 Restart Loop 컨테이너 발견 → 배포 중단, 원인 분석

### 2단계: 환경 일관성 (`Skill(check-env)`)

환경별 설정 일관성 검증:
- 환경 변수 누락 없는지
- SSM placeholder 미해결 없는지 (`{{SSM:/path}}` 잔존)
- TODO 플레이스홀더 없는지
- Docker Compose env vs `.env` 일치하는지

**Fail 조건**: TODO 플레이스홀더 발견, SSM 미해결 → 배포 중단, 시크릿 주입 필요

### 3단계: 마이그레이션 상태 (`Skill(migration-status)`)

DB 마이그레이션 적용 상태:
- alembic head vs DB 현재 버전 일치 여부
- 미적용 migration 있는지
- 충돌하는 migration revision 없는지

**Fail 조건**: 미적용 migration 있음 → DB 마이그레이션 선행

### 4단계: 배포 상태 (`Skill(deploy-status)`)

CI/CD 배포 파이프라인 상태:
- 마지막 배포 시점
- 현재 진행 중인 배포 있는지
- CI 실패 잔존 여부

### 5단계: 종합 판정

전체 결과를 표로 정리:

| 단계 | 상태 | 비고 |
|------|------|------|
| 서버 상태 | ✅/⚠️/❌ | ... |
| 환경 일관성 | ✅/⚠️/❌ | ... |
| 마이그레이션 | ✅/⚠️/❌ | ... |
| 배포 상태 | ✅/⚠️/❌ | ... |

**최종 권고**:
- 모두 ✅ → 배포 진행 가능
- 하나라도 ⚠️ → 사용자 확인 후 진행
- 하나라도 ❌ → **배포 중단**, 원인 해결 후 재실행

### 6단계: 🔴 prod 환경 추가 안전장치

prod 인자 시:
- **사람 승인 필수** (auto mode에서도 필수 확인)
- 백업 시점 확인
- 롤백 절차 사전 안내
- 변경 영향 범위 (어떤 사용자/기능)

## 주의

- 이 명령은 **read-only** — 실제 배포 실행은 하지 않음
- 배포는 별도 `deploy.sh` 또는 CodeDeploy로 진행
- prod 배포 변경은 글로벌 ops 라우팅 (TYPE-F) — 단계별 검증 + 사람 승인

## 호출 예시

```
/safe-deploy
# → 4단계 통과 시 "배포 진행 가능" 안내

/safe-deploy prod
# → 5단계 + 🔴 사람 승인 대기
```

## 관련 자료

- `~/.claude/workflows/standard-routines.md` TYPE-F (ops)
- `~/Workspace/identity-platform-docker/.claude/CLAUDE.md` — 환경별 설정
- `~/Workspace/maxai-docker/.claude/CLAUDE.md` — 운영 환경
