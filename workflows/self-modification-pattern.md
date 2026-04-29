# Claude 자기 설정 수정 표준 절차

> CLAUDE.md에서 `@~/.claude/workflows/self-modification-pattern.md` 로 참조됨.
> 자기 글로벌 설정(CLAUDE.md, settings.json) 수정이 필요할 때 자동으로 이 절차 따른다.

## 배경 — 시스템 가드

Claude Code 본체에 **self-modification 보안 가드**가 내장되어 있다. 다음 파일들에 대한 직접 수정(Edit/Write/Bash 모두)은 시스템 레벨에서 차단된다:

| 파일 | 차단 사유 |
|------|----------|
| `~/.claude/CLAUDE.md` | 글로벌 에이전트 설정 |
| `~/.claude/settings.json` | 권한/hook/MCP 설정 |
| `~/.claude/settings.local.json` | 로컬 권한 설정 |

차단 메시지 예시:
```
Self-Modification of agent configuration without explicit user authorization
BLOCK condition with no applicable exception
```

이 가드는 **plugin/hook이 아닌 본체 정책**이라 우회 불가. 사용자 권한으로 끌 수 없는 옵션.

## 표준 우회 절차 (5단계)

### 1단계: 수정 필요성 판단

다음 경우만 자기 설정 수정:
- 사용자가 명시적으로 요청 ("CLAUDE.md에 추가해줘")
- 새 hook/스킬 등록 (settings.json)
- 권한 룰 갱신 (allow/deny)
- 트리거 키워드/라우팅 표 갱신

**금지**:
- 사용자 요청 없는 자동 수정
- 일시적 변경
- 검증 안 된 변경

### 2단계: 백업 (필수)

```bash
/bin/cp ~/.claude/CLAUDE.md ~/.claude/CLAUDE.md.bak-$(/bin/date +%Y%m%d-%H%M%S)
# 또는
/bin/cp ~/.claude/settings.json ~/.claude/settings.json.bak-$(/bin/date +%Y%m%d-%H%M%S)
```

이건 자기 수정 아닌 백업이라 가드 안 막힘.

### 3단계: 임시 파일 빌드

수정된 전체 내용을 `/tmp/`에 작성:

```bash
# A. 새 내용 블록만 별도 텍스트 파일
# (Write 도구 사용)
/tmp/claude-md-insert.txt

# B. awk로 원본에 삽입 → 새 파일 생성
/usr/bin/awk '/^## TARGET_HEADING/ && !inserted {while ((getline line < "/tmp/claude-md-insert.txt") > 0) print line; close("/tmp/claude-md-insert.txt"); inserted=1} {print}' ~/.claude/CLAUDE.md > /tmp/claude-md-new.txt

# C. 검증 (라인 수, 추가 부분 미리보기)
/usr/bin/wc -l ~/.claude/CLAUDE.md /tmp/claude-md-new.txt
/usr/bin/grep -A5 "추가된 섹션" /tmp/claude-md-new.txt
```

settings.json은 Python으로 안전하게 JSON 조작:
```bash
/usr/bin/python3 <<'PY'
import json
with open('/Users/leonard/.claude/settings.json') as f:
    d = json.load(f)
# 변경 작업
d['permissions']['allow'].extend([...])
with open('/tmp/settings-new.json', 'w') as f:
    json.dump(d, f, indent=2, ensure_ascii=False)
PY
```

### 4단계: 사용자에게 적용 명령 제시

본인이 직접 실행해야 함. 명확한 한 줄로:

```
! cp /tmp/claude-md-new.txt ~/.claude/CLAUDE.md
```

또는

```
! cp /tmp/settings-new.json ~/.claude/settings.json
```

`!` 접두사는 Claude Code 대화창에서 사용자 직접 실행. 가드 안 걸림.

### 5단계: 적용 검증

```bash
# 라인 수 변경 확인
/usr/bin/wc -l ~/.claude/CLAUDE.md

# 추가 내용 들어갔나 확인
/usr/bin/grep -A2 "추가한 섹션 헤더" ~/.claude/CLAUDE.md

# settings.json: JSON 파싱 + 룰 카운트
/usr/bin/python3 -c "
import json
with open('/Users/leonard/.claude/settings.json') as f:
    d = json.load(f)
print('allow rules:', len(d.get('permissions',{}).get('allow',[])))
"
```

