# GitHub Actions

## Workflow Syntax Basics
- 워크플로우는 `.github/workflows/*.yml` 경로에 저장한다.
- `on: [push, pull_request, workflow_dispatch]` 트리거 조합을 명시한다.
- `jobs.<job_id>.runs-on`에 `ubuntu-latest` 또는 self-hosted 라벨을 지정한다.
- 공통 환경변수는 `env:` 블록으로 선언하고 민감값은 제외한다.
- `permissions:`를 최소 권한으로 설정해 `GITHUB_TOKEN` 범위를 줄인다.
- `concurrency:`로 중복 실행을 취소해 낭비를 줄인다.

### YAML Patterns
- `if: github.ref == 'refs/heads/main'`로 메인 브랜치 전용 잡을 분리한다.
- `needs:`를 사용해 DAG 의존성을 명확히 표현한다.
- `timeout-minutes`를 설정해 무한 대기를 방지한다.
- `defaults.run.shell: bash`로 스크립트 일관성을 맞춘다.
- `continue-on-error: false`를 기본으로 유지한다.
- 긴 스크립트는 리포지토리 `scripts/`로 분리한다.

## Matrix Builds
- `strategy.matrix`로 `node`, `python`, `os` 조합 테스트를 병렬화한다.
- `include`와 `exclude`로 예외 케이스를 정교하게 제어한다.
- `fail-fast: false`로 전체 결과를 수집해 회귀 범위를 파악한다.
- 매트릭스별 아티팩트 이름에 `${{ matrix.* }}`를 포함한다.
- 고비용 조합은 `if:` 조건으로 PR에서 축소한다.
- 캐시 키에 런타임 버전을 포함해 충돌을 방지한다.

### Matrix Example Topics
- `go-version: [1.22, 1.23]` 다중 버전 검증을 운영한다.
- `architecture: [amd64, arm64]` 이미지 빌드 행렬을 적용한다.
- `test shard`를 `matrix.shard`로 나눠 테스트 시간을 단축한다.
- `coverage merge` 단계로 분산 결과를 통합한다.
- flaky job은 `max-parallel`을 낮춰 리소스 압박을 줄인다.
- 병렬 로그는 `step summary`로 링크를 모은다.

## Reusable Workflows
- 공통 파이프라인은 `workflow_call` 기반으로 재사용한다.
- 입력값은 `inputs` 타입(`string`, `boolean`)을 명시한다.
- 공통 시크릿은 `secrets: inherit`보다 명시 전달을 우선한다.
- 조직 표준 워크플로우를 버전 태그로 고정 참조한다.
- `composite action`은 로직 재사용, `reusable workflow`는 파이프라인 재사용에 쓴다.
- breaking 변경은 새 버전으로 배포해 호환성을 유지한다.

### Action Versioning
- `uses: actions/checkout@v4`처럼 major 버전 고정을 기본으로 둔다.
- 고위험 액션은 `@<commit-sha>` pinning을 적용한다.
- 내부 액션은 `CODEOWNERS` 검토를 필수화한다.
- 릴리즈 노트에 변경된 입력/출력 스키마를 기록한다.
- deprecated 액션 사용을 `actionlint`로 탐지한다.
- 의존성 업데이트는 `Dependabot` 자동 PR로 관리한다.

## Secrets and OIDC
- 장기 `AWS_ACCESS_KEY_ID` 대신 `OIDC` + `assume role`을 사용한다.
- `id-token: write` 권한은 필요한 잡에만 제한한다.
- `aws-actions/configure-aws-credentials`로 임시 자격증명을 발급한다.
- `audience`, `subject` 조건으로 `IAM trust policy`를 좁힌다.
- `GCP Workload Identity Federation`으로 키리스 인증을 구현한다.
- `Azure federated credentials`도 동일한 키리스 원칙을 적용한다.

