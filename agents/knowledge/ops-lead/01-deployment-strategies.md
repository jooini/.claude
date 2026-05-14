# Deployment Strategies

## Blue-Green Deployment
- `blue` 환경과 `green` 환경을 분리해서 동일 스펙으로 유지한다.
- `ALB` 타깃 그룹 전환은 `aws elbv2 modify-listener`로 원자적으로 수행한다.
- `Nginx` 업스트림 스위칭은 `nginx -s reload` 전에 `nginx -t`를 강제한다.
- 배포 직전 `smoke test`를 `curl -f https://green.example.com/healthz`로 수행한다.
- `database schema` 호환성을 위해 `expand-contract` 패턴을 선적용한다.
- 트래픽 전환 후 `5xx`, `p95 latency`, `error rate`를 10분 관찰한다.

### Traffic Switch Checklist
- `readinessProbe` 성공 상태를 `kubectl get pods -w`로 확인한다.
- `connection draining`은 `deregistration_delay.timeout_seconds`로 설정한다.
- `DNS TTL`이 길면 `Route53 weighted record` 방식으로 우회한다.
- `session stickiness` 사용 시 세션 저장소를 `Redis`로 외부화한다.
- `feature flag`가 있다면 `green`에서 기본값을 보수적으로 시작한다.
- 전환 직후 `rollback` 명령을 미리 터미널 히스토리에 준비한다.

## Canary Deployment
- `Argo Rollouts`의 `setWeight` 단계로 트래픽을 점진적으로 늘린다.
- `canary analysis`는 `success-rate`와 `latency` 임계치를 함께 본다.
- `1% -> 5% -> 20% -> 50% -> 100%` 식의 단계적 승격을 사용한다.
- `header-based routing`으로 내부 사용자만 먼저 노출한다.
- `Prometheus` 쿼리 예시는 `rate(http_requests_total{status=~"5.."}[5m])`를 쓴다.
- `abort` 조건을 엄격히 걸어 자동 중단을 활성화한다.

### Canary Metrics Gate
- `error budget burn rate`가 임계 초과 시 즉시 `pause`한다.
- `p99 latency` 상승이 `baseline` 대비 20% 초과면 중단한다.
- `saturation` 지표로 `CPU throttling`과 `memory pressure`를 본다.
- `business KPI`로 결제 성공률, 로그인 성공률을 함께 검증한다.
- 분석 창은 최소 `10m` 이상으로 노이즈를 줄인다.
- 야간 배포는 `on-call` 인력 대기 조건을 붙인다.

## Rolling Deployment
- `Kubernetes Deployment`에서 `maxSurge`와 `maxUnavailable`을 명시한다.
- 기본값 대신 `maxUnavailable: 0`으로 무중단 성향을 강화한다.
- `PodDisruptionBudget`을 같이 설정해 가용성 하락을 방지한다.
- `preStop` 훅으로 `graceful shutdown` 시간을 확보한다.
- `terminationGracePeriodSeconds`를 실제 종료 시간보다 길게 둔다.
- `HPA`와 충돌하지 않게 배포 중 스케일 변동을 모니터링한다.

### Zero-Downtime Probes
- `readinessProbe`는 의존성 확인 포함, `livenessProbe`는 최소화한다.
- `startupProbe`를 사용해 초기화가 긴 앱의 오탐을 줄인다.
- `pod anti-affinity`로 동일 노드 집중 배치를 피한다.
- `node drain` 시 `kubectl drain --ignore-daemonsets` 정책을 문서화한다.
- `graceful timeout`은 API, worker를 분리해 설정한다.
- `grpc health check`는 `grpc_health_probe` 사용을 표준화한다.

## Feature Flag Strategy
- `LaunchDarkly`, `Unleash`, `Flipt` 중 하나를 표준으로 정한다.
- `flag naming`은 `domain.feature.variant` 규칙으로 관리한다.
- `kill switch` 플래그를 모든 핵심 기능에 준비한다.
- `percentage rollout`은 사용자 세그먼트 기준으로 나눈다.
- `flag debt` 방지를 위해 제거 기한을 `Jira` 티켓으로 만든다.
- 배포와 릴리즈를 분리해 `dark launch`를 지원한다.

