---
name: write-daily-report
description: claude-mem, 세션 기록, 프로젝트 산출물(Projects/), 전체 Workspace git 커밋을 교차 수집하여 오늘 전체 작업 기반 일일 업무 보고서를 작성합니다. Mattermost 붙여넣기용 변환도 지원(to-mattermost.sh).
disable-model-invocation: true
allowed-tools: Bash(git *), Bash(date *), Bash(ls *), Bash(find *), Bash(~/.claude/skills/write-daily-report/to-mattermost.sh *), Read, Write, Glob, mcp__plugin_claude-mem_mcp-search__timeline, mcp__plugin_claude-mem_mcp-search__search, mcp__plugin_claude-mem_mcp-search__get_observations
---

# write-daily-report

오늘 하루 작업 기반으로 간결한 일일 업무 보고서를 작성한다.

## 핵심 원칙

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

#### 요약 (필수 — 최상단)
- `## 요약` 섹션을 본문 최상단에 배치 (오늘 한 일 위)
- 프로젝트당 한 줄, `- {프로젝트명}: {핵심 헤드라인 1-2개를 + 로 연결}` 형식
- 1줄 최대 100자. 그날의 결정/머지/배포 등 헤드급만
- 마지막 1줄로 미해결 이슈/블로커 1개를 `- 이슈: ...` 로 명시 (있을 때만)
- 본문(오늘 한 일)과 중복돼도 OK — 요약은 한 줄로 묶고 본문은 동사 단문으로 분해

예 ✅:
```
## 요약

- speakingmax-backend: gzip audio develop 머지 + presigned URL IDOR 가드
- speakingmax-study-admin: BFF gunzip 스트림 + AudioCompareView 1053→127줄 분할
- 이슈: audioGain AOS 통합 미적용 — 내일 안드로이드 전달 예정
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

## 요약

- {프로젝트1}: {헤드라인 1-2개}
- {프로젝트2}: {헤드라인 1-2개}
- 이슈: {미해결/블로커 1줄, 있을 때만}

## 오늘 한 일

### {프로젝트/작업 제목}

- 작업 요약 (3~5줄, 무엇을 왜 했는지)

## 이슈

### [해결] {이슈명}

- 원인: {한 줄}
- 해결: {한 줄}

### [미해결] {이슈명}

- 원인: {한 줄}
- 현재 상태: {한 줄}

## 할 일

### {프로젝트}

- [ ] 할 일 1
- [ ] 할 일 2 (이월)

## 확인 필요 사항

- 확인 내용 (없으면 이 섹션 자체 생략)

## 세션 기록

- [[Sessions/YYYY-MM/YYYY-MM-DD-{프로젝트명}]]
```

### 5단계: 저장 확인

1. 기존 파일 있으면 덮어쓸지 사용자에게 확인
2. 저장 경로 + 요약 출력 (프로젝트 수, 작업 항목 수)

### 6단계 (선택): 채팅 붙여넣기용 변환

사용자가 "Mattermost 붙여넣을 버전", "메타모스트", "하이웍스", "카톡용", "MM용", "복사본", "순수 텍스트" 등을 요청하면 다음 스크립트를 실행한다.

```bash
# Mattermost (inline code 지원, 기본 모드)
~/.claude/skills/write-daily-report/to-mattermost.sh [YYYY-MM-DD]

# 하이웍스·카톡·일반 채팅 (모든 마크다운 제거)
~/.claude/skills/write-daily-report/to-mattermost.sh --plain [YYYY-MM-DD]
```

| 키워드 | 모드 |
|--------|------|
| Mattermost, 메타모스트, MM | 기본(inline code 유지, `■`/`▸` 헤딩) |
| 하이웍스, 카톡, 이메일, 텍스트, plain | `--plain` (마크다운 완전 제거, `▣`/`▸` 헤딩) |

- 인자 생략 시 오늘 날짜
- stdout에 변환본 출력 + macOS `pbcopy`로 클립보드 복사
- `--plain` 모드는 백틱/볼드/이탤릭/링크/이미지/취소선/수평선 전부 제거 + 문단 간 빈 줄 2개로 가독성 확보
- 이유: 채팅 앱마다 헤딩/볼드를 과장 렌더링하여 "전부 굵게 보이는" 문제 발생. 프리픽스 기호로 바꾸면 평문 느낌 유지하면서 계층 유지

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
- 커밋 해시, 브랜치명, 머지 내역 포함 금지 (git log로 확인 가능)
- "상세: 세션 기록 참조" 문구 본문에 사용 금지
