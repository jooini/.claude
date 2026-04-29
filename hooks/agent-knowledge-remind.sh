#!/bin/zsh
# PreToolUse:Agent — 커스텀 에이전트에 knowledge 참조 리마인더 주입
# 빌드에 압축본 포함됨 → 상세 필요 시만 원본 Read 안내
# 비차단 (exit 0 + stdout)

INPUT=$(cat)

AGENT_TYPE=$(echo "$INPUT" | sed -n 's/.*"subagent_type"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p')

KNOWLEDGE_BASE="$HOME/.claude/agents/knowledge"

# 커스텀 에이전트만 대상 — 공통 메시지 생성
case "$AGENT_TYPE" in
    backend-developer|frontend-developer|ai-engineer|code-reviewer|code-tester|designer|po|qa|data-analyst|ops-lead|prompt-engineer)
        echo "[KNOWLEDGE] 빌드에 압축 knowledge 포함됨. 상세 내용이 필요한 경우만 ${KNOWLEDGE_BASE}/${AGENT_TYPE}/ 에서 원본 Read."
        ;;
esac

exit 0