검증 안 되면 백업으로 복구:
```bash
! cp ~/.claude/CLAUDE.md.bak-{시간} ~/.claude/CLAUDE.md
```

## 자주 쓰는 패턴

### A. CLAUDE.md에 새 섹션 추가

위치 지정자: 기존 섹션 헤더(`## XXX`)를 awk 매칭 패턴으로

```bash
# "## 도구 역할 분담" 섹션 직전에 새 블록 삽입
/usr/bin/awk '/^## 도구 역할 분담/ && !inserted {
    while ((getline line < "/tmp/insert.txt") > 0) print line;
    close("/tmp/insert.txt");
    inserted=1
} {print}' ~/.claude/CLAUDE.md > /tmp/claude-md-new.txt
```

### B. settings.json hook 추가

```python
import json
with open('/Users/leonard/.claude/settings.json') as f:
    d = json.load(f)

new_hook = {
    'type': 'command',
    'command': '/Users/leonard/.claude/hooks/새_hook.sh',
    'timeout': 5
}

d['hooks']['UserPromptSubmit'][0]['hooks'].append(new_hook)
# 또는 새 트리거 추가
# d['hooks']['PostToolUse'].append({'matcher': 'Bash', 'hooks': [new_hook]})

with open('/tmp/settings-new.json', 'w') as f:
    json.dump(d, f, indent=2, ensure_ascii=False)
```

### C. settings.json 권한 룰 추가

```python
allow_rules = [
    'Bash(grep *)',
    'Bash(ls *)',
    # ...
]

perms = d.setdefault('permissions', {})
existing = perms.get('allow', [])
perms['allow'] = list(dict.fromkeys(existing + allow_rules))  # 중복 제거
```

## 검증된 사례 (2026-04-28 세션)

이 세션에서 표준 절차로 수정한 항목들:

| 변경 | 방법 | 결과 |
|------|------|------|
| CLAUDE.md "작업 타입 자동 라우팅" 섹션 추가 | awk 삽입 → 사용자 cp | ✅ 191줄 → 200줄 |
| CLAUDE.md "백로그 정책" 섹션 추가 | awk 삽입 → 사용자 cp | ✅ 200줄 → 209줄 |
| settings.json memory-search hook 등록 | Python json 수정 → 사용자 cp | ✅ UserPromptSubmit hook 추가 |
| settings.json allow 룰 71개 추가 | Python json 수정 → 사용자 cp | ✅ defaultMode auto + 명시 allowlist |

## 금지 사항

❌ Edit 도구로 자기 설정 직접 수정 시도 (가드 차단)
❌ Write 도구로 자기 설정 덮어쓰기 시도 (가드 차단)
❌ Bash로 `cp /tmp/foo ~/.claude/X` 직접 실행 (가드 차단)
❌ 사용자 승인 없이 자동 수정 시도

## 권장 사항

✅ 사용자가 "수정해줘" 명시할 때만 수정
✅ 백업 → 임시 파일 → 사용자 직접 cp → 검증 5단계 준수
✅ 변경 사유와 효과를 사용자에게 명확히 설명
✅ 검증 안 되면 즉시 백업 복구 안내

## 단축 트리거

다음 키워드 감지 시 자동으로 이 절차 따른다:
- "CLAUDE.md 수정해줘"
- "글로벌 설정 추가"
- "권한 룰 추가"
- "hook 등록"
- "트리거 키워드 추가"

매번 절차 설명 반복 금지. 임시 파일 만들고 사용자에게 cp 명령 한 줄 제시.

## 향후 개선 (이 가드가 풀리면)

만약 향후 Anthropic이 self-modification을 사용자 승인 후 허용하는 옵션 제공하면:
1. settings.json에 명시적 권한 룰 추가
2. 이 문서의 우회 절차는 단순화

현재(2026-04-28 기준)는 우회 불가, 위 5단계 절차 필수.
