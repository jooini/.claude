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

# === 주입 출력 (포인터 방식 — 전문 cat 금지) ===
# 배경: 전문 cat 주입은 발화당 최대 ~7500tok(pipeline.md+standard-routines.md 등)을
#   쏟아부어 컨텍스트를 오염시키고 도구 직렬화를 저하시킴(2026-05-31 실측).
#   라우팅 룰 인지는 "경로 포인터 + 1줄 핵심"으로 충분. 정말 필요하면 Claude가 Read.
#   세션 1회 중복방지 캐시는 그대로 유지(위 CACHE_FILE 로직).

# 파일별 1줄 핵심 요약 (룰 인지용 — 키워드만으로 무슨 룰인지 알게)
summarize() {
    case "$1" in
        codex.md)             echo "Codex CLI 호출 규약(codex exec, codex: 명령)" ;;
        sso.md)               echo "SSO/Identity Hub/BFF 연동 컨텍스트" ;;
        debugging.md)         echo "7단계 디버깅 절차(추측금지, 2회실패 재검토, 3회 rescue)" ;;
        llm-routing.md)       echo "Gemma/Gemini/Codex/Ollama 라우팅 규약" ;;
        docs-convention.md)   echo "Obsidian Vault 문서 작성 규칙(파일명/frontmatter/링크)" ;;
        coding-convention.md) echo "코딩 컨벤션(공백4칸, 약어금지, FastAPI Annotated)" ;;
        pipeline.md)          echo "backend/frontend/fullstack 파이프라인 단계" ;;
        standard-routines.md) echo "TYPE A~G 표준 루틴(feature/bugfix/refactor/design/data/ops/docs)" ;;
        automation.md)        echo "hook 자동화/메트릭/규모판별 동작" ;;
        growth.md)            echo "학습/회고/3중 LLM 성장 루프" ;;
        projects.md)          echo "프로젝트 목록/스택/위치" ;;
        *)                    echo "워크플로 룰" ;;
    esac
}

echo "[📚 워크플로 룰 적용 대상 — 키워드 매칭]"
echo "이 발화는 아래 룰 적용 대상. 핵심은 요약대로. 세부 필요 시에만 해당 경로 Read:"
for f in "${MATCHED[@]}"; do
    echo "  • ~/.claude/workflows/$f — $(summarize "$f")"
done

exit 0
