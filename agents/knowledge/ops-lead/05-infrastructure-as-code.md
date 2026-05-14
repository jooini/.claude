# Infrastructure as Code

## Terraform Core Workflow
- 기본 흐름은 `terraform fmt -> terraform validate -> terraform plan -> terraform apply`다.
- `plan` 산출물은 `-out=tfplan`으로 고정 파일로 저장한다.
- 승인된 계획만 `terraform apply tfplan`으로 반영한다.
- CI에서는 `terraform init -backend-config=...`를 환경별로 분리한다.
- `-var-file=env/prod.tfvars`로 입력 변수를 명시적으로 주입한다.
- 파괴적 변경은 `-target` 남용 대신 모듈 분리로 예방한다.

### State Safety
- 원격 상태는 `S3 backend`에 저장하고 버전 관리를 활성화한다.
- 잠금은 `DynamoDB` 테이블로 강제해 동시 apply 충돌을 막는다.
- state 접근은 최소 IAM 권한으로 제한한다.
- `terraform state pull` 결과를 임의 편집하지 않는다.
- state 백업 복구 절차를 runbook에 문서화한다.
- 재해 복구 테스트로 state 복원 시간을 측정한다.

## Module Design
- 모듈은 `inputs`, `outputs`, `locals` 경계를 명확히 유지한다.
- 재사용 모듈은 `versions.tf`에서 provider 버전을 고정한다.
- `variable validation`으로 잘못된 입력을 조기 차단한다.
- 모듈 이름은 도메인 단위(`network`, `database`, `eks`)로 분리한다.
- 모듈 내부에서 리소스 이름 규칙을 일관되게 유지한다.
- `README`에 예제와 required variables를 명시한다.

### Module Versioning
- 모듈 배포는 `git tag` 또는 내부 registry 버전으로 관리한다.
- breaking 변경은 major 버전을 올려 호환성을 분리한다.
- 소비 프로젝트는 `ref=v1.4.2`처럼 고정 버전을 사용한다.
- 변경 로그에 state migration 필요 여부를 기록한다.
- `tflint`로 모듈 품질 검사를 자동화한다.
- 공통 태그 정책을 모듈 기본값으로 제공한다.

## Workspaces and Environment Strategy
- `terraform workspace`는 소규모 분리에만 제한적으로 사용한다.
- 대규모 환경 분리는 디렉터리 또는 스택 분리를 우선한다.
- `dev/stage/prod` 입력값은 별도 `tfvars`로 관리한다.
- 환경별 backend 키 경로를 명확히 분리한다.
- 워크스페이스 전환 전 `terraform workspace show`를 확인한다.
- 프로덕션 apply는 별도 승인 파이프라인을 적용한다.

## Terragrunt Patterns
- `terragrunt.hcl`로 공통 backend/provider 설정을 상속한다.
- `include`와 `generate` 블록으로 중복 코드를 제거한다.
- `dependencies`로 스택 적용 순서를 선언한다.
- `terragrunt run-all plan`으로 전체 영향도를 빠르게 확인한다.
- `run-all apply`는 환경 락과 승인 절차를 함께 사용한다.
- 모듈 소스는 내부 레지스트리로 고정해 변동성을 줄인다.

## Drift Detection
- 정기적으로 `terraform plan -detailed-exitcode`를 실행한다.
- exit code `2`는 drift 또는 변경 필요 상태로 분류한다.
- 수동 변경 감지는 `CloudTrail` 이벤트와 교차 검증한다.
- drift 발견 시 원인 라벨을 `hotfix`, `console-change`, `policy-change`로 분류한다.
- 콘솔 변경 복구는 코드 우선으로 되돌린다.
- drift 리포트를 주간 운영 회의에 공유한다.

## Policy and Security
- `OPA`, `Sentinel`, `Conftest`로 정책 위반을 사전 차단한다.
- public `S3 bucket`, `0.0.0.0/0` 보안그룹을 금지 규칙으로 설정한다.
- 시크릿은 `AWS Secrets Manager`, `Vault` 참조로 주입한다.
- `terraform output -json` 민감값은 로그 저장을 금지한다.
- provider 자격증명은 `OIDC` 임시 토큰 기반으로 발급한다.
- `tfsec`, `checkov`를 CI 필수 단계로 넣는다.

## Pulumi and CDK
- `Pulumi`는 코드형 IaC가 필요한 복잡 로직에 적합하다.
- `AWS CDK`는 애플리케이션 팀의 TypeScript 친화성이 높다.
- 상태 저장소(`Pulumi backend`) 보안 정책을 Terraform과 동일 수준으로 맞춘다.
- 코드 리뷰 시 인프라 diff 가시성을 확보하는 플러그인을 사용한다.
- 언어 런타임 의존성 업데이트 정책을 별도로 유지한다.
- IaC 도구 혼용 시 ownership 경계를 문서화한다.

## OpenTofu Adoption
- `OpenTofu`는 Terraform 호환 워크플로우를 유지하며 대안이 된다.
- `tofu init`, `tofu plan`, `tofu apply` 명령을 CI 병행 검증한다.
- provider 호환성 매트릭스를 사전에 검증한다.
- 레거시 모듈의 `terraform` 블록 제약조건을 점검한다.
- 이행 기간에는 동일 state에 동시 도구 접근을 금지한다.
- 전환 결정 시 라이선스, 생태계, 지원 정책을 비교 기록한다.

## Ansible Integration
- VM 구성관리에는 `Ansible playbook`을 Terraform 후속 단계로 연결한다.
- 동적 인벤토리는 `aws_ec2` 플러그인으로 자동 생성한다.
- `ansible-lint`와 `molecule` 테스트를 CI에 포함한다.
- 멱등성 보장을 위해 `changed_when` 남용을 피한다.
- 비밀은 `ansible-vault` 또는 외부 시크릿 저장소를 사용한다.
- 인프라 생성/구성 경계는 runbook에 명확히 정의한다.

## 안티패턴
- ❌ 로컬 state 파일을 팀 공유 드라이브로 관리한다.
- ✅ `S3 + DynamoDB lock` 원격 상태로 일원화한다.
- ❌ `terraform apply`를 plan 검토 없이 바로 실행한다.
- ✅ 승인된 `tfplan`만 적용하는 2단계 절차를 강제한다.
- ❌ 콘솔 수동 변경 후 코드 반영을 미룬다.
- ✅ drift 탐지 후 즉시 코드와 상태를 정합화한다.
- ❌ 모듈 버전을 `main` 브랜치로 직접 참조한다.
- ✅ 태그 버전 고정과 변경 로그 검토를 기본으로 둔다.
- ❌ 시크릿 값을 `tfvars` 평문으로 커밋한다.
- ✅ 외부 비밀 저장소 참조와 CI 마스킹을 사용한다.
