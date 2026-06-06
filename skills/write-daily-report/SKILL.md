---
name: write-daily-report
description: claude-mem, 세션 기록, 프로젝트 산출물(Projects/), 전체 Workspace git 커밋을 교차 수집하여 오늘 전체 작업 기반 일일 업무 보고서를 작성합니다. Mattermost 붙여넣기용 변환도 지원(to-mattermost.sh).
disable-model-invocation: true
allowed-tools: Bash(git *), Bash(date *), Bash(ls *), Bash(find *), Bash(~/.claude/skills/write-daily-report/to-mattermost.sh *), Read, Write, Glob, mcp__plugin_claude-mem_mcp-search__timeline, mcp__plugin_claude-mem_mcp-search__search, mcp__plugin_claude-mem_mcp-search__get_observations
---

# write-daily-report

오늘 하루 작업 기반으로 간결한 일일 업무 보고서를 작성한다.

## 핵심 원칙

- **독자는 비개발 보고 대상이다**: 이 보고서를 읽는 사람은 팀장·상급자·타 부서 등 코드를 모르는 사람이다. 개발자만 알아듣는 표현을 쓰면 보고서로서 실패다. **"코드 모르는 사람이 읽어도 무슨 일을 왜 했는지 이해되는가?"가 모든 줄의 합격 기준**
- **HOW 말고 WHAT/WHY**: "어떻게 구현했는지(메커니즘·코드 구조)"가 아니라 "무엇을 해결했고 그래서 무엇이 좋아졌는지(업무 가치)"를 쓴다. 구현 디테일은 세션 기록에 둔다
- **내부 식별자 전면 금지**: 아래는 보고서 본문에 절대 쓰지 않는다 (자세한 목록은 「금지 사항」)
  - SPEC ID (`SPEC-XXX-001`, `B-1`, `METRIC-003` 등), 커밋 해시, 브랜치명
  - 변수/함수/메서드/클래스/파일 경로/컬럼명/DB 식별자 (`failure_category`, `lib/study-status.ts`, `merge_parallel`, `asyncio.Lock` 등)
  - 환경변수 키, 내부 상태값 (`AZURE_SPEECH_KEYS`, `not_applicable` 등)
  - 빌드/테스트 도구·수치 (`tsc`, `vitest 230개`, `lint 0` 등) — "검증 완료"로 충분
- **분량 상한**: 1 프로젝트 = **최대 3줄**, 1줄 = **최대 80자**. 초과 시 잘라내기
- **동사 단문**: 한 줄에 한 동작. "~하고 ~했다" 결합문 금지. "~함" 종결 권장
- **WHY 1개**: 줄마다 결과만. WHY는 프로젝트당 1줄로 묶어서 따로
- **세션 기록 상세 위임**: 보고서는 헤드라인만. 디테일/배경/시도과정은 세션 기록에 둠
- **중복 금지**: frontmatter/파일명에 날짜 있으므로 본문에 날짜 섹션 불필요
- **커밋 해시 금지**: 커밋 해시를 보고서에 포함하지 않는다. git log로 확인 가능
- **브랜치 머지 내역 금지**: "feature/xxx 브랜치 머지 완료" 같은 내용 불필요
- **"상세: 세션 기록 참조" 금지**: 세션 기록 링크는 하단 세션 기록 섹션에만. 본문에서 "세션 기록 참조" 문구 사용 금지
- **자의적 섹션 추가 금지**: "핵심 성과", "생성된 주요 자산", "골든 커맨드", "교훈" 등 템플릿에 없는 섹션 만들지 말 것
- **확인할 게 없으면 섹션 자체 생략**

## 실행 절차

### 1단계: 기존 데이터 확인 (병렬)

