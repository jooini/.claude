# Monitoring and Alerting

## Prometheus Fundamentals
- `Prometheus`는 pull 모델로 `metrics endpoint`를 수집한다.
- 메트릭 명명은 `snake_case`와 단위 접미사 `_seconds`, `_bytes`를 사용한다.
- `counter`, `gauge`, `histogram`, `summary` 타입을 목적에 맞게 선택한다.
- `relabel_configs`로 불필요 라벨을 줄여 cardinality 폭증을 막는다.
- `recording rules`로 고비용 쿼리를 사전 계산한다.
- 원격 저장은 `Thanos` 또는 `Mimir`로 확장한다.

### PromQL Patterns
- 에러율은 `sum(rate(http_requests_total{status=~"5.."}[5m]))`로 계산한다.
- 지연시간은 `histogram_quantile(0.95, sum(rate(..._bucket[5m])) by (le))`를 사용한다.
- saturation은 `node_cpu_seconds_total`과 `container_cpu_usage_seconds_total`을 함께 본다.
- `increase()`는 누적량, `rate()`는 초당 변화량 계산에 쓴다.
- `offset`을 이용해 동일 시간대 전일 비교를 수행한다.
- 경보 임계치 튜닝은 `for: 5m`으로 노이즈를 완화한다.

## Grafana and Dashboards
- 대시보드는 `golden signals` 중심으로 구성한다.
- `Grafana folder`를 서비스/팀 단위로 분리한다.
- 패널 변수는 `environment`, `region`, `service`를 표준화한다.
- `dashboard as code`는 `jsonnet` 또는 `grafonnet`으로 관리한다.
- 변경은 `Git PR` 리뷰를 거쳐 반영한다.
- 대시보드마다 `runbook URL` 링크를 포함한다.

### Dashboard Design
- 상단에는 `SLO status`, `error budget`를 먼저 배치한다.
- 중단에는 `RED method` 패널을 고정 배치한다.
- 하단에는 인프라 `USE method` 패널을 배치한다.
- 로그/트레이스 drill-down 링크를 패널에 연결한다.
- `annotation`으로 배포 이벤트를 표시한다.
- 모바일 온콜을 고려해 핵심 패널을 1스크린에 넣는다.

## Logs with Loki
- 애플리케이션 로그는 `JSON structured logging`을 기본으로 한다.
- `Loki` 라벨은 저카디널리티 원칙으로 최소화한다.
- `promtail` 또는 `fluent-bit`로 로그 수집 파이프라인을 구성한다.
- 민감정보는 수집 전에 `redaction` 필터로 마스킹한다.
- 보존 기간은 규제와 비용을 함께 고려해 설정한다.
- 샘플링 정책을 서비스 중요도에 따라 차등 적용한다.

### Log Query Patterns
- `|= "ERROR"`와 `| json` 파서를 조합해 오류 탐색을 가속한다.
- `count_over_time`로 특정 오류 패턴 급증을 탐지한다.
- request id 기반 상관분석으로 트레이스와 연결한다.
- 로그 드롭률 지표를 수집해 수집 파이프라인 건강도를 본다.
- `tenant` 분리로 멀티팀 로그 접근을 격리한다.
- 경보 연동 시 동일 이벤트 dedup 규칙을 구성한다.

## OpenTelemetry
- `OpenTelemetry SDK`로 metric, log, trace를 표준 수집한다.
- `OTLP` 프로토콜로 collector에 전송한다.
- 리소스 속성에 `service.name`, `deployment.environment`를 필수화한다.
- 자동 계측(`auto-instrumentation`)과 수동 계측을 혼합한다.
- 샘플링은 `parentbased_traceidratio`를 기본으로 시작한다.
- collector 파이프라인에서 배치/리트라이/큐를 설정한다.

### Context Propagation
- `W3C traceparent` 헤더 전파를 모든 게이트웨이에 적용한다.
- 비동기 메시징은 `baggage`와 trace context를 함께 전달한다.
- 프록시 계층에서 헤더 제거 여부를 점검한다.
- cross-language 환경에서 동일 semantic convention을 강제한다.
- 누락 span 탐지를 위한 synthetic trace를 주기 실행한다.
- trace id를 로그 필드로 기록해 상관분석을 단순화한다.

## Distributed Tracing
- `Jaeger` 또는 `Tempo`로 분산 트레이싱 백엔드를 운영한다.
- `critical path` 분석으로 병목 서비스를 식별한다.
- `span attributes`에 DB 쿼리명, 외부 API 대상, retry 횟수를 기록한다.
- high-cardinality 속성은 이벤트로 내리고 태그 남용을 피한다.
- tail-based sampling으로 오류 트래픽을 우선 수집한다.
- trace 기반 SLO 디버깅 플레이북을 팀에 공유한다.

## SLO/SLI/Error Budget
- `SLI`는 사용자 관점 성공률과 지연시간을 정의한다.
- `SLO`는 예: 30일 가용성 99.9%처럼 명시 숫자로 합의한다.
- `error budget` 소진율을 릴리즈 속도 조절 신호로 사용한다.
- burn rate 알림은 `multi-window multi-burn` 공식을 사용한다.
- SLO 미달 시 신규 기능보다 안정화 작업을 우선한다.
- 분기마다 SLO 타당성을 비즈니스와 재검토한다.

## Alert Routing and On-call
- `Alertmanager` 라우팅 키는 `severity`, `service`, `team`을 사용한다.
- 동일 원인 경보는 `group_by`로 묶어 페이지 폭탄을 방지한다.
- `inhibit_rules`로 상위 장애 시 하위 경보를 억제한다.
- `PagerDuty` 또는 `Opsgenie` 에스컬레이션 정책을 명확히 둔다.
- 경보마다 `runbook`, `dashboard`, `owner` 링크를 필수화한다.
- false positive 비율을 월별로 측정해 튜닝한다.

## RED and USE Methods
- `RED method`는 `Rate`, `Errors`, `Duration`을 서비스별로 본다.
- `USE method`는 `Utilization`, `Saturation`, `Errors`를 인프라에 적용한다.
- API 게이트웨이, 워커, DB 각각에 RED/USE 패널을 분리한다.
- 지표 이상 징후를 `deployment marker`와 함께 해석한다.
- 지표 사일로를 피하려면 로그/트레이스 링크를 동반한다.
- 서비스 카탈로그에 각 지표 소유권을 지정한다.

## 안티패턴
- ❌ CPU 80% 단일 임계치로 모든 경보를 처리한다.
- ✅ 서비스 SLI 기반 알림과 인프라 보조 경보를 분리한다.
- ❌ 라벨 cardinality를 무제한으로 늘린다.
- ✅ 고카디널리티 필드는 로그/트레이스로 이동한다.
- ❌ runbook 없는 경보를 온콜에 연결한다.
- ✅ 모든 페이지 경보에 실행 절차와 소유자를 연결한다.
- ❌ 샘플링 없이 모든 trace를 영구 저장한다.
- ✅ 비용/가치 기준으로 tail sampling 정책을 운영한다.
- ❌ 대시보드를 UI에서만 수동 편집한다.
- ✅ `dashboard as code`와 PR 리뷰로 변경 이력을 관리한다.
