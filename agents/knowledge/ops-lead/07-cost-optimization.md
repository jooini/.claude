# Cost Optimization

## Cost Visibility Fundamentals
- 비용 최적화의 시작은 `tagging`, `allocation`, `ownership` 정렬이다.
- `AWS Cost Explorer`로 서비스별/계정별 추세를 주간 점검한다.
- `cost anomaly detection`을 켜서 급증 이벤트를 조기 탐지한다.
- `unit economics` 지표(요청당 비용, 고객당 비용)를 함께 본다.
- 공통 태그는 `Environment`, `Service`, `Owner`, `CostCenter`를 강제한다.
- 미태깅 리소스는 자동 격리 또는 삭제 후보로 분류한다.

### Reporting Patterns
- 월간 총액보다 `day-over-day` 변화율을 우선 감시한다.
- `amortized cost`와 `unblended cost`를 구분해 해석한다.
- 예약형 할인 반영 여부를 별도 차트로 분리한다.
- 공유 비용은 명확한 배분 규칙으로 팀에 청구한다.
- 비용 리포트는 `QuickSight` 또는 `Grafana`로 자동화한다.
- 경영 리포트와 엔지니어 리포트의 상세도를 분리한다.

## Savings Plans and Reserved Capacity
- `Compute Savings Plans`는 EC2, Fargate, Lambda에 폭넓게 적용된다.
- `EC2 Instance Savings Plans`는 특정 패밀리 집중 사용에 유리하다.
- `Reserved Instances`는 고정 워크로드에서 높은 할인율을 제공한다.
- `Convertible RI`와 `Standard RI`의 유연성/할인율 트레이드오프를 평가한다.
- 1년/3년 계약은 예측 정확도와 현금흐름을 함께 고려한다.
- `coverage`와 `utilization` 지표를 월별로 점검한다.

### Reserved Capacity vs Compute Savings Plans
- `Reserved Capacity`는 서비스 고정성이 높고 할인 예측이 쉽다.
- `Compute Savings Plans`는 워크로드 이동이 잦을 때 유연성이 높다.
- 혼합 전략으로 baseline은 RI, 변동분은 Savings Plans로 설계한다.
- 만기 캘린더를 운영해 공백 기간 과금 급증을 방지한다.
- 실사용 추세가 바뀌면 조기 재계약보다 포트폴리오 조정을 우선한다.
- 구매 승인 기준에 `payback period`를 포함한다.

## Spot and Preemptible Strategy
- `Spot Instances`는 stateless, batch, CI 워크로드에 우선 적용한다.
- interruption handling은 `termination notice` 기반으로 자동화한다.
- `mixed instances policy`로 가용성 위험을 분산한다.
- 핵심 경로에는 on-demand fallback capacity를 유지한다.
- `Karpenter` 또는 `Cluster Autoscaler`에서 spot 비율을 조정한다.
- 장애 민감 서비스는 spot 비중 상한을 명시한다.

## Right-Sizing
- `CPU`, `Memory`, `IOPS` 사용률 기반으로 인스턴스 크기를 조정한다.
- 과대 프로비저닝 탐지는 95퍼센타일 사용량을 기준으로 판단한다.
- `AWS Compute Optimizer` 권고안을 검토하되 맹신하지 않는다.
- 부하 패턴이 계절성일 경우 스케줄 기반 스케일링을 사용한다.
- DB는 `RDS Performance Insights`와 연결해 튜닝 우선순위를 정한다.
- rightsizing 변경은 canary 방식으로 단계 적용한다.

### Kubernetes Cost Controls
- `requests/limits` 미설정 파드를 금지해 낭비를 줄인다.
- `Kubecost`로 namespace/label 단위 비용을 시각화한다.
- `OpenCost` API로 비용 데이터를 내부 대시보드에 통합한다.
- `VPA` 권고를 수용하되 급격한 변경은 점진 적용한다.
- `HPA` 최소/최대값을 업무시간 패턴에 맞게 튜닝한다.
- 노드 풀 분리로 고비용 워크로드를 격리한다.

## Storage and Data Transfer Costs
- `S3 Intelligent-Tiering`으로 접근 패턴 변동 비용을 최적화한다.
- 오래된 로그는 `Glacier` 또는 `Deep Archive`로 수명주기 이동한다.
- 미사용 `EBS volume`, `EIP`, `snapshot` 정리를 자동화한다.
- 리전 간 전송 비용은 아키텍처 단계에서 최소화한다.
- `CloudFront` 캐싱으로 egress 비용과 지연을 동시에 줄인다.
- DB 백업 보존기간은 규정과 비용을 함께 고려해 조정한다.

## Idle Resource Detection
- 야간/주말 유휴 환경은 `scheduler`로 자동 종료한다.
- 개발 환경은 `ttl tag` 만료 후 자동 삭제 정책을 둔다.
- 미연결 `load balancer`와 orphan 리소스를 주기 점검한다.
- 장기 idle 인스턴스는 owner 확인 후 다운사이징한다.
- `Lambda` 미호출 함수와 오래된 버전을 정리한다.
- 유휴 탐지 결과를 티켓으로 자동 생성해 추적한다.

## FinOps Operating Model
- `FinOps`는 엔지니어, 재무, 제품이 공동 책임을 가진다.
- 예산 대비 실적을 주간 단위로 검토한다.
- 신규 아키텍처 제안에는 예상 비용 모델을 포함한다.
- `showback` 또는 `chargeback` 체계를 팀 성숙도에 맞게 도입한다.
- 절감 KPI는 성능/신뢰성 KPI와 균형 있게 관리한다.
- 비용 리뷰는 blame이 아니라 학습 중심으로 운영한다.

## Governance and Policy
- `SCP`와 `IAM policy`로 고비용 리소스 생성을 제한한다.
- 기본 리전 제한으로 분산된 유령 자원 생성을 막는다.
- 실험 계정은 spending limit 알람을 낮게 설정한다.
- `budget action`으로 임계 초과 시 자동 차단을 설정한다.
- 구매형 할인 상품은 승인 워크플로우를 표준화한다.
- 비용 태그 누락 리소스는 배포 차단 정책을 적용한다.

## 안티패턴
- ❌ 월말에만 총액을 보고 사후 대응한다.
- ✅ 일별 추세와 anomaly 탐지로 선제 대응한다.
- ❌ 무조건 spot으로 전환해 안정성을 희생한다.
- ✅ 중요도 기반으로 spot/on-demand 혼합 정책을 사용한다.
- ❌ 태그 정책 없이 비용 귀속을 수작업으로 처리한다.
- ✅ 배포 단계에서 태그 필수 검증을 자동화한다.
- ❌ 할인 상품을 한 번 구매하고 방치한다.
- ✅ `coverage/utilization` 지표로 포트폴리오를 주기 재조정한다.
- ❌ 쿠버네티스 requests 과다 설정을 성능 안전장치로만 본다.
- ✅ 실제 사용량 기반 rightsizing으로 낭비를 줄인다.