```bash
# 오늘 날짜
date +%Y-%m-%d

# 기존 보고서 확인
ls ~/Workspace/weaversbrain/weaversbrain/Daily/$(date +%Y-%m)/$(date +%Y-%m-%d).md 2>/dev/null

# 오늘의 세션 히스토리 (1순위 소스)
ls ~/Workspace/weaversbrain/weaversbrain/Sessions/$(date +%Y-%m)/$(date +%Y-%m-%d)-*.md 2>/dev/null

# 오늘의 프로젝트별 산출물/핸드오프/분석 문서 (Projects/ 전체 스캔)
find ~/Workspace/weaversbrain/weaversbrain/Projects \
  -path "*/$(date +%Y-%m)/$(date +%Y-%m-%d)-*.md" -type f 2>/dev/null

# 최근 보고서 (전날 연속성)
ls -t ~/Workspace/weaversbrain/weaversbrain/Daily/$(date +%Y-%m)/*.md 2>/dev/null | head -3
```

### 2단계: 정보 수집

**우선순위:**

1. **claude-mem timeline** — 전 세션 통합 기록. `mcp__plugin_claude-mem_mcp-search__timeline`으로 오늘 날짜 범위 조회. 필요시 `get_observations`로 상세 내용 확인. **단일 장애점 주의** — MCP 미가동/uvx 누락/인덱싱 지연 시 누락 가능. 1순위지만 유일 근거로 쓰지 않는다.
2. **세션 히스토리 파일** — `Sessions/YYYY-MM/YYYY-MM-DD-*.md`. claude-mem 누락분 교차 확인.
3. **프로젝트별 산출물** — `Projects/{프로젝트}/YYYY-MM/YYYY-MM-DD-HHMM-*.md`. 핸드오프, 분석, 스펙, metric dictionary, misc 비코드 작업(택시비/경비 정산) 포함. find로 동적 스캔.
4. **현재 대화 컨텍스트** — 이 세션에서 수행한 작업, 이슈, TODO.
5. **git 커밋** — Workspace 전체 git 저장소를 동적 스캔. 하드코딩 프로젝트 목록 사용 금지:

```bash
find ~/Workspace -maxdepth 2 -name .git -type d 2>/dev/null |
while read gitdir; do
  dir="${gitdir%/.git}"
  commits=$(git -C "$dir" log --since="$(date +%Y-%m-%d) 00:00" --format="%h %s" 2>/dev/null)
  if [ -n "$commits" ]; then
    echo "=== $(basename "$dir") ==="
    printf '%s\n' "$commits"
  fi
done
```

**누락 방지 규칙:**
- claude-mem timeline은 1순위지만 유일 근거로 쓰지 않는다 (MCP 장애 가능)
- git 커밋이 있는 프로젝트가 세션/Projects 산출물에 없으면 후보에 포함하고 커밋 제목 기준 요약
- `Projects/misc/...` 문서는 커밋 없어도 포함 후보
- 커밋 없는 프로젝트는 대화/세션/Projects 중 하나에서 확인된 경우만 포함

**전날 보고서에서 추출:**
- "할 일" → 오늘 이어서 한 작업
- 미해결 이슈 → 오늘 해결 여부

### 3단계: 내용 구성

각 섹션 작성 규칙:

#### 회고 및 공유 사항 (필수 — 최상단)
- `## 회고 및 공유 사항` 섹션을 본문 최상단에 배치 (오늘 한 일 위)
- **단순 요약이 아니다** — 그날의 핵심 성과 + 진행 상태(완료/진행 중/예정) + 팀에 공유할 사항
- 항목당 한 줄, `- {프로젝트/작업}) {성과} {상태}` 형식. 상태를 문장 끝에 명시:
  - 완료된 것: "... 라이브 반영 완료", "... 정상 작동까지 확인 완료"
  - 진행 중인 것: "... 진행 중. {남은 조건/기한}", "... 검토 진행, {다음 액션}"
- 1줄 최대 100자. 그날 팀이 알아야 할 헤드급 성과/상태만
- 미해결 이슈/블로커가 공유 대상이면 여기에 상태와 함께 1줄 (`## 이슈` 섹션 내용도 여기로 흡수됨)

