# 표준 팀 템플릿

> 멀티프로젝트 작업 시 `/team` spawn 가이드. 자주 같이 수정되는 프로젝트 묶음별 표준 구성.

## 호출 방법

```
/team {템플릿명} "{태스크 설명}"
```

내가 해당 템플릿대로 멤버를 spawn하고 작업 분배.

## 템플릿 1: SSO 코어 (sso-core)

**언제**: SSO 인증/인가 변경, 로그인 플로우 수정, 토큰 발급/검증, Keycloak Realm 변경

**프로젝트 묶음**:
- identity-hub (FastAPI BFF)
- identity-keycloak (KC Realm/SPI)
- maxai-b2c-backend (PHP 연동)
- identity-hub-frontend (Admin)

**멤버 구성**:
| 멤버 | 역할 | cwd |
|------|------|-----|
| ih-dev | identity-hub 변경 | identity-hub |
| kc-dev | Keycloak SPI/Realm | identity-keycloak |
| b2c-dev | PHP 연동 | maxai-b2c-backend |
| admin-dev | Admin UI | identity-hub-frontend |
| reviewer | code-reviewer 3중 | (선택) |

**워크플로우**:
1. 각자 cwd에서 변경
2. 통합 단계: identity-hub 가 마스터, 나머지 동기화
3. 통합 검증: cross-check 스킬

## 템플릿 2: B2C 풀스택 (b2c-fullstack)

**언제**: 회원/로그인/마이페이지 등 B2C 사용자 기능 추가/수정

**프로젝트 묶음**:
- maxai-b2c-backend (PHP API)
- identity-hub (인증)
- identity-hub-frontend (선택, 관리 화면)

**멤버 구성**:
| 멤버 | 역할 | cwd |
|------|------|-----|
| be-dev | PHP API | maxai-b2c-backend |
| auth-dev | 인증 연동 | identity-hub |
| qa | 테스트 케이스 | (글로벌) |
| reviewer | 보안 리뷰 | (글로벌) |

## 템플릿 3: 플랫폼 신규 (platform-new)

**언제**: 신규 Spring Boot 마이크로서비스 개발 (Kotlin + JPA)

**프로젝트 묶음**:
- wb-platform-backend (Kotlin Core)
- member-api (회원 도메인)
- (frontend 추가 예정)

**멤버 구성**:
| 멤버 | 역할 | cwd |
|------|------|-----|
| platform-dev | Kotlin/Spring | wb-platform-backend |
| member-dev | 회원 도메인 | member-api |
| qa | 통합 테스트 | (글로벌) |
| reviewer | 도메인 리뷰 | (글로벌) |

## 템플릿 4: 인프라 (infra)

**언제**: Docker compose 변경, 환경 변수 통합, 배포 스크립트 수정, Terraform 변경

**프로젝트 묶음**:
- maxai-docker (운영 환경)
- identity-platform-docker (로컬 환경)
- terracore-infra (AWS)

**멤버 구성**:
| 멤버 | 역할 | cwd |
|------|------|-----|
| ops | docker compose | maxai-docker |
| local-ops | 로컬 환경 | identity-platform-docker |
| iac | Terraform | terracore-infra |
| reviewer | adversarial-review | (글로벌, 보안 트리거) |

🔴 **주의**: 인프라 변경은 사람 승인 필수. 단계별 검증.

## 템플릿 5: 단일 프로젝트 병렬 (single-parallel)

**언제**: 한 프로젝트에서 6+ 파일 리팩터, 테스트 추가 등 큰 작업

**프로젝트**: 임의 (1개)

**멤버 구성**:
| 멤버 | 역할 | worktree |
|------|------|----------|
| worker-1 | 모듈 A 변경 | task-a |
| worker-2 | 모듈 B 변경 | task-b |
| worker-3 | 모듈 C 변경 | task-c |
| integrator | 통합 검증 | main |

worktree 격리로 충돌 방지. 4월 23일 identity-hub 리팩터 사례 참조.

## 팀 청소 정책

### 정리 대상
1. **config.json 없는 팀** → 즉시 삭제 (default, UUID들)
2. **30일 이상 비활성 + 작업 완료** → archive로 이동
3. **isActive: false 인데 inboxes에 idle_notification만 있음** → 작업 끝난 것 → archive

### 청소 명령
```bash
# 비활성 팀 archive
mkdir -p ~/.claude/teams/.archive/$(date +%Y-%m)
for d in ~/.claude/teams/*/; do
  name=$(basename "$d")
  if [ ! -f "$d/config.json" ]; then continue; fi
  # 30일 이상 비활성 체크
  ...
done
```

## 호출 예시

```
# SSO 토큰 만료 정책 변경
/team sso-core "토큰 만료 24h → 1h 단축, refresh_token 회전 적용"

# B2C 회원 탈퇴 강화
/team b2c-fullstack "회원 탈퇴 시 30일 유예, 데이터 즉시 마스킹"

# 인프라 시크릿 정리
/team infra "Prod DB 비밀번호 플레이스홀더 → AWS Secrets Manager"

# 단일 프로젝트 큰 리팩터
/team single-parallel "identity-hub auth_service 4개 파일로 분할"
```

## 팀 vs 단일 에이전트 선택 기준

| 상황 | 선택 |
|------|------|
| 1 프로젝트, 3 파일 미만 | 단일 에이전트 |
| 1 프로젝트, 6+ 파일 | single-parallel 팀 |
| 2+ 프로젝트, 동일 변경 | 멀티프로젝트 팀 |
| 보안/인프라/배포 | infra 팀 + 사람 승인 |
| Spec 단계 (PRD) | po + designer 단일 호출 (팀 불필요) |

## 효과 측정

- 팀 사용 후 `/retro 7` 으로 처리 속도 비교
- 단일 에이전트 vs 팀 처리 시간 차이 기록
