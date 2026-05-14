#!/bin/zsh
# UserPromptSubmit: 사용자 프롬프트 키워드 감지 → 해당 workflow .md 내용을 system 메시지로 주입
#
# 배경:
#   md-trace v2 측정(2026-05-08) 결과 CLAUDE.md "조건부 로드" 표 14개 .md 가
#   14일간 평균 1회만 Read. Claude 가 자율적으로 키워드 보고 .md를 안 끌어옴.
#   훅이 강제 주입해서 라우팅 룰을 살린다.
#
# 정책:
#   - 키워드 매칭된 .md만 주입 (전부가 아님)
#   - 한 발화에 여러 .md 매칭되면 최대 3개까지 (토큰 보호)
#   - 너무 짧은 발화(<10자) 또는 슬래시 명령(/...)은 스킵
#   - 같은 세션에서 같은 .md 중복 주입 방지: 캐시 파일 사용

: "${HOME:?}"

INPUT=$(cat)
# JSON 정확 파싱 (멀티라인/이스케이프 따옴표/중첩 필드 안전)
PARSED=$(printf '%s' "$INPUT" | python3 -c '
import json, sys
try:
    d = json.loads(sys.stdin.read())
    p = d.get("prompt", "") or ""
    s = d.get("session_id", "") or "default"
    # 한글 4000자 정도 = 12000 bytes
    print(p[:4000].replace("\x00", " "))
    print("\x1e", end="")  # record separator
    print(s)
except Exception:
    pass
' 2>/dev/null)
PROMPT="${PARSED%%$'\x1e'*}"
SESSION_ID="${PARSED##*$'\x1e'}"
SESSION_ID="${SESSION_ID%$'\n'}"
PROMPT="${PROMPT%$'\n'}"

# 너무 짧으면 스킵
[ ${#PROMPT} -lt 10 ] && exit 0

# 슬래시 명령은 스킵 (스킬이 알아서 처리)
echo "$PROMPT" | grep -qE '^/' && exit 0

# 세션별 주입 캐시 (중복 방지)
CACHE_DIR="$HOME/.claude/cache/workflow-md-inject"
mkdir -p "$CACHE_DIR"
CACHE_FILE="$CACHE_DIR/${SESSION_ID:-default}.txt"
touch "$CACHE_FILE"

WF_DIR="$HOME/.claude/workflows"
MATCHED=()

# === 키워드 → workflow .md 매핑 ===
# (각 행: "정규식|파일명")
RULES=(
    "(codex|gpt-?5|세컨드 ?오피니언|second ?opinion)|codex.md"
    "(SSO|Identity ?Hub|keycloak|B2C|JWT|access_token|refresh_token|로그인|OAuth|인증|service-token)|sso.md"
    "(버그|에러|오류|안 ?돼|작동 ?안|fix |bug |예외|stack ?trace|exception|디버그)|debugging.md"
    "(gemini|gemma|ollama|qwen|1M ?토큰|로컬 ?LLM)|llm-routing.md"
    "(문서|PRD|스펙|마크다운|markdown|Obsidian|옵시디언)|docs-convention.md"
    "(코딩 ?컨벤션|네이밍|코딩 ?스타일|naming|FastAPI|Annotated)|coding-convention.md"
    "(파이프라인|pipeline|backend|frontend|fullstack)|pipeline.md"
    "(기능 ?추가|새 ?기능|리팩터|refactor|UI |화면|디자인|쿼리|대시보드|배포|deploy|Docker|Terraform|SPI)|standard-routines.md"
    "(훅|hook|자동화|automation|메트릭|measurement)|automation.md"
    "(학습|회고|성장|3중 ?LLM|deep[- ]?learn|retro)|growth.md"
    "(프로젝트 ?목록|어떤 ?프로젝트|workspace 구조)|projects.md"
)

for rule in "${RULES[@]}"; do
    pattern="${rule%|*}"
    file="${rule##*|}"
    if echo "$PROMPT" | grep -qiE "$pattern"; then
        # 이미 이 세션에서 주입했으면 스킵
        if grep -qFx "$file" "$CACHE_FILE"; then
            continue
        fi
        if [ -f "$WF_DIR/$file" ]; then
            MATCHED+=("$file")
            echo "$file" >> "$CACHE_FILE"
        fi
    fi
    # 최대 3개까지만
    [ ${#MATCHED[@]} -ge 3 ] && break
done

# 매칭 없으면 침묵
[ ${#MATCHED[@]} -eq 0 ] && exit 0

# === 주입 출력 ===
echo "[📚 워크플로 컨텍스트 자동 로드]"
echo ""
echo "다음 워크플로 문서가 발화 키워드와 매칭되어 주입됨 (이번 세션 내 중복 주입 안 됨):"
echo ""

for f in "${MATCHED[@]}"; do
    echo "═══════════════════════════════════════════════════════════"
    echo "📄 ~/.claude/workflows/$f"
    echo "═══════════════════════════════════════════════════════════"
    /bin/cat "$WF_DIR/$f"
    echo ""
done

echo "─────────────────────────────────────────────"
echo "위 내용을 컨텍스트로 활용. 추가 Read 불필요."

exit 0
