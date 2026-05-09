---
name: save-all-history
description: 현재 활성 중인 모든 Claude 세션의 작업 내용을 일괄로 Obsidian Sessions/ 에 저장합니다. ~/.claude/projects/{cwd}/{uuid}.jsonl 메시지 로그를 cwd별로 그룹핑하여 프로젝트별 세션 히스토리 문서를 만듭니다. save-history와 sessionId 기준 중복 방지.
disable-model-invocation: true
allowed-tools: Bash(git *), Bash(basename *), Bash(date *), Bash(ls *), Bash(find *), Bash(jq *), Bash(python3 *), Bash(curl *), Bash(grep *), Bash(wc *), Bash(tail *), Bash(head *), Bash(sort *), Bash(uniq *), Read, Write, Edit, Glob
---

# save-all-history

여러 활성 Claude 세션의 작업 내용을 일괄로 Obsidian Vault에 저장한다. 단일 세션 처리는 `save-history` 스킬을 사용한다.

## 사용 시점

- 7개+ Claude 세션을 동시에 띄워놓고 일괄 백업
- 퇴근 전 모든 작업 컨텍스트 단번에 Obsidian 저장
- 다음 날 다른 머신에서 어제 작업 일괄 리뷰

## 핵심 원리

`~/.claude/projects/{cwd-encoded}/{session-uuid}.jsonl` — Claude Code가 자동 저장하는 세션 메시지 로그. 각 라인은 JSON 한 건 (user/assistant/tool 메시지).

**검증된 사실** (스킬 설계 시 확인):
- jsonl 라인은 `cwd` 필드를 **자체 보유** (디렉토리명 sed 디코드 불필요)
- 같은 jsonl 안에 여러 cwd 가능 (worktree, 하위 디렉토리 cd)
- 큰 세션은 2,899줄 이상 (10MB+)
- jsonl mtime은 마지막 메시지 시각과 일치

## 실행 절차

### 1단계: 활성 세션 발견 (jsonl mtime 기준)

```bash
TODAY=$(date +%Y-%m-%d)
MONTH=$(date +%Y-%m)

# 오늘 활동한 세션 jsonl 전체 수집 (mtime -1일)
ACTIVE_JSONLS=$(find ~/.claude/projects -maxdepth 2 -name '*.jsonl' -mtime -1 2>/dev/null)
echo "$ACTIVE_JSONLS" | wc -l   # 후보 수
```

**조건 보강 — 오늘 실제로 메시지 추가된 세션만**:

```bash
# jsonl 내부 마지막 라인의 timestamp가 오늘 이상인 것만
for jsonl in $ACTIVE_JSONLS; do
  last_ts=$(tail -1 "$jsonl" 2>/dev/null | python3 -c "import sys,json; d=json.loads(sys.stdin.read()); print(d.get('timestamp','')[:10])" 2>/dev/null)
  if [ "$last_ts" = "$TODAY" ]; then
    echo "$jsonl"
  fi
done
```

### 2단계: 중복 방지 (이미 저장된 세션 스킵)

`Sessions/{MONTH}/` 의 모든 .md 파일 frontmatter 에서 `sessionId` 필드를 읽어 이미 저장된 sessionId 집합을 만든다. 이번 호출에서는 그 집합에 없는 세션만 처리.

```bash
EXISTING_IDS=$(grep -h '^sessionId:' ~/Workspace/weaversbrain/weaversbrain/Sessions/$MONTH/*.md 2>/dev/null \
  | awk '{print $2}' | tr -d '"' | sort -u)
```

**증분 업데이트 정책**:
- sessionId 일치 + 기존 파일 `lastTimestamp` < jsonl 마지막 timestamp → **추가 작업분만 본문 끝에 append** (덮어쓰기 금지)
- sessionId 일치 + lastTimestamp 동일 → **스킵**
- sessionId 없는 legacy 문서 — 자동 매칭 금지. 신규 파일 생성 (사용자가 나중에 수동 통합)

### 3단계: cwd별 프로젝트 그룹핑

각 jsonl 안의 메시지에서 cwd를 수집한 뒤 정책 적용:

```python
# 같은 repo 하위 cwd는 하나로 묶음
# 예: /ws/A, /ws/A/sub, /ws/A/.worktrees/X → 모두 "A" 프로젝트
# 다른 repo cwd가 섞이면 sessionId 같아도 프로젝트별 split
```

**프로젝트 식별 우선순위**:
1. cwd가 `~/Workspace/{name}` 또는 `~/Workspace/{name}/...` 패턴 → `name`
2. cwd가 `~/Workspace/{name}/.worktrees/{x}` → `{name}` (worktree는 본문에 표시)
3. cwd가 `~/.claude` → `claude-config`
4. cwd가 `~/Workspace` 자체 → `Workspace` (공통 작업)
5. 그 외 — `basename $(cwd)`

### 4단계: 메시지 추출 + 요약

큰 jsonl (>5,000줄 또는 >5MB) 처리:

```bash
LINE_COUNT=$(wc -l < "$jsonl")
SIZE_KB=$(($(wc -c < "$jsonl") / 1024))

if [ "$LINE_COUNT" -le 500 ]; then
  # 작은 세션 — 전체 user/assistant 텍스트만 추출
  EXTRACTED=$(python3 -c "
import json,sys
lines = open('$jsonl').readlines()
out = []
for ln in lines:
    try:
        d = json.loads(ln)
        t = d.get('type')
        if t == 'user':
            c = d.get('message',{}).get('content','')
            if isinstance(c,str) and len(c) < 2000: out.append('USER: '+c)
        elif t == 'assistant':
            for blk in d.get('message',{}).get('content',[]):
                if blk.get('type')=='text':
                    out.append('ASST: '+blk['text'][:2000])
    except: pass
print('\n'.join(out))
")
else
  # 큰 세션 — 마지막 200개 메시지만
  EXTRACTED=$(tail -1000 "$jsonl" | python3 -c "...")  # 위와 동일
fi
```

