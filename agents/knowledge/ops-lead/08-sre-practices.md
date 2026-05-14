# SRE Practices

## SRE Core Principles
- `automation-first` 원칙으로 반복 수작업을 시스템화한다.
- 신뢰성 목표는 `SLO` 계약으로 제품과 합의한다.
- 운영 부채는 기능 부채와 동일한 우선순위로 관리한다.
- 운영 이벤트는 모두 학습 자산으로 기록한다.
- `error budget`을 속도와 안정성 균형 장치로 사용한다.
- 팀 경계보다 서비스 책임 경계를 우선 정의한다.

### Toil Definition
- `toil`은 반복적, 수동적, 자동화 가능, 장기 가치 낮은 작업이다.
- 주간 toil 비율을 측정해 50% 초과를 경고 신호로 본다.
- toil 항목은 `runbook automation` 후보로 우선 정렬한다.
- 동일 알림 반복 대응은 자동 복구 후보로 분류한다.
- toil 절감 목표를 분기 OKR에 반영한다.
- toil 측정 기준을 팀 간 동일하게 유지한다.

## Error Budgets
- `availability SLO`에서 허용 실패량을 error budget으로 계산한다.
- budget 소진 속도(`burn rate`)가 높으면 배포 속도를 낮춘다.
- budget 건강 시 기능 릴리즈 속도를 높여 학습 속도를 확보한다.
- `multi-window burn alerts`로 단기/장기 이상을 동시에 감지한다.
- budget 정책 위반 시 change freeze 기준을 명시한다.
- 경영진 보고에는 budget 추세와 제품 영향도를 함께 제시한다.

## Capacity Planning
- 용량 계획은 `CPU`, `Memory`, `IO`, `QPS` 예측을 함께 본다.
- 성장률 예측은 `p50/p95` 트래픽 시나리오로 분리한다.
- `headroom` 목표를 서비스 중요도별로 설정한다.
- 정기 `load test`로 모델 오차를 보정한다.
- 스케일 한계는 `bottleneck` 계층별로 명시한다.
- 비용과 신뢰성 트레이드오프를 문서화한다.

### Capacity Commands
- `kubectl top node`로 노드 압박 상태를 확인한다.
- `kubectl describe hpa <name>`로 스케일 이벤트를 분석한다.
- `vegeta attack` 또는 `k6 run`으로 부하 테스트를 수행한다.
- `promql`로 `predict_linear` 예측 쿼리를 사용한다.
- `aws cloudwatch get-metric-data`로 클라우드 지표를 교차 검증한다.
- 용량 가정과 실제치 차이를 분기별 회고한다.

## Observability vs Monitoring
- `monitoring`은 알려진 문제 탐지, `observability`는 미지 문제 탐구다.
- 메트릭, 로그, 트레이스를 `correlation id`로 연결한다.
- `high-cardinality` 데이터는 탐구 목적에서 전략적으로 사용한다.
- 도메인 이벤트를 기술 지표와 함께 수집한다.
- 관측성 품질은 디버깅 시간 단축으로 측정한다.
- 배포 파이프라인에 관측성 검증 단계를 포함한다.

## On-call Engineering
- 온콜 로테이션은 `follow-the-sun` 또는 주간 교대로 설계한다.
- 온콜 시작 전 `handover checklist`를 실행한다.
- 페이지 응답 목표(`MTTA`)를 명시하고 자동 측정한다.
- 페이지 기준은 고객 영향 중심으로 엄격히 제한한다.
- 경보 피로는 `noise audit`로 주기 제거한다.
- 온콜 후 회복 시간과 보상 정책을 명확히 둔다.

### On-call Tooling
- `PagerDuty` 스케줄과 에스컬레이션 체인을 정기 검토한다.
- `Opsgenie` 통합으로 챗옵스 ack/resolve를 자동화한다.
- `Slack bot`으로 runbook 링크와 명령 템플릿을 제공한다.
- 모바일 환경에서 핵심 대시보드 접근성을 최적화한다.
- 심야 변경은 자동화된 승인 게이트를 추가한다.
- 온콜 메트릭 리포트를 월간 공유한다.

## Runbook Automation
- 수동 runbook 단계는 `script` 또는 `ChatOps` 명령으로 치환한다.
- `kubectl`, `helm`, `terraform` 명령은 파라미터 검증을 넣는다.
- 자동 복구는 `safe guardrail`과 취소 절차를 포함한다.
- 실패 시 사람이介入할 기준점을 명확히 둔다.
- 자동화 실행 로그를 감사 가능하게 저장한다.
- runbook 버전과 코드 버전을 함께 추적한다.

## Chaos Engineering and Game Days
- `Chaos Monkey`, `Litmus`, `Gremlin`으로 장애 주입 실험을 수행한다.
- 실험은 가설, 중단 조건, 복구 계획을 사전 정의한다.
- 프로덕션 실험은 error budget 상태가 양호할 때만 실행한다.
- 네트워크 지연, 패킷 손실, 노드 종료 시나리오를 포함한다.
- `game day`는 운영/개발/제품이 함께 참여한다.
- 결과는 취약점 백로그로 전환해 추적한다.

### Chaos Safety
- blast radius를 namespace, AZ, 트래픽 비율로 제한한다.
- 실험 중 `abort switch`를 항상 활성화한다.
- 고객 영향 임계치 초과 시 즉시 중단한다.
- 실험 후 SLO 회복 시간을 반드시 측정한다.
- 반복 가능한 실험 템플릿을 저장소에 버전관리한다.
- 카오스 결과를 분기 신뢰성 계획에 반영한다.

## DORA Metrics Operations
- `deployment frequency`는 서비스별 릴리즈 빈도로 측정한다.
- `lead time for changes`는 커밋부터 배포까지 시간을 계산한다.
- `change failure rate`는 배포 후 장애/롤백 비율을 본다.
- `MTTR`은 사용자 영향 종료 기준으로 표준화한다.
- DORA 지표는 숫자보다 개선 추세와 맥락을 같이 본다.
- 지표 악화 시 원인 분석 액션을 자동 티켓화한다.

## Reliability Reviews
- 분기마다 `reliability review`를 열어 상위 리스크를 갱신한다.
- 서비스 카탈로그에 `SLO owner`와 `runbook owner`를 명시한다.
- major incident 재발 항목의 완료율을 추적한다.
- 위험 수용(`risk acceptance`) 항목은 만료일을 둔다.
- 관측성 갭은 아키텍처 변경 전 우선 해소한다.
- 리뷰 결과를 다음 분기 roadmap에 반영한다.

## 안티패턴
- ❌ 온콜이 영웅주의로 문제를 개인 역량에 의존한다.
- ✅ 절차, 자동화, 문서로 팀 역량을 시스템화한다.
- ❌ 에러 버짓을 보고만 하고 릴리즈 정책에 반영하지 않는다.
- ✅ budget 소진 규칙을 배포 게이트와 연동한다.
- ❌ 카오스 실험을 이벤트성 데모로만 진행한다.
- ✅ 가설 기반 반복 실험과 후속 개선을 루프로 운영한다.
- ❌ DORA 지표를 팀 비교 랭킹으로 사용한다.
- ✅ 서비스 맥락별 개선 도구로만 사용한다.
- ❌ toil을 개인 성실성 문제로 본다.
- ✅ toil을 자동화 투자 신호로 정량 관리한다.
