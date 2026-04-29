---
name: tool-status
description: Claude Code/Gemini/Codex 도구 사용 현황 대시보드를 표시합니다.
disable-model-invocation: true
allowed-tools: Bash(ls *), Bash(cat *), Bash(wc *), Bash(date *), Bash(sort *), Bash(awk *), Bash(head *), Read, Glob
---

# tool-status

도구 사용 현황 대시보드를 표시한다.

## 실행 절차

### 1단계: 사용 로그 수집

로그 파일 위치: `~/.claude/cache/usage/YYYY-MM-DD.log`
형식: `TIMESTAMP|TOOL|PROJECT|STATUS|ACTION`

$ARGUMENTS가 있으면:
- "today" 또는 빈 값: 오늘 로그만
- "week": 최근 7일
- "month": 최근 30일
- "YYYY-MM-DD": 특정 날짜

### 2단계: 통계 집계

로그에서 다음을 집계:

**도구별 사용 횟수:**
```bash
awk -F'|' '{print $2}' ~/.claude/cache/usage/*.log | sort | uniq -c | sort -rn
```

**프로젝트별 사용 횟수:**
```bash
awk -F'|' '{print $3}' ~/.claude/cache/usage/*.log | sort | uniq -c | sort -rn
```

**시간대별 분포:**
```bash
awk -F'|' '{split($1,t," "); split(t[2],h,":"); print h[1]"시"}' ~/.claude/cache/usage/*.log | sort | uniq -c | sort -k2
```

**실패율:**
```bash
awk -F'|' '{total++; if($4=="fail") fail++} END {printf "총 %d회, 실패 %d회 (%.1f%%)\n", total, fail, fail/total*100}' ~/.claude/cache/usage/*.log
```

### 3단계: 캐시 상태

```bash
# Gemini 캐시
ls -la ~/.claude/cache/gemini/ 2>/dev/null | wc -l
du -sh ~/.claude/cache/gemini/ 2>/dev/null

# Codex 캐시
ls -la ~/.claude/cache/codex/ 2>/dev/null | wc -l
du -sh ~/.claude/cache/codex/ 2>/dev/null

# 파이프라인 상태
ls ~/.claude/cache/pipeline/ 2>/dev/null
```

### 4단계: 출력

마크다운 테이블로 출력:

```
## 도구 사용 현황 ({기간})

### 사용 횟수
| 도구 | 횟수 | 성공 | 실패 |
|------|------|------|------|
| gemini | N | N | N |
| codex | N | N | N |
| agent:backend-developer | N | N | N |
| ... | | | |

### 프로젝트별
| 프로젝트 | gemini | codex | agents | 합계 |
|----------|--------|-------|--------|------|
| identity-hub | N | N | N | N |
| ... | | | | |

### 시간대별 분포
| 시간대 | 횟수 | ██████ |
|--------|------|--------|

### 캐시 상태
| 디렉토리 | 파일 수 | 크기 |
|----------|---------|------|
| gemini/ | N | NMB |
| codex/ | N | NMB |
| pipeline/ | N | NMB |
```

## 입력

$ARGUMENTS