### 5단계: Ollama 로컬 요약 (순차)

LLM 부하/단일 GPU 고려 **순차 처리** (병렬 금지):

```bash
for sid in "${ACTIVE_SESSION_IDS[@]}"; do
  PROMPT="다음 Claude 세션 메시지를 한국어로 요약. save-history 스킬 형식 따름.

작업 요약 (표 형식 # | 작업 | 상태):
상세 내역 (변경 파일, 핵심 변경):
이슈 및 해결 (표):
미해결/TODO (체크박스):

세션 내용:
$EXTRACTED"

  SUMMARY=$(curl -s --max-time 180 http://leonard.local:11434/api/generate \
    -d "$(jq -n --arg p "$PROMPT" '{model:"qwen3.5:9b", prompt:$p, stream:false, keep_alive:"30m", options:{num_ctx:16384}}')" \
    | python3 -c "import json,sys; print(json.load(sys.stdin).get('response','요약 실패'))")

  # 다음 단계 — 파일 저장
done
```

**토큰 예산**:
- num_ctx 16384 (qwen3.5:9b RTX 4090 Laptop 적정)
- prompt 5KB 이하 권장. 초과 시 메시지 청크 분할 → 청크별 요약 → 합치기

### 6단계: 파일 저장

경로: `~/Workspace/weaversbrain/weaversbrain/Sessions/{MONTH}/{TODAY}-{프로젝트}.md`
중복 시 `-2`, `-3` 증번 (save-history 컨벤션 동일).

**frontmatter 필수 필드**:

```markdown
---
date: "YYYY-MM-DD"
project: {프로젝트명}
type: session
sessionId: {jsonl uuid}
sourceJsonl: {jsonl 절대경로}
lastTimestamp: "{jsonl 마지막 라인 timestamp}"
generatedBy: save-all-history
tags: [{태그}, session]
---
```

**본문 구조** (save-history와 동일하게):

```markdown
# {세션 주요 작업 제목 — Ollama가 추출}

**프로젝트:** `{프로젝트 경로}` | **브랜치:** `{gitBranch}`
**세션 ID:** `{uuid:0:8}` | **작업 경로:** {여러 cwd 콤마 구분}

## 작업 요약
| # | 작업 | 상태 |
...

## 상세 내역
...

## 이슈 및 해결
...

## 미해결 / TODO
...
```

### 7단계: 저장 결과 출력

```
저장된 세션: N개
스킵된 세션 (중복): M개
업데이트된 세션 (증분): K개

저장 위치:
- ~/Workspace/weaversbrain/weaversbrain/Sessions/{MONTH}/{TODAY}-speakingmax-backend.md (sid abc12345)
- ~/Workspace/weaversbrain/weaversbrain/Sessions/{MONTH}/{TODAY}-ini.md (sid def67890)
...
```

## save-history와의 차이

| 항목 | save-history | save-all-history |
|---|---|---|
| 처리 범위 | 현재 세션 1개 | 활성 세션 N개 일괄 |
| 정보 소스 | 현재 대화 컨텍스트 + git | jsonl 메시지 로그 + git |
| 요약 주체 | Claude (현재 세션) | Ollama qwen3.5:9b (로컬) |
| 중복 방지 | 동명 파일 -2/-3 | sessionId 비교 + 증분 |
| 호출 시점 | 작업 완료 시 매번 | 퇴근 전 1회 일괄 |

## 주의사항

- **save-history 결과 덮어쓰기 금지** — sessionId 없는 legacy 문서는 별도 처리
- 큰 jsonl 토큰 한계 — num_ctx 16K 초과 시 청크 분할 필수
- 민감 정보 마스킹 — Ollama 요약 전 SSH 키/토큰/비밀번호 패턴 grep -v
- 멀티 cwd 정책 — 같은 repo 하위는 합치고, 다른 repo는 split
- 병렬 호출 금지 — Ollama 단일 GPU, 순차 처리
- frontmatter `sessionId` 필드 무결성 — 다음 호출에서 중복 방지의 키
- 자동 트리거 금지 — 명시적 사용자 호출만 (`/save-all-history` 또는 발화)

## 확장 — 자동화 옵션

`~/.claude/hooks/` 에 종료 시 자동 호출 hook 등록 가능. 단, jsonl이 매우 클 때 처리 시간(세션당 30초+) 고려 필요. **기본은 수동 호출**.

## 트러블슈팅

| 증상 | 원인 | 해결 |
|---|---|---|
| Ollama 응답 늦음 | 모델 콜드 스타트 | `keep_alive: "30m"` 명시, 첫 호출 후 빠름 |
| `num_ctx` 초과 에러 | jsonl 큼 | tail -200 또는 청크 분할 |
| sessionId 매칭 실패 | legacy save-history 문서 | 별도 파일 생성 (덮어쓰기 안 함) |
| jsonl 파싱 에러 | 일부 라인 깨짐 | try/except로 라인 단위 skip |
| 같은 프로젝트 여러 세션 | sessionId 다름 | `-2`, `-3` 증번 |
| Ollama 서버 다운 | leonard.local 미접속 | curl 헬스체크 후 사용자에게 알림 |
