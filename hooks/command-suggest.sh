#!/bin/zsh
# UserPromptSubmit: 사용자 프롬프트 키워드 감지 → 명령어/스킬 자동 제안
#
# 목적: 50개 스킬 외울 필요 없이, 상황 맞으면 자동 제안 표시
# 효과: "있는 거 모르겠어" 문제 해결 — 발화 시점에 명령어 매칭

: "${HOME:?}"

INPUT=$(cat)
PROMPT=$(echo "$INPUT" | sed -n 's/.*"prompt"[[:space:]]*:[[:space:]]*"\(.*\)".*/\1/p' | head -c 2000)

# 너무 짧으면 스킵
PROMPT_LEN=${#PROMPT}
if [ "$PROMPT_LEN" -lt 5 ]; then
    exit 0
fi

# 이미 슬래시 명령어로 시작하면 스킵 (사용자가 이미 알고 호출 중)
if echo "$PROMPT" | grep -qE '^/'; then
    exit 0
fi

SUGGESTIONS=()

# === 키워드 → 명령어 매핑 ===

# 일과/시작/종료
if echo "$PROMPT" | grep -qiE '(아침|시작하자|뭐해야|오늘 할|today)'; then
    SUGGESTIONS+=("/morning — 아침 종합 (today + backlog + 서버 + git)")
elif echo "$PROMPT" | grep -qiE '(퇴근|마무리|끝내자|done)'; then
    SUGGESTIONS+=("/done — 커밋 + 일일 보고 + 세션 저장")
fi

# 디버깅/버그
if echo "$PROMPT" | grep -qiE '(버그|에러|오류|안 ?돼|작동 ?안|fix |bug |stack ?trace|예외|exception)'; then
    SUGGESTIONS+=("/debug — 자동 진단 (재현→로그→가설→수정)")
fi

# 백로그
if echo "$PROMPT" | grep -qiE '(백로그|backlog|할 ?일|task)'; then
    SUGGESTIONS+=("/backlog — 12 프로젝트 대시보드")
    if echo "$PROMPT" | grep -qiE '(쌓였|많아|정리|stale)'; then
        SUGGESTIONS+=("/orchestrator — 백로그 자동 순회 처리")
    fi
fi

# 배포/서버
if echo "$PROMPT" | grep -qiE '(배포|deploy|prod|서버 ?상태|server)'; then
    SUGGESTIONS+=("/safe-deploy — 4단계 안전 체크 (서버+환경+마이그+배포상태)")
    SUGGESTIONS+=("/check-server — Docker 컨테이너 상태")
fi

# SSO/인증
if echo "$PROMPT" | grep -qiE '(SSO|sso|Keycloak|JWT|인증|로그인|OAuth|토큰|세션)'; then
    SUGGESTIONS+=("/sso-flow — 4프로젝트 통합 컨텍스트 + 호환성 체크")
    SUGGESTIONS+=("/cross-check — 멀티프로젝트 영향 분석")
fi

# 검색/찾기
if echo "$PROMPT" | grep -qiE '(찾아|어디|어디에|where|어떻게.*했|이전에)'; then
    SUGGESTIONS+=("mcp__plugin_claude-mem_mcp-search__search — 과거 세션 검색 (252+ 세션)")
    SUGGESTIONS+=("mcp__local-rag__query_documents — 의미론적 검색 (75365 청크)")
fi

# PRD/기획/문서
if echo "$PROMPT" | grep -qiE '(PRD|기획|요구 ?사항|스펙|spec|문서 ?작성)'; then
    SUGGESTIONS+=("피오 — po 에이전트 (PRD/기획)")
    SUGGESTIONS+=("프롬프트 — prompt-engineer (스킬/에이전트 수정)")
fi

# 디자인/UI
if echo "$PROMPT" | grep -qiE '(UI|화면|디자인|레이아웃|스타일|design)'; then
    SUGGESTIONS+=("디자이너 — designer 에이전트")
    SUGGESTIONS+=("Skill(frontend-design) — 컴포넌트 디자인")
fi

# 데이터/쿼리
if echo "$PROMPT" | grep -qiE '(쿼리|SQL|ClickHouse|대시보드|차트|분석|성능 ?측정)'; then
    SUGGESTIONS+=("데이터 — data-analyst 에이전트")
fi

# 리뷰
if echo "$PROMPT" | grep -qiE '(리뷰|review|검토|체크|검증)'; then
    if ! echo "$PROMPT" | grep -qiE '(3중|병렬|동시)'; then
        SUGGESTIONS+=("3중 리뷰 — code-reviewer + codex:review + Gemini 병렬 (한 번에 3명 의견)")
    fi
fi

# 큰 결정/마이그레이션/조사
if echo "$PROMPT" | grep -qiE '(마이그레이션|migration|업그레이드|upgrade|선택지|대안|결정)'; then
    SUGGESTIONS+=("Skill(deep-research) — 심층 조사 후 결정")
    SUGGESTIONS+=("Skill(ask-codex) — 세컨드 오피니언")
fi

# 큰 분석/스캔
if echo "$PROMPT" | grep -qiE '(전체 ?스캔|아키텍처|architecture|구조 ?파악|영향 ?범위)'; then
    SUGGESTIONS+=("Skill(ask-gemini) — 1M 토큰 대규모 스캔")
fi

# 멀티프로젝트
if echo "$PROMPT" | grep -qiE '(멀티 ?프로젝트|여러 ?프로젝트|크로스 ?프로젝트|동시 ?수정)'; then
    SUGGESTIONS+=("/team sso-core — SSO 4프로젝트 동시 spawn")
    SUGGESTIONS+=("/team b2c-fullstack — B2C 풀스택 spawn")
fi

# 보안 변경
if echo "$PROMPT" | grep -qiE '(보안|security|취약|CVE|시크릿|secret)'; then
    SUGGESTIONS+=("Skill(codex:adversarial-review) — 보안 검증 격상")
fi

# 회고/측정
if echo "$PROMPT" | grep -qiE '(회고|retro|얼마나|효과|측정)'; then
    SUGGESTIONS+=("/retro 7 — 주간 파이프라인 회고")
fi

# 결정 기록 검색
if echo "$PROMPT" | grep -qiE '(왜.*했|왜.*결정|이유|rationale|decision)'; then
    SUGGESTIONS+=("/decisions — 자동 캡처된 과거 결정 검색")
fi

# 모니터링/반복
if echo "$PROMPT" | grep -qiE '(계속.*확인|반복.*체크|주기적|polling)'; then
    SUGGESTIONS+=("/loop 5m /check-server — 5분마다 자동 실행")
fi

# 핸드오프
if echo "$PROMPT" | grep -qiE '(다른 ?세션|핸드오프|인계|새 ?세션|이어서)'; then
    SUGGESTIONS+=("/session-handoff — 핸드오프 문서 생성")
fi

# 결과 출력 (제안 없으면 침묵)
if [ ${#SUGGESTIONS[@]} -eq 0 ]; then
    exit 0
fi

# 중복 제거
UNIQUE=$(printf '%s\n' "${SUGGESTIONS[@]}" | awk '!seen[$0]++')

cat <<EOF
[💡 명령어 제안]

다음 명령어/패턴이 도움될 수 있음:

EOF
echo "$UNIQUE" | while IFS= read -r s; do
    echo "  • $s"
done
echo ""
echo "외우려 하지 말 것. 발화 시점에 hook이 매칭. 안 쓰면 무시 OK."

exit 0