### Flag Governance
- `owner`, `created_at`, `sunset_date` 메타데이터를 필수화한다.
- `stale flag` 탐지는 CI에서 주기적으로 실행한다.
- `flag prerequisites` 의존 관계를 다이어그램으로 기록한다.
- 민감 기능은 `admin override` 권한을 RBAC로 제한한다.
- `A/B test` 플래그와 운영 플래그를 분리 관리한다.
- `default variation`은 실패 시 안전한 값으로 둔다.

## GitOps Deployment
- `ArgoCD`는 `syncPolicy: automated`와 `prune` 정책을 신중히 사용한다.
- `Flux`는 `Kustomization` 단위로 팀 경계를 분리한다.
- `declarative desired state`를 `Git`만 단일 소스로 유지한다.
- 긴급 변경도 `kubectl edit` 대신 `Git commit`으로 반영한다.
- `drift detection` 이벤트를 `Slack` 알림으로 연결한다.
- `sync wave`를 사용해 CRD -> 앱 순서 의존성을 제어한다.

### Promotion Flow
- `dev -> staging -> prod` 브랜치 승격 규칙을 문서화한다.
- `image tag`는 `sha256 digest` 고정으로 재현성을 확보한다.
- `signed commit`과 `branch protection`을 함께 적용한다.
- `policy as code`는 `OPA Gatekeeper`나 `Kyverno`로 강제한다.
- `ArgoCD AppProject`로 네임스페이스 접근 범위를 제한한다.
- `sync window`로 금지 시간대 자동 배포를 차단한다.

## Database Migration Coordination
- `expand-contract`로 스키마 변경을 2단계 이상으로 나눈다.
- `Flyway` 또는 `Liquibase` 마이그레이션은 idempotent하게 작성한다.
- `long-running migration`은 배치 윈도우로 분리한다.
- `backfill job`은 `chunk size`와 `sleep interval`을 조정한다.
- `dual-write` 기간에는 정합성 검증 쿼리를 자동화한다.
- `read path` 선호를 새 컬럼으로 전환 후 구 컬럼 제거한다.

### Migration Safety
- 배포 전 `pg_dump --schema-only` 스냅샷을 저장한다.
- `ALTER TABLE ... ADD COLUMN NULL`을 우선 사용해 락을 줄인다.
- `CREATE INDEX CONCURRENTLY`로 쓰기 중단을 피한다.
- `lock_timeout`, `statement_timeout`을 세션에 명시한다.
- `rollback SQL`을 같은 PR에 포함한다.
- 마이그레이션 후 `row count` 검증을 자동 실행한다.

## Rollback Strategy
- `application rollback`과 `data rollback`을 분리 설계한다.
- `kubectl rollout undo deployment/<name>` 명령을 플레이북에 고정한다.
- `helm rollback <release> <revision>` 기준을 릴리즈 노트에 기록한다.
- `immutable artifact` 정책으로 동일 바이너리 재배포를 보장한다.
- `config rollback`은 `Git revert` 후 GitOps 동기화로 수행한다.
- `circuit breaker` 트립 시 자동 롤백 조건을 정의한다.

### Rollback Validation
- 롤백 직후 `synthetic check`와 핵심 거래 테스트를 실행한다.
- `cache schema` 변경은 `versioned key`로 역호환을 유지한다.
- `consumer contract test` 결과를 롤백 승인 조건에 포함한다.
- `rollback latency`를 지표화해 매 분기 개선한다.
- `post-rollback incident note`를 24시간 내 작성한다.
- 재배포 금지 창을 둬 flapping 배포를 방지한다.

## 안티패턴
- ❌ `latest` 태그를 프로덕션 배포에 사용한다.
- ✅ `image digest` 고정과 `provenance` 검증을 사용한다.
- ❌ DB 파괴적 변경을 앱 배포와 동시에 수행한다.
- ✅ `expand-contract`와 다단계 릴리즈로 분리한다.
- ❌ `kubectl apply` 수동 핫픽스로 Git 상태를 무시한다.
- ✅ 모든 변경을 `GitOps` 경로로 반영하고 드리프트를 차단한다.
- ❌ 관측 없이 canary 승격을 자동화한다.
- ✅ `metric gate`와 `abort` 규칙을 함께 강제한다.
- ❌ 롤백 절차를 문서만 두고 리허설하지 않는다.
- ✅ 월 1회 `game day`로 롤백 리허설을 실행한다.
