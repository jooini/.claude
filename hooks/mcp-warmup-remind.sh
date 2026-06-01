#!/bin/zsh
# SessionStart: 자주 쓰는 MCP 도구 ToolSearch 선행(warm-up) 안내
#
# deferred 모드에서 mcp__ 도구 직접 호출은 InputValidationError 왕복을 부른다.
# 셸 hook 은 ToolSearch 를 직접 실행할 수 없으므로(LLM 전용 도구),
# Claude 에게 "세션 초반에 자주 쓰는 MCP 를 미리 ToolSearch 로 로드하라"고 안내한다.
#
# 대상은 최근 30일 transcript 실측 호출 빈도 기준 (2026-06-01 교정):
#   1위 ouroboros 계열(job_wait 70 등), 2위 ssh 계열(30), claude-mem search 0회.
# 설계 원칙 (Codex 교차검증 일치):
#   - 도구 20개+ 나열은 컨텍스트 노이즈 → 상위 "계열" 2~3개만, 개별 도구명 대신 군으로 묶음
#   - ouroboros 같은 연쇄 도구군은 SessionStart preload 대신 "워크플로 진입 시 ToolSearch 1회"
#   - 빈도 0인 claude-mem 은 상시 안내에서 제외, "회고/기억" 키워드 시 lazy-load 만 언급

: "${HOME:?}"

# 너무 자주 띄우면 노이즈 → 하루 1회만 (date 스탬프 가드)
STAMP="$HOME/.claude/cache/mcp-warmup-remind.stamp"
TODAY=$(date '+%Y-%m-%d')
[ "$(cat "$STAMP" 2>/dev/null)" = "$TODAY" ] && exit 0
printf '%s' "$TODAY" > "$STAMP" 2>/dev/null

cat <<'MSGEOF'
[MCP warm-up 권고]

이 환경은 MCP 도구가 많아 deferred(지연 로딩) 모드다. mcp__ 도구를 ToolSearch 없이
바로 부르면 InputValidationError 가 난다(mcp-deferred-guard 가 차단). 원칙:

  mcp__ 도구는 "쓰기 직전 ToolSearch 1회 → 노출된 이름으로 호출". preload 불필요.

작업 성격별 진입 시점에 한 번만:
  - SSH 작업 진입: ToolSearch(query: "ssh remote", max_results: 5)
  - ouroboros 워크플로 진입: ToolSearch(query: "ouroboros job", max_results: 8)
  - 회고/기억/과거결정 검색 시: ToolSearch(query: "memory search", max_results: 3)
MSGEOF

exit 0
