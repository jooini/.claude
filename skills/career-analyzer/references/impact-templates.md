# impact-templates

Activity (커밋·파일·PR) → Outcome (비즈니스·시스템 영향) 변환 템플릿.

## 왜 필요한가

Collector가 주는 raw는 **Activity**. 이력서/리뷰에 쓰이는 건 **Outcome**.
직접 연결되는 수치가 Collector에 없을 때 사용자 자가 보고로 보완.

## 템플릿

### SSO / 인증

| Activity 시그널 | 질문할 Outcome |
|---|---|
| identity-hub* 그룹 commits 20+ | 영향 서비스 수? 로그인 세션 수? 장애 감소? |
| SPI 추가/수정 | 어떤 인증 흐름 지원? 제거된 레거시? |
| refactor 비중 40%+ | 제거된 deprecated API 수? 신규 클라이언트 수? |

### 프론트엔드

| Activity | Outcome 질문 |
|---|---|
| identity-hub-frontend 대형 변경 | 페이지 로드 시간? Accessibility 점수? |
| next 버전 bump | 이전 버전 EOL 대응? 성능 지표? |
| `feat` 커밋 다수 | 노출된 사용자 수? 전환율? |

### 백엔드 (Kotlin/Spring, FastAPI)

| Activity | Outcome |
|---|---|
| maxai-* 새 엔드포인트 추가 | 일 호출량? p99 지연? |
| DB 마이그레이션 커밋 | 데이터 크기? 다운타임? |
| 테스트 파일 추가 | 커버리지 변화? CI 시간? |

### 인프라

| Activity | Outcome |
|---|---|
| CI 파일 변경 | 빌드 시간 단축? 실패율? |
| docker/terraform 변경 | 배포 빈도 증가? 다운타임? |
| 의존성 업데이트 | CVE 해결? |

## 변환 절차

1. Collector portrait §9에서 그룹별 볼륨 확인
2. 위 템플릿에서 해당 그룹 질문 추출
3. 사용자에게 Outcome 질문 (수치 or 정성 답변)
4. 사용자 답변을 bullet로 편성
5. 답변 없으면 Activity만 남기고 Outcome 생략 (지어내지 말 것)

## 예시 프롬프트

```
Analyzer: identity-hub-frontend 그룹에서 15건 커밋, +6286/-726 라인 관찰되었습니다 (source: portrait §9).
다음 중 해당 기간 Outcome 데이터가 있으면 알려주세요:
- 페이지 로드 시간 변화 (p50/p95)
- 로그인 성공률 변화
- 사용자 피드백/장애 티켓 수
없으면 "없음" 으로 답해주세요.
```

## 금지

- 임의 수치 생성 ("로그인 성공률 99.9% 추정")
- 업계 평균치로 대체 ("일반적으로 X%")
- Outcome 없을 때 "영향이 컸다" 추상 문구
