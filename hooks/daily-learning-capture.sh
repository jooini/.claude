#!/bin/zsh
# Stop hook: 세션 종료 시 학습 내용 자동 캡처
#
# 작동:
#   - 세션 jsonl 분석 → 새로 배운 패턴/막힌 것/궁금한 점 추출
#   - Obsidian Learning/{YYYY-MM}/{YYYY-MM-DD}.md 누적 저장
#   - Gemma 활용 (가용 시) — 분석 + 요약
#
# 트리거: 매 세션 종료 (Stop hook)
# 조건: 세션 길이 50턴+ (짧은 세션은 학습 거리 없음)

: "${HOME:?}"

INPUT=$(cat)
SESSION_ID=$(echo "$INPUT" | /usr/bin/python3 -c "
import json, sys
try:
    print(json.load(sys.stdin).get('session_id', ''))
except Exception:
    pass
" 2>/dev/null)

TRANSCRIPT=$(echo "$INPUT" | /usr/bin/python3 -c "
import json, sys
try:
    print(json.load(sys.stdin).get('transcript_path', ''))
except Exception:
    pass
" 2>/dev/null)

if [ -z "$TRANSCRIPT" ] || [ ! -f "$TRANSCRIPT" ]; then
    exit 0
fi

# 세션 턴 수 체크 (너무 짧으면 스킵)
TURN_COUNT=$(/usr/bin/grep -c '"role":"user"' "$TRANSCRIPT" 2>/dev/null || echo 0)
if [ "$TURN_COUNT" -lt 30 ]; then
    exit 0
fi

# Learning 디렉토리
TODAY=$(/bin/date +%Y-%m-%d)
YEAR_MONTH=$(/bin/date +%Y-%m)
LEARNING_DIR="$HOME/Workspace/weaversbrain/weaversbrain/Learning/$YEAR_MONTH"
LEARNING_FILE="$LEARNING_DIR/$TODAY.md"

/bin/mkdir -p "$LEARNING_DIR"

# 새 사용자 발화 + 도구 호출 패턴 추출
/usr/bin/python3 <<PY > /tmp/session-extract.txt 2>/dev/null
import json
import os
from collections import Counter

transcript = "$TRANSCRIPT"

if not os.path.exists(transcript):
    exit(0)

user_questions = []
tool_calls = Counter()
files_read = []
files_edited = []
errors = []

with open(transcript) as f:
    for line in f:
        try:
            d = json.loads(line)
            t = d.get('type')

            if t == 'user':
                msg = d.get('message', {})
                content = msg.get('content')
                if isinstance(content, str) and 10 <= len(content) <= 300:
                    if not content.startswith(('The ', 'File ', 'Exit', '<', '/', '(eval)', 'Web ', '<bash')):
                        user_questions.append(content)

            if t == 'assistant':
                msg = d.get('message', {})
                content = msg.get('content', [])
                if isinstance(content, list):
                    for block in content:
                        if isinstance(block, dict):
                            if block.get('type') == 'tool_use':
                                tool_calls[block.get('name', 'unknown')] += 1
                                inp = block.get('input', {})
                                if block.get('name') == 'Read':
                                    fp = inp.get('file_path', '')
                                    if fp: files_read.append(fp)
                                if block.get('name') == 'Edit':
                                    fp = inp.get('file_path', '')
                                    if fp: files_edited.append(fp)
        except:
            pass

# 의문/탐색 패턴 (학습 신호)
questions = [q for q in user_questions if any(k in q for k in ['왜', '어떻게', '뭐가', '뭐야', '?', '궁금', '이해'])]
issues = [q for q in user_questions if any(k in q for k in ['아니야', '틀렸', '안 돼', '에러', '오류', '실패'])]

print("==QUESTIONS==")
for q in questions[:5]:
    print(q)
print("==ISSUES==")
for q in issues[:5]:
    print(q)
print("==TOOLS==")
for tool, count in tool_calls.most_common(5):
    print(f"{tool}\t{count}")
print("==FILES_EDITED==")
unique_files = list(dict.fromkeys(files_edited))
for f in unique_files[:10]:
    print(f)
PY

# 추출 결과 파싱
QUESTIONS=$(/usr/bin/sed -n '/==QUESTIONS==/,/==ISSUES==/p' /tmp/session-extract.txt | /usr/bin/grep -v "^==" | /usr/bin/head -5)
ISSUES=$(/usr/bin/sed -n '/==ISSUES==/,/==TOOLS==/p' /tmp/session-extract.txt | /usr/bin/grep -v "^==" | /usr/bin/head -5)
TOOLS=$(/usr/bin/sed -n '/==TOOLS==/,/==FILES_EDITED==/p' /tmp/session-extract.txt | /usr/bin/grep -v "^==" | /usr/bin/head -5)
EDITED=$(/usr/bin/sed -n '/==FILES_EDITED==/,$p' /tmp/session-extract.txt | /usr/bin/grep -v "^==" | /usr/bin/head -10)

# 의문/이슈 없으면 학습 거리 적음 → 스킵
if [ -z "$QUESTIONS" ] && [ -z "$ISSUES" ]; then
    exit 0
fi

# 누적 모드 (오늘 파일 있으면 추가)
if [ ! -f "$LEARNING_FILE" ]; then
    cat > "$LEARNING_FILE" <<HEADER
---
date: $TODAY
type: learning
auto_generated: true
---

# 학습 노트 — $TODAY

HEADER
fi

# 세션별 섹션 추가
SHORT_SESSION=$(echo "$SESSION_ID" | /usr/bin/cut -c1-8)
TIME_NOW=$(/bin/date +%H:%M)

cat >> "$LEARNING_FILE" <<EOF

## 세션 $SHORT_SESSION ($TIME_NOW, ${TURN_COUNT}턴)

EOF

if [ -n "$QUESTIONS" ]; then
    /bin/echo "### ❓ 떠올린 질문 (학습 거리)" >> "$LEARNING_FILE"
    /bin/echo "" >> "$LEARNING_FILE"
    echo "$QUESTIONS" | while IFS= read -r q; do
        [ -n "$q" ] && /bin/echo "- $q" >> "$LEARNING_FILE"
    done
    /bin/echo "" >> "$LEARNING_FILE"
fi

if [ -n "$ISSUES" ]; then
    /bin/echo "### 🐛 막힌 것/오류" >> "$LEARNING_FILE"
    /bin/echo "" >> "$LEARNING_FILE"
    echo "$ISSUES" | while IFS= read -r q; do
        [ -n "$q" ] && /bin/echo "- $q" >> "$LEARNING_FILE"
    done
    /bin/echo "" >> "$LEARNING_FILE"
fi

if [ -n "$TOOLS" ]; then
    /bin/echo "### 🛠️ 자주 쓴 도구" >> "$LEARNING_FILE"
    /bin/echo "" >> "$LEARNING_FILE"
    echo "$TOOLS" | while IFS= read -r line; do
        [ -n "$line" ] && /bin/echo "- $line" >> "$LEARNING_FILE"
    done
    /bin/echo "" >> "$LEARNING_FILE"
fi

if [ -n "$EDITED" ]; then
    /bin/echo "### 📝 수정한 파일" >> "$LEARNING_FILE"
    /bin/echo "" >> "$LEARNING_FILE"
    echo "$EDITED" | while IFS= read -r f; do
        [ -n "$f" ] && /bin/echo "- \`$f\`" >> "$LEARNING_FILE"
    done
    /bin/echo "" >> "$LEARNING_FILE"
fi

/bin/echo "### 💡 다음에 깊이 볼 것" >> "$LEARNING_FILE"
/bin/echo "" >> "$LEARNING_FILE"
/bin/echo "_(다음 \`/deep-learn\` 실행 시 자동 분석 대상)_" >> "$LEARNING_FILE"
/bin/echo "" >> "$LEARNING_FILE"

# stdout에 짧은 알림 (다음 세션 시작 시 보일 수 있음)
/bin/echo "[학습 노트 자동 캡처] $LEARNING_FILE"

exit 0