예 ✅ (성과 + 상태가 드러남):
```
## 회고 및 공유 사항

- 돈버는영어 친구추천 코인지급 자동화 및 데이터 현행화 라이브 반영 완료. 운영 요청 건 정상 처리.
- TM 부분환불 시 이용권 환불 처리 기능 개발·라이브 적용 및 정상 작동까지 확인 완료
- 돈버는영어 전광판 데이터 추출 진행 중. 추가 확인 조건 있어 목요일까지 진행 예정
- 맥스 돈버는영어 세팅 이슈 기술 검토 진행, 우선 업무 대응 후 추가 분석 예정
```

나쁜 예 ❌ (그냥 오늘 한 일 압축 — 상태 없음):
```
## 회고 및 공유 사항

- identity-hub: ih-integrate v0.5.0 릴리스 + redirect_uri 수정
- maxai 인프라: QA2 nginx vhost 통합
```

#### 오늘 한 일
- 프로젝트별 `###`로 그룹핑
- **1 프로젝트 = 최대 3줄, 1줄 = 최대 80자**. 초과 시 잘라낼 것
- 동사 단문 (예: "녹음 정책 응답에 speechApiUrl 추가"). "~하고 ~했다" 결합 금지
- 항목별 WHY/배경 금지. 필요하면 프로젝트당 1줄로 묶어서 마지막에 추가
- 커밋 해시, 브랜치명, 머지 내역 포함 금지
- "세션 기록 참조" 문구 사용 금지

좋은 예 ✅:
```
### speakingmax-backend
- 녹음 정책 응답에 speechApiUrl 추가
- outcome/failure_category/extra 자동 판정 6분기 구현
- mapCellTypeToV2 입력 키 cell_gubun → cell_code 정규화
```

나쁜 예 ❌ (장황/결합문/배경 포함):
```
### speakingmax-backend
- 녹음 정책 API 응답에 speechApiUrl 필드를 추가하여 환경별 speech-hub baseURL을
  클라가 부트스트랩 시점에 받아갈 수 있게 함. 기존 XML view의 sttUrl 태그와
  의미는 같지만 신규 컨벤션으로 도입.
- outcome/failure_category 등을 자동 판정하는 로직을 6분기로 구현하고 extra에
  정책 메타 6필드를 JSON으로 적재하여 분석 시 정책 변경 영향을 추적 가능하게 함.
- ...
```

##### jargon → 사람 말 변환 (필수)

내부 식별자가 들어간 줄은 반드시 업무 표현으로 바꾼다. 독자는 코드를 모른다.

| 나쁜 예 ❌ (HOW·식별자 노출) | 좋은 예 ✅ (WHAT/WHY·사람 말) |
|------------------------------|------------------------------|
| `SPEC-AZURE-METRIC-003: merge() 제거 → merge_parallel(max) 명명. 커밋 0215235` | 음성인식 호출 시간이 실제보다 부풀려 집계되던 버그 수정 |
| `failure_category 마이그레이션 4단계: lib/study-status.ts 추출, Stage 1 b11b76d...` | 학습 화면의 발화 상태 표시가 더 이상 안 쓰는 데이터에 기대 깨져 있던 것을 정상 데이터 기준으로 교체 |
| `recognition/evaluation_status 컬럼이 not_applicable` | 더 이상 사용하지 않는(빈) 데이터 항목 |
| `AzureSpeechCredentialProvider 구현 — asyncio.Lock 원자 회전, AZURE_SPEECH_KEYS 폴백` | 음성인식 API 키를 여러 개 번갈아 쓰도록 해 한도 초과 시 자동 우회 |
| `build·lint·tsc·test(vitest 230개) 통과` | 전체 검증 통과 (또는 생략) |
| `quality-cleanup 브랜치 main 머지` | 코드 정리분 본 코드에 반영 |

규칙:
- 같은 작업이 여러 단계(Stage 1~N)로 쪼개져 있어도 보고서엔 **결과 1~2줄로 합친다**. 단계별 나열 금지
- "검증 통과" 한 줄이면 충분. 빌드/타입체크/테스트 종류와 개수는 적지 않는다
- 어떤 화면·기능·사용자에게 영향이 가는지를 우선 적는다 (예: "학습 화면", "회원 조회", "로그인")

