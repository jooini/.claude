# 이력서 작성 21원칙

개발자 이력서를 Claude로 작성할 때 사전 체크리스트. 4개 Part 구성:

- **Part 1. 기본 형식 8개** — Claude raw 출력의 약점 잡기
- **Part 2. 시니어 시그널 6개** — EM이 첫 30초에 보는 것
- **Part 3. AI 시대 4개** — 2025~2026 채용 시프트 반영
- **Part 4. 한국 시장 3개** — 글로벌 가이드가 못 잡는 한국 특수성

> 본 문서의 모든 구체 예시는 **가상 시나리오**입니다. 실제 적용 시 사용자의 실제 경력에서 추출한 사례로 대체합니다.

---

## Part 1. 기본 형식 (Form) — 1~8

### 1. Competency 헤더는 비개발자도 이해되는 평문으로

- ❌ "Submodule → AAR 전환 의사결정 경험"
- ❌ "Hexagonal Architecture 도입을 통한 도메인 격리 경험"
- ✅ "프로덕트 코드와 연구 코드의 **경계를 분리**한 경험"
- ✅ "**구독 해제를 깜빡해도 메모리 릭이 나지 않는** 구조로 전환한 경험"
- ✅ "**결제 실패가 다른 도메인으로 번지지 않도록** 경계를 설계한 경험"

**Why:** Competency 헤더는 채용 담당자(개발자 아닐 수 있음)와 HR이 가장 먼저 본다. 기술 약어로 시작하면 "이게 무슨 말이지" 단계에서 막힘.
**How:** "이걸 사용자/팀이 봤을 때 뭐가 좋아지는가"를 한 문장 평문으로. 기술 스택 이름은 본문에 둠.

### 2. 수치는 굵은 1~2개만. 폭주 금지

- ❌ "코어 모듈 633줄·서브 모듈 678줄 ... 합 1,311 → 968줄(26% 감소), 모듈별 81%/80% 감소" (한 줄에 5개 이상)
- ✅ "중복 코드 80%를 공통 계층으로 추출"
- ✅ "테스트 0개 → 549개"
- ✅ "p99 지연 1.2s → 280ms"

**Why:** 수치 5개가 동시에 박히면 신뢰도가 떨어짐. 검증 가능한 강한 수치 하나 > 검증 안 되는 다섯.
**How:** bullet 하나에 수치 최대 2개. **이전 vs 이후(0 → 549)** 또는 **퍼센트(80%)** 형태가 강함.

### 3. 코드 백틱·내부 클래스명·제네릭·어노테이션 금지

- ❌ `BaseRepositoryImpl<T extends BaseEntity, ID extends Serializable>`
- ❌ `@InternalApi`, `@RestrictTo(LIBRARY_GROUP)`
- ✅ "공통 베이스 클래스로 모듈별 중복 제거" (제네릭 시그너처는 평문화)
- ✅ "공개 API 표면을 100+ 클래스에 걸쳐 internal로 축소" (어노테이션 이름은 평문)

**Why:** 내부 식별자는 외부에서 검증 불가. 제네릭 시그너처는 "이 사람은 자기 코드 안에 갇혀 있다" 시그널.
**How:** 기술 스택명(Flow, CameraX, Spring Boot, Kafka)은 OK. 내부 클래스명·제네릭·어노테이션은 평문/패턴 설명으로 대체.

### 4. Bullet 4~5개 한계. 10개는 안 읽힌다

**Why:** 채용 담당자가 한 이력서에 쓰는 시간은 6초~30초. bullet 10개 = 위 3개만 읽힘. 길이 ≠ 깊이.
**How:** 한 프로젝트당 bullet 4~5개 상한. 넘어가면 묶거나 별 프로젝트로 분리.

### 5. 본인 시그너처 어휘 + Ownership 동사 화이트리스트

본인이 일하는 방식을 정의하는 **동사 3~5개**를 정해 본문 전체에 흐르게.