### Secret Hygiene
- 시크릿은 `repo`, `env`, `org` 스코프를 구분해 최소 노출한다.
- `environment protection rule`로 수동 승인 단계를 추가한다.
- 로그 마스킹 누락 여부를 `::add-mask::`로 보완한다.
- `pull_request_target` 이벤트의 시크릿 노출 위험을 피한다.
- 서드파티 액션에 시크릿 전달을 최소화한다.
- 시크릿 회전 주기를 티켓화해 자동 점검한다.

## Caching and Performance
- `actions/cache` 키는 `hashFiles('**/lockfile')` 기반으로 구성한다.
- `restore-keys`를 사용해 부분 히트를 유도한다.
- `docker/build-push-action`의 `cache-from`, `cache-to`를 활성화한다.
- 큰 의존성은 `setup-*` 액션 내장 캐시를 우선 사용한다.
- 캐시 오염 의심 시 키 버전을 올려 즉시 무효화한다.
- 아티팩트는 최소 기간만 보관해 저장비를 줄인다.

### Runner Performance
- self-hosted는 `ephemeral runner`로 깨끗한 실행환경을 유지한다.
- `runner group`으로 민감 워크로드를 분리한다.
- 대형 빌드는 `larger runners` 또는 전용 VM을 사용한다.
- 디스크 부족 예방을 위해 빌드 후 `docker system prune` 정책을 둔다.
- 큐 적체는 `queued_duration` 지표로 모니터링한다.
- 러너 업데이트 자동화로 보안 패치 누락을 막는다.

## Branch Protection and Governance
- `required status checks`에 테스트, 린트, 보안스캔을 포함한다.
- `require pull request reviews` 최소 승인 수를 강제한다.
- `dismiss stale reviews`를 켜서 재검토를 강제한다.
- `require linear history`로 merge commit 혼선을 줄인다.
- `restrict who can push`로 직접 푸시를 제한한다.
- `signed commits` 정책으로 출처 무결성을 강화한다.

### CODEOWNERS
- `CODEOWNERS` 파일로 디렉터리별 책임자를 명시한다.
- 핵심 경로는 최소 2인 리뷰를 요구한다.
- 플랫폼 팀 경로에 `@org/platform-team`을 지정한다.
- 과도한 광역 소유권으로 리뷰 병목이 생기지 않게 분할한다.
- 신규 서비스 생성 시 CODEOWNERS 갱신을 체크리스트화한다.
- 휴가/온콜 대체자 룰을 팀 문서에 유지한다.

## Security Scanning in CI
- `CodeQL` 정적 분석을 기본 워크플로우에 포함한다.
- `Trivy`로 컨테이너 이미지와 IaC 취약점을 함께 스캔한다.
- `gitleaks`로 시크릿 커밋 누출을 차단한다.
- `npm audit`, `pip-audit`, `osv-scanner`를 언어별로 실행한다.
- `SARIF` 업로드로 보안 결과를 PR에 시각화한다.
- high/critical 취약점은 빌드 실패로 차단한다.

## 안티패턴
- ❌ `pull_request_target`에서 포크 코드를 checkout 후 시크릿을 사용한다.
- ✅ 포크 PR은 시크릿 없는 검증 경로로 분리한다.
- ❌ `GITHUB_TOKEN` 기본 권한을 그대로 둔다.
- ✅ `permissions: read-all` 또는 잡 단위 최소 권한으로 축소한다.
- ❌ 재사용 워크플로우 버전을 `main` 브랜치로 참조한다.
- ✅ 태그 또는 `commit SHA`로 고정해 재현성을 확보한다.
- ❌ self-hosted 러너를 장기 재사용해 오염 상태를 방치한다.
- ✅ `ephemeral` 전략과 실행 후 정리 자동화를 적용한다.
- ❌ required check 이름을 자주 바꿔 보호 규칙을 깨뜨린다.
- ✅ 체크 이름은 계약처럼 고정하고 변경 시 마이그레이션한다.