#### 이슈
- `[해결]` 또는 `[미해결]` 접두사
- 원인 + 해결(또는 현재 상태) 각 1줄
- 없으면 섹션 생략

#### 할 일
- 체크박스 `- [ ]`, 프로젝트별 그룹핑
- 전날 미완료 항목은 `(이월)` 표시하되 별도 서브섹션 만들지 말 것

#### 확인 필요 사항
- 다른 사람에게 확인/결정 받아야 하는 것만
- **없으면 섹션 자체 생략**

### 4단계: 문서 생성

경로: `~/Workspace/weaversbrain/weaversbrain/Daily/YYYY-MM/YYYY-MM-DD.md`

```markdown
---
date: "YYYY-MM-DD"
type: daily
tags: [daily]
---

# 일일 업무 보고서

## 회고 및 공유 사항

- {프로젝트/작업}) {성과} {상태 — 완료/진행 중/예정}
- {프로젝트/작업}) {성과} {상태}
- {공유할 이슈/블로커가 있으면 상태와 함께 1줄}

## 오늘 한 일

- {프로젝트/작업}) {핵심 작업 한 줄}
  - {세부 1}
  - {세부 2}
- {프로젝트/작업}) {핵심 작업 한 줄} (with {협업자})

## 할 일

- {프로젝트}) 할 일 1
- {프로젝트}) 할 일 2 (이월)

## 세션 기록

- [[Sessions/YYYY-MM/YYYY-MM-DD-{프로젝트명}]]
```

### 5단계: 저장 확인

1. 기존 파일 있으면 덮어쓸지 사용자에게 확인
2. 저장 경로 + 요약 출력 (프로젝트 수, 작업 항목 수)

### 6단계 (선택): 채팅/메일 붙여넣기용 변환

사용자가 "Mattermost 붙여넣을 버전", "메타모스트", "하이웍스", "카톡용", "MM용", "복사본", "순수 텍스트", "팀 보고 양식", "메일 보고", "일일 업무 보고 양식" 등을 요청하면 다음 스크립트를 실행한다.

```bash
# Mattermost (inline code 지원, 기본 모드)
~/.claude/skills/write-daily-report/to-mattermost.sh [YYYY-MM-DD]

# 하이웍스·카톡·일반 채팅 (모든 마크다운 제거)
~/.claude/skills/write-daily-report/to-mattermost.sh --plain [YYYY-MM-DD]

# 팀 일일 업무 보고 메일/메신저 양식 (인사말+회고및공유+오늘한일+내일할일+맺음말)
~/.claude/skills/write-daily-report/to-mattermost.sh --report [YYYY-MM-DD]
```

| 키워드 | 모드 |
|--------|------|
| Mattermost, 메타모스트, MM | 기본(inline code 유지, `■`/`▸` 헤딩) |
| 하이웍스, 카톡, 이메일, 텍스트, plain | `--plain` (마크다운 완전 제거, `▣`/`▸` 헤딩) |
| 팀 보고, 메일 보고, 일일 업무 보고 양식 | `--report` (팀 보고 메일 양식) |

- 인자 생략 시 오늘 날짜
- stdout에 변환본 출력 + macOS `pbcopy`로 클립보드 복사
- `--plain` 모드는 백틱/볼드/이탤릭/링크/이미지/취소선/수평선 전부 제거 + 문단 간 빈 줄 2개로 가독성 확보
- 이유: 채팅 앱마다 헤딩/볼드를 과장 렌더링하여 "전부 굵게 보이는" 문제 발생. 프리픽스 기호로 바꾸면 평문 느낌 유지하면서 계층 유지

#### `--report` 모드 (팀 일일 업무 보고 메일 양식)

Vault 저장본은 그대로 두고, **출력만** 팀 표준 메일/메신저 양식으로 변환한다. Vault 내부 관리(검색·링크·이월추적)는 손대지 않는다.