**Ownership 동사 화이트리스트** (시니어 시그널):
- ✅ **owned / drove decision on / defined / arbitrated / unblocked / shipped**
- ❌ **led / responsible for / helped / assisted / worked on / leveraged / utilized**

**Why:** "led/helped" 같은 약한 동사는 의미가 닳음. EM이 즉시 "junior" 라벨. 시니어 시그너처 어휘는 동사 단위에서 시작.
**How:** Summary부터 Experience 본문까지 본인 시그너처 동사를 흘리되, 위 화이트리스트로 자동 치환. ("led migration" → "owned migration end-to-end") 어휘 자랑하듯 나열 X.

#### 한↔영 시그너처 어휘 매핑

사용자가 한국어 시그너처 동사를 주면 영문 이력서엔 다음 매핑으로 변환. **같은 한국어 동사가 문장마다 다른 영어로 번역되어도 OK** — 맥락별로 가장 자연스러운 영어 선택.

| 한국어 시그너처 | 영문 equivalents (맥락별) |
|---|---|
| 분리한다 | separate / decouple / isolate / split |
| 회수한다 | reclaim / unblock / reduce friction / free up |
| 통일한다 | consolidate / unify / standardize |
| 자산화한다 | codify / formalize / institutionalize |
| 흐름으로 본다 | model as a pipeline / flow-oriented design |
| 경계를 짓는다 | encapsulate / define boundary / set interface |
| 자동화한다 | automate / orchestrate / streamline |
| 운영한다 | operate / steward / run |
| 추출한다 | extract / surface / pull out |
| 정렬한다 | align / standardize / normalize |

영문 이력서일 때 사용자에게 시그너처 동사를 영어로 받아도 OK. 한국어로 받았으면 위 표 기준으로 변환.

### 6. Competency 4개는 서로 다른 4축 + Development 시그널 1개

- ❌ Competency 4개 = 모두 같은 강점의 변주 (강점 하나를 4번 쪼갬)
- ✅ Competency 4개 = 아키텍처 분리 / 실시간 성능 / 안정성 / **남을 키운 흔적**

**Why:** 같은 강점 4번 = 깊이가 아니라 폭의 부재. 시니어 이상이면 "Development(남을 키운 흔적)" 1개는 필수 — Charity Majors가 말하는 E5↑ 차별점.
**How:** Competency 4축 중 1축은 반드시 **사람 키우기/문화 도입/온보딩 자동화** 같은 development 시그널. ("주니어 4명 온보딩 → 2명이 서브시스템 오너 인수")

### 7. 포지션마다 헤드라인 + 경력 자체를 갈아끼움

| 타겟 | 헤드라인 예시 | 경력 표시 |
|---|---|---|
| 제너럴/풀스택 | "Software Engineer" | 모든 경력 + 다양성 |
| 도메인 특화 (예: 백엔드 플랫폼) | "Backend Platform Engineer" | 해당 도메인 + Awards 강조 |
| 인프라/SDK | "Infrastructure · SDK Engineer" | 인프라·SDK 관련 + 앱 작업 축소 |

**Why:** 타겟에 안 맞는 경력은 노이즈. 가장 강조하고 싶은 걸 맨 위에 — **위치도 메시지**.
**How:** 포지션 받으면 먼저 1) 헤드라인 2) 포함/제외 경력 3) Awards·Side Project 표시 4) 강조 경력 배치 — 이 4가지를 정한 후 본문. **한 이력서로 모든 포지션 대응 X**.

### 8. 솔직 라벨은 유지 + 실패/학습도 노출

- ✅ "권고사직: 경영 악화" / "B2C / B2B" / "조직 개편으로 팀 해체"
- ✅ "A/B 결과 실패 → 가설 재설계" (Microsoft Growth Mindset, Google "intellectual humility")

