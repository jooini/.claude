# Docker and Orchestration

## Dockerfile Best Practices
- 베이스 이미지는 `alpine`보다 보안 패치 주기가 명확한 이미지를 선택한다.
- `FROM`은 가능한 `digest`로 고정해 재현성을 확보한다.
- `USER nonroot`를 설정해 컨테이너 권한을 최소화한다.
- `COPY --chown`으로 파일 소유권을 명시한다.
- `RUN apt-get update && apt-get install` 후 캐시를 즉시 삭제한다.
- `HEALTHCHECK`를 넣어 오케스트레이터가 상태를 판단하게 한다.

### Layer Optimization
- 변경 빈도 낮은 의존성을 상위 레이어에 배치한다.
- `package-lock.json`, `poetry.lock`, `go.sum`을 먼저 복사한다.
- `RUN` 명령을 의미 단위로 묶되 과도한 단일 레이어는 피한다.
- `docker history`로 불필요한 레이어 크기를 점검한다.
- `.dockerignore`에 `node_modules`, `.git`, 빌드 산출물을 제외한다.
- 민감정보는 빌드 컨텍스트에 절대 포함하지 않는다.

## Multi-Stage Build
- `builder` 단계와 `runtime` 단계를 분리해 이미지 크기를 줄인다.
- `golang` 빌드는 `CGO_ENABLED=0`과 `-ldflags='-s -w'`를 고려한다.
- `npm ci` 후 산출물만 runtime으로 복사한다.
- Python은 `venv` 또는 `wheel` 아티팩트만 최종 이미지에 복사한다.
- 디버그 도구는 builder에만 두고 runtime에서는 제거한다.
- `distroless` 이미지 도입 시 디버깅 전략을 별도로 준비한다.

### BuildKit
- `DOCKER_BUILDKIT=1`을 기본 활성화한다.
- `RUN --mount=type=cache,target=/root/.cache`로 의존성 캐시를 사용한다.
- `RUN --mount=type=secret,id=pypi_token`으로 시크릿을 안전 주입한다.
- `docker buildx bake`로 멀티 타깃 빌드를 선언형으로 관리한다.
- `--platform linux/amd64,linux/arm64` 멀티아치 빌드를 표준화한다.
- build cache exporter를 `registry`로 보내 CI 속도를 개선한다.

## Image Security Scanning
- `Trivy image`로 OS 패키지와 라이브러리 취약점을 함께 스캔한다.
- `Snyk container test`로 정책 기반 차단을 적용한다.
- `grype`와 `syft` 조합으로 SBOM 생성 및 검증을 수행한다.
- high/critical CVE는 `fail build` 정책으로 차단한다.
- 예외 CVE는 만료일 포함한 `waiver` 문서로만 허용한다.
- 정기 리빌드로 base image patch를 자동 반영한다.

### Image Signing
- `cosign sign --key kms://... <image>`로 서명한다.
- `cosign verify`를 배포 파이프라인 게이트에 넣는다.
- `Sigstore Fulcio` 기반 keyless 서명도 고려한다.
- `attestation`으로 빌드 provenance를 생성한다.
- `policy-controller`로 서명 없는 이미지 배포를 차단한다.
- 서명 키 회전 정책을 KMS와 연동한다.

## docker-compose Patterns
- 로컬 개발은 `docker-compose.yml`과 `docker-compose.override.yml`로 분리한다.
- 서비스 간 의존은 `depends_on`보다 헬스체크 기반 대기를 우선한다.
- 공통 환경변수는 `.env`로 주입하되 민감값은 제외한다.
- `profiles`로 선택적 서비스 구동을 지원한다.
- 볼륨은 `named volume` 우선, bind mount는 개발 전용으로 제한한다.
- `docker compose config`로 최종 머지 결과를 검증한다.

## Kubernetes Core Resources
- `Deployment`는 무상태 워크로드, `StatefulSet`은 상태 저장 워크로드에 사용한다.
- `Service ClusterIP`를 내부 통신 기본값으로 사용한다.
- 외부 노출은 `Ingress` + `TLS` termination을 기본으로 둔다.
- `ConfigMap`과 `Secret`을 분리해 구성/비밀을 관리한다.
- `resource requests/limits`를 필수화해 스케줄링 안정성을 높인다.
- `namespace` 단위로 환경 경계를 분리한다.

### Kubernetes Commands
- `kubectl get deploy,po,svc -n <namespace>`로 기본 상태를 확인한다.
- `kubectl describe pod <pod>`로 이벤트와 probe 실패를 분석한다.
- `kubectl logs -f <pod> -c <container>`로 컨테이너별 로그를 본다.
- `kubectl rollout status deploy/<name>`로 배포 진행을 추적한다.
- `kubectl top pod`로 리소스 사용량을 점검한다.
- `kubectl diff -f manifests/`로 적용 전 변경을 검토한다.

## Helm and Kustomize
- `Helm chart`는 공통 템플릿 재사용과 버전 관리를 쉽게 한다.
- `values.yaml`는 환경별 파일로 분리하고 비밀은 외부 저장소를 쓴다.
- `helm lint`와 `helm template`를 CI에서 강제한다.
- `kustomize`는 베이스/오버레이 기반 환경 차이를 선언한다.
- `kubectl apply -k`로 오버레이를 직접 배포할 수 있다.
- `Helm`과 `kustomize` 혼용 시 책임 경계를 명확히 문서화한다.

## Registry Management
- `ECR`, `GCR`, `GHCR` 중 조직 표준 레지스트리를 정의한다.
- `immutable tags` 정책으로 태그 재사용을 차단한다.
- `lifecycle policy`로 오래된 이미지 정리를 자동화한다.
- `imagePullSecrets` 또는 OIDC 기반 pull 권한을 구성한다.
- 네트워크 제한은 `private endpoint`와 방화벽 규칙으로 강화한다.
- `registry replication`으로 지역 장애 대비를 구성한다.

## 안티패턴
- ❌ `root` 사용자로 앱 컨테이너를 실행한다.
- ✅ `USER 10001` 같은 비권한 사용자로 실행한다.
- ❌ 이미지를 `latest` 태그로만 관리한다.
- ✅ `semver` + `git sha` + `digest` 조합으로 추적 가능성을 높인다.
- ❌ 취약점 스캔 경고를 무시하고 배포한다.
- ✅ `severity gate`와 만료 있는 예외 정책을 적용한다.
- ❌ 쿠버네티스에서 `requests` 없이 배포한다.
- ✅ `requests/limits`와 `HPA` 기준을 함께 관리한다.
- ❌ Helm 값 파일에 비밀 값을 평문 저장한다.
- ✅ `External Secrets`, `Sealed Secrets`, `Vault` 연동을 사용한다.