- 머리말: `안녕하세요. / {부서} {작성자}입니다. / 일일 업무 보고 드립니다.` / 맺음말: `감사합니다.`
- 작성자·부서는 스크립트 상단 `REPORT_AUTHOR`(기본 `주인식`)·`REPORT_DEPT`(기본 `기술개발연구실`) 상수. env 로 1회성 덮어쓰기 가능: `REPORT_AUTHOR=홍길동 to-mattermost.sh --report`
- 섹션 매핑: `## 요약`→`* 회고 및 공유 사항`, `## 오늘 한 일`→`* 오늘 한 일`, `## 할 일`→`* 내일 할 일`. `## 이슈`/`## 확인 필요 사항`은 **회고 및 공유 사항에 흡수**(별도 섹션 안 만듦)
- 들여쓰기(공백): 섹션 헤더 0칸 / `### 프로젝트` 6칸 / 프로젝트 직속 항목 12칸 / 더 깊은 중첩 18칸 — 팀 표준 양식과 동일한 계단
- 마크다운·체크박스 마커(`[ ]`/`[x]`)·Obsidian 링크 전부 제거된 평문 출력
- 따라서 `--report` 출력 품질을 높이려면 본문 작성 시 `### 프로젝트` 헤딩 아래 동작을 `-` 로 묶고, 협업자는 `(with 이름)` 형태로 적어두면 그대로 살아난다

## 서식 규칙

- 본문에 `**볼드**` 사용 금지. 헤딩(`##`, `###`)으로 구조화하고 본문은 일반체로 작성
  - BAD: `- **긴급 이슈 대응**: AOS/iOS에서...`
  - GOOD: `- 긴급 이슈 대응 — AOS/iOS에서...`
- 강조가 필요하면 백틱(`` ` ``)으로 코드/명령어만 감쌈
- `---` 구분선 사용 금지 (헤딩으로 충분)

## 금지 사항

- 대화와 git에서 확인된 작업만 기록. 추측 금지
- 세션 히스토리를 그대로 복사 금지 — 요약으로 재구성
- 민감 정보 마스킹
- 커밋이 없는 프로젝트는 대화에서 언급된 경우만 포함
- 템플릿에 없는 섹션 추가 금지 (생성된 자산, 핵심 성과, 골든 커맨드, 교훈 등)
- "상세: 세션 기록 참조" 문구 본문에 사용 금지

### 보고서 본문에 절대 넣지 않는 식별자 (독자가 코드를 모른다)

아래가 한 글자라도 보이면 그 줄은 사람 말로 다시 쓴다. 「오늘 한 일 → jargon 변환표」 참조.

- **SPEC ID / 작업 코드**: `SPEC-XXX-NNN`, `METRIC-003`, `B-1`, `R-1` 등
- **커밋 해시**: `b11b76d`, `0215235` 등 (git log로 확인 가능)
- **브랜치명·머지 내역**: `feat/...`, `quality-cleanup`, "main 머지", "feat 브랜치로 분리" 등
- **코드 식별자**: 변수·함수·메서드·클래스·파일 경로 (`lib/study-status.ts`, `merge_parallel()`, `ProviderCallMeta`, `amplifyBuffer`, `cors.inc` 등)
- **DB 식별자**: 테이블·컬럼·뷰·상태값 (`failure_category`, `recognition_status`, `not_applicable` 등)
- **환경변수·설정 키**: `AZURE_SPEECH_KEYS`, `READ_TIMEOUT`, `RETRY_AFTER_MAX`, `need_to_check_url` 등
- **라이브러리·도구·내부 메커니즘 디테일**: `asyncio.Lock`, `peak-headroom`, `라운드 로빈` 등 (필요하면 효과만 풀어 씀)
- **빌드/테스트 도구·수치**: `tsc`, `eslint`, `vitest 230개`, `lint 0`, `build 성공` → "검증 완료" 한 줄 또는 생략
- **단계 번호 나열**: `Stage 1~4`, `1단계/2단계` 식으로 구현 과정을 쪼개 나열 금지 → 결과로 합침

예외: 외부에 공개된 제품/서비스/기술 이름(Azure, CloudFront, SSO, ClickHouse 등)은 그대로 써도 된다 — 보고 대상도 인지하는 고유명사이기 때문.