**Why:** 솔직함이 신뢰의 무기. 가리려고 애쓴 흔적이 더 의심받음. 실패를 의도적으로 1~2 bullet 노출하면 "know-it-all"이 아니라 "learn-it-all" 시니어 시그널.
**How:** 짧은 근속·권고사직·인수합병 한 줄 솔직. 추가로 "실패한 시도와 학습" 1 bullet 권장. 미화 X, 자기 비방 X.

---

## Part 2. 시니어 시그널 (Senior Signal) — 9~14

빅테크/시니어 EM 리서치에서 일관되게 나오는 6축. 시니어로 인정받는 이력서엔 이 6개가 한 번씩 박혀 있음.

### 9. Scope 카드 1줄 — 시스템 규모를 첫 줄에

각 포지션 첫 줄에 **시스템 규모를 한 줄로 박는다**.

- ✅ "DAU 18M / RPS 4K / 백엔드 12명 팀 / Kotlin·Spring 멀티모듈"
- ✅ "B2C 모바일 앱, 글로벌 20개국 출시, Android·iOS·TV 3 플랫폼"
- ✅ "B2B SaaS, MAU 500K, 데이터 파이프라인 일 50TB"

**Why:** EM이 10초 안에 "이 사람이 다룬 시스템이 우리 회사 규모와 맞나?" 판단. Scope 없으면 "스타트업 토이 프로젝트"로 보임.
**How:** 회사·역할 라인 바로 아래에 사용자 수/RPS/데이터 볼륨/팀 인원/플랫폼 수 중 가장 강한 2~3개 한 줄.

### 10. Trade-off / 포기한 것 한 줄 명시

주요 결정마다 **무엇을 포기했는지** 한 줄.

- ❌ "Improved API latency"
- ✅ "p99 40% 단축 — 결제 외 경로에서 **eventual consistency 수용**(2초 stale)"
- ✅ "Room vs SQLDelight 비교, **빌드타임 30% 우위로 후자 선택**"
- ✅ "gRPC 대신 REST 유지 — 사내 디버깅 도구 호환성을 위해 latency 15% 손해 수용"

**Why:** Will Larson "navigating ambiguity" 핵심 + Google RRK 평가축. 트레이드오프 없는 결정 서술은 "구현자"로 보임. 시니어는 **무엇을 포기했는지로 평가**됨.
**How:** 핵심 의사결정(아키텍처/스택/마이그레이션) bullet엔 "X 대신 Y 선택, 이유는 Z 포기 수용" 패턴.

### 11. Delivery → Outcome → Impact 3층 구조

큰 프로젝트는 한 bullet에 3층을 의도적으로 분리.

- ❌ "Shipped notification service"
- ✅ "Push pipeline 출하 *(delivery)* → DAU 18M 커버 *(outcome)* → growth팀의 re-engagement 실험 unblock *(impact)*"

**Why:** Amazon STAR(-L) + Meta "Long-Term Impact" + 빅테크 공통. **구현 → 지표 → 사업 임팩트** 3단계를 한 사람이 다 보여줄 수 있는지가 시니어 시그널.
**How:** 가장 중요한 프로젝트 1~2개는 3층 구조. 모든 bullet에 강제하면 길어지니 핵심만. "수치 절제(원칙 2)"는 outcome 층에 적용하고, impact 층은 정성적 영향 허용.

### 12. 독립 산출물 / 외부 링크 상단 배치

학력 위에 **블로그/오픈소스/사이드 프로젝트 링크**를 둔다.

- ✅ GitHub: 본인 라이브러리/도구 링크
- ✅ 기술 블로그: 직접 쓴 글 2~3편 링크
- ✅ Side Project: 출시한 앱/도구

**Why:** "I built this, here's the link"가 PhD를 이긴다 (Anthropic 채용 공식). 한국 시장에서도 jojoldu/우아한형제들 후기 공통: 링크 없으면 부풀림 의심.
**How:** Summary 직후 또는 Education 위. 활동이 적다면 차라리 "공개 활동 없음 — 사내 코드 중심" 솔직 표기 (한국 시장 안티-부풀림 시그널).

### 13. ★ Thread Re-narration — 같은 경력, 다른 실로 일관 서사

**가장 강한 시니어 시그널 (커리어 차원).** 같은 경력 풀에서 **타겟 포커스에 맞는 실(thread)을 뽑아 초기부터 최근까지 끊김 없는 한 줄기로 엮는다.**

#### 핵심 패턴: Origin Story 라벨

초기 경력 프로젝트에 **"현재 X의 기반이 된 첫 Y 경험"** 라벨을 명시적으로 박는다.

**가상 예시 — 백엔드 플랫폼 포커스**:
- ✅ 5년 전 "스타트업 PHP REST API"를 "**(현재 결제 플랫폼 운영의 기반이 된 첫 백엔드 경험)**" 으로 라벨
- ✅ "스타트업 PHP API" → "핀테크 Spring Boot 전환" → "결제 모듈 분리" → "MSA 전환" 일관 흐름

**가상 예시 — 모바일 SDK 포커스**:
- ✅ "초기 BLE 라이브러리 사용 앱 (origin)" → "외부 SDK 통합 (SDK 사용자 측)" → "공통 모듈 분리 (모듈화 첫 시도)" → "단독 SDK 운영" 일관 흐름

**가상 예시 — AI Builder/자동화 포커스**:
- ✅ "마케팅 시절 정산 자동화 (origin)" → "주니어 시절 로깅 유틸 통일" → "팀 단위 번역 파이프라인 자동화" → "AI 에이전트 워크플로우" 일관 흐름

#### 같은 프로젝트, 다른 디테일

같은 회사 같은 프로젝트도 포커스에 따라 부각하는 디테일이 달라진다.

**가상 예시 — 한 회사의 한 마이그레이션 프로젝트를 세 포커스로**:

| 포커스 | 부각하는 디테일 |
|---|---|
| Backend Platform | "결제 모듈 모놀리식 → MSA 4개 서비스, Kafka 이벤트 라우팅, p99 250ms → 80ms" |
| Reliability/SRE | "99.5% → 99.95% SLO, 인시던트 RCA 6건, 평균 회복 시간 12분 → 3분" |
| AI Builder | "Claude Code로 마이그레이션 8주 → 3주, 테스트 커버리지 95% 유지, 롤백 0건" |

같은 프로젝트지만 **포커스에 맞는 단편만** 부각.

**Why:** 단순 경력 나열 vs 일관 서사의 차이가 정확히 여기서 갈림. EM에게 "이 사람은 커리어를 의도적으로 쌓아왔다" 시그널. 본인 커리어를 한 줄기로 정리할 수 있는 능력 자체가 시니어 시그널.

**How:**
1. 자료에서 모든 회사·프로젝트를 시간순 나열
2. 각 프로젝트에서 타겟 포커스와 관련된 **단편(snippet)** 만 추출
3. 단편들이 **하나의 강점이 점점 깊어지는 흐름**으로 읽히는지 검증
4. 초기 경력은 **origin story 라벨** 명시 — "(현재 X의 기반이 된 첫 Y 경험)"

### 14. ★ Problem Framing — 문제 정의 + 가설 + 검증

**가장 강한 시니어 시그널 (사고 과정 차원).** #13이 "본인 커리어를 어떻게 보는가"라면, #14는 **"본인이 문제를 어떻게 보는가"**.

결정에 도달하기 전 단계 — **모호한 문제를 어떻게 정의했고, 어떤 가설을 세웠으며, 어떻게 검증했는지**. 시니어 새 정의 = "어떻게 그 답에 도달했는가".

#### 4가지 sub-pattern

**Pattern 1. 문제 재정의 (Reframe)** — 모호한 표현을 측정 가능한 정의로 좁힘
- ❌ "성능 개선"
- ✅ "**'느리다'를 'p99 800ms 스파이크 주 3회'로 재정의** → 진짜 병목 식별"

**Pattern 2. 본질 추궁 (Dive Deep)** — 표면 증상이 아닌 구조적 원인 추적
- ❌ "메모리 릭 수정"
- ✅ "메모리 릭이 단일 버그가 아니라 **콜백·리스너·이벤트버스 3가지 혼재 패턴의 구조적 문제**임을 식별 → 단일 구조로 통일하여 재발 0건"

**Pattern 3. 가설-검증 사이클** — 모든 결정에 측정 가능한 검증 흔적
- ❌ "캐시 도입으로 개선"
- ✅ "캐시 도입 — **가설**: 읽기 쏠림 80% / **검증**: 트래픽 샘플링 89% / **결과**: 평균 응답 220ms → 30ms"

**Pattern 4. 모호함 명세화 (Spec under Ambiguity)** — "이걸 원한다"를 "이것이 성공이다"로 변환
- ❌ "사용자 피드백 반영"
- ✅ "**'검색이 답답하다' 피드백을 '결과 첫 화면 ≤ 1초 SLO'로 명세화** → 이해관계자 3팀 합의 후 착수"

#### 통합 예시
모든 pattern을 합친 한 줄:
> "**'느리다'를 'p99 800ms 스파이크 주 3회'로 재정의** *(Reframe)* → DB 풀 고갈 가설 → APM 트레이스로 89% 확인 *(검증)* → 커넥션 풀 비대칭 수정으로 40% 단축 *(결과)*"

**Why:** Amazon Dive Deep / Google GCA / Larson navigating-ambiguity 모두 강조. EM이 시니어 검증할 때 "어떻게 그 답에 도달했는가"를 가장 깊이 본다. 이게 없으면 "운 좋게 답 찾은 사람"으로 읽힘.

**How:** 핵심 프로젝트 1~2개에 적용 (#11 3층 구조와 마찬가지로 모든 bullet 강제 X). 4 pattern 중 적어도 1개는 명시. **#10 Trade-off가 "포기한 것"이면 #14는 "그 결정에 어떻게 도달했나"** — 짝이 되는 두 원칙.

**Anti-pattern:**
- 가설 없이 결과만 나열 ("X를 했고 Y가 좋아졌다") — "운 좋게 답 찾은 사람"
- 검증 방법 부재 ("개선했다"만 있고 "어떻게 측정했는가" 없음)
- 모호한 요구를 그대로 받아 그대로 구현한 흔적 — "수동적 구현자" 시그널

---

## Part 3. AI 시대 (2025~2026) — 15~18

채용 시장의 메타 시그널이 바뀌었다. "AI를 쓰는 사람"이 아니라 **"AI 출력을 신뢰할/검증할/거부할 시점을 아는 사람"** 으로.

### 15. AI는 "도구"가 아니라 "워크플로우"로 보여줘라

- ❌ "Tools: Cursor, Claude Code, Copilot" (도구 나열)
- ❌ "AI에 관심 있음 / passionate about AI"
- ✅ "**Claude Code 에이전트를 지휘(directed)** API 통합 시간 3일 → 4시간 단축, 47개 endpoint에 95% 테스트 커버리지 유지"

**Why:** 2026년 ATS 62%가 "passionate/leveraged/utilized/cutting-edge" 같은 표현을 자동 감점. 도구만 적으면 "써본 사람"이지 "지휘하는 사람"이 아님.
**How:** 한 역할당 최소 1 bullet은 AI-assisted 임팩트. **"[정량 결과] by [AI 도구] + [에이전트가 한 일] + [내가 직접 한 판단/검증]"** 공식.

### 16. Speed × Quality 페어링 — 속도 수치 옆에 품질 지표

- ❌ "AI로 개발 속도 3배" (검증 부재로 reject)
- ✅ "Claude Code로 14 서비스 마이그레이션 8주 → 3주, **테스트 커버리지 95% 유지 + 롤백 0건**"

**Why:** AI 속도만 적으면 "검증 안 한 사람"으로 즉시 reject. **속도는 반드시 품질과 페어**.
**How:** AI-assisted bullet엔 무조건 품질 지표(테스트 커버리지/보안 취약점 수/롤백 수/장애 수) 한 쌍.

### 17. Judgment Layer 명시 — AI가 못 하는 결정 따로 표시

- ✅ "Claude Code로 서비스 레이어 scaffold, **수동 보안 리뷰 + 아키텍처 검증** 후 머지 — 무롤백 출시"
- ✅ "Eval framework 직접 설계 후 RAG 파이프라인 구축, **hallucination 40% 감소를 프로덕션 트래픽에서 검증**"

**Why:** "Taste is the new bottleneck" 시대. **실행은 싸지고 판단이 병목**. 시니어 새 정의 = 모호함을 실행 가능한 스펙으로 변환 + 비가역적 결정을 불완전한 정보로 내림.
**How:** AI-assisted 작업 뒤엔 항상 "내가 직접 한 판단" 1줄 — eval 설계 / 보안 리뷰 / 아키텍처 검증 / 수락 기준 정의 / observability 설계 중 최소 1개.

### 18. 진정성 디테일 — AI 탐지 회피 = 거친 디테일

- ❌ "Leveraged cutting-edge AI to seamlessly integrate..." (균일한 buzzword)
- ✅ "Anthropic SDK 0.21.0에서 stream API 버그로 막혀 3시간 디버깅 — issue tracker에 reproducible case 등록 후 우회"

**Why:** AI가 쓴 이력서 62% 자동 reject (GPTZero 2026). **다듬어지지 않은 구체 디테일**이 진정성 시그널.
**How:** bullet 중 1~2개는 의도적으로 거친 디테일 — 특정 버그, 특정 버전, 특정 시간, 특정 사람과의 협업 — 균일한 buzzword 문장은 피함.

---

## Part 4. 한국 시장 특수성 — 19~21

글로벌 가이드가 못 잡는 한국 채용 시장 특수 항목. **한국 기업 지원 시에만 적용**.

### 19. 포맷 / 분량 — PDF + 이력서 2장 + 경력기술서 2장

- **PDF 필수**, 한글(HWP)/Word 금지 (macOS 호환·사내 ATS 문제)
- **이력서 2장 + 경력기술서 2장 내외** — 영문 1-page rule 그대로 적용 X
- Notion → PDF export 워크플로 권장

**Why:** 토스·당근·우아한형제들 모두 PDF 권장. 점핏·원티드 표준. 한국 채용은 이력서(요약)와 경력기술서(상세) 분리 문화.
**How:** 첫 2장에 핵심(Summary + Competency + 최근 2~3개 경력), 뒤 2장에 상세 경력. 단일 1-page resume는 한국 시장에선 빈약해 보임.

### 20. 직책 이중 표기 — 공식 직급 + 수행 역할 분리

- ❌ "Senior Tech Lead" (단독 자칭) — 한국 시장 직책 인플레이션 의심
- ✅ "Backend Engineer (Tech Lead 역할 겸직, 결제 모듈 Owner, 팀 4명)"
- ✅ "Android Developer (개발팀 운영, 5명 팀 리드)"

**Why:** 한국은 연공서열·짬수 문화 잔존. 외국계/스타트업 직책을 그대로 옮기면 "직책 인플레이션"으로 의심. "연차 ≠ 시니어" 공식.
**How:** 회사 공식 직급 + 수행 역할/팀 규모/기간/범위를 분리 기재. 검증 가능하게.

### 21. 공백 라벨 + 컬처핏 시그널 레이어

**공백 라벨 (한국형)**:
- ✅ "권고사직: 경영 악화" / "조직 개편으로 팀 해체" / "육아휴직 8개월"
- ✅ "8개월 학습 공백 — 오픈소스 기여 + 사이드 프로젝트 출시"

**컬처핏 시그널 레이어**:
- ✅ "주도적으로 코드리뷰 문화 도입, PR 평균 리뷰 2.3건/주"
- ✅ "신규 입사자 온보딩 자동화 도구 제작, 4명 적용"
- ✅ "결제 도메인 4년 — 정산/환불 모듈 일관 오너십"

**Why:** 한국 빅테크(토스·당근·인프랩)는 컬처핏을 별도 라운드로 평가. 이력서 단계부터 "팀 핏"이 보여야 함. 공백 1년 미만 반복은 강한 레드플래그 — 미리 라벨링하면 통과율↑.
**How:** 공백/짧은 근속엔 사유 한 줄 라벨. 별도로 "협업/도메인 깊이/오너십" 시그널을 bullet 1~2개에 명시 — 한국식 어휘로 "주도/리드/책임감/꾸준함" 자연스럽게.

---

## 우선순위 가이드

21원칙을 한 번에 적용하기 어려우면 다음 순서로:

1. **반드시 (모든 이력서)**: #1, #2, #3, #4, #7, #8, #13 — 기본 형식 + Thread Re-narration
2. **시니어 지원 시**: + #5, #6, #9, #10, #11, #12, **#14** — Senior Signal 풀세트
3. **AI 활용 사례 있으면**: + #15, #16, #17, #18 — AI 시대 항목
4. **한국 기업 지원 시**: + #19, #20, #21 — 한국 시장 항목

**#13 (Thread Re-narration)과 #14 (Problem Framing)이 가장 자주 누락되는 시니어 시그널의 두 축.** 단순 경력 나열 vs 일관 서사 (#13) + 단순 결과 나열 vs 사고 과정 (#14) — 이 두 축이 시니어 검증의 진짜 척추.

---

## 출처

**빅테크 인재상**
- [Amazon Leadership Principles](https://www.amazon.jobs/content/en/our-workplace/leadership-principles) (특히 Dive Deep — #14 근거)
- [Google How We Hire](https://www.google.com/about/careers/applications/how-we-hire/) (GCA — #14 근거)
- [Meta Culture](https://www.metacareers.com/culture)
- [Netflix Culture Memo](https://jobs.netflix.com/culture)
- [Microsoft Growth Mindset — Fortune](https://fortune.com/2024/05/20/satya-nadella-microsoft-culture-growth-mindset-learn-it-alls-know-it-alls/)

**시니어/EM 검수**
- [The Pragmatic Engineer Resume — Orosz](https://blog.pragmaticengineer.com/resume/)
- [lethain: Staff-plus interview](https://lethain.com/staff-plus-interview-process/) (navigating ambiguity — #14 근거)
- [charity.wtf: engineering levels](https://charity.wtf/2020/09/14/useful-things-to-know-about-engineering-levels/)

**AI 시대**
- [Pragmatic Engineer — State of Job Market 2026](https://newsletter.pragmaticengineer.com/p/state-of-the-job-market-2026)
- [Anthropic Careers](https://www.anthropic.com/careers)
- [Designative — Taste Is the New Bottleneck](https://www.designative.info/2026/02/01/taste-is-the-new-bottleneck-design-strategy-and-judgment-in-the-age-of-agents-and-vibe-coding/)

**한국 시장**
- [우아한형제들 — 신입 개발자 이력서](https://techblog.woowahan.com/11998/) / [시니어 개발자란](https://techblog.woowahan.com/2525/)
- [jojoldu/junior-recruit-scheduler](https://github.com/jojoldu/junior-recruit-scheduler)
- [원티드 — 서류 통과 이력서](https://www.wanted.co.kr/events/article_23_01_06)
