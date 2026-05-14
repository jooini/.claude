#!/bin/zsh
# UserPromptSubmit: 발화 features 추출 → qq rules.json 매칭 → 임계값 초과 시 stderr 경고
#
# 데이터 출처:
#   ~/.claude/cache/question-quality-rules.json (qq skill 산출물)
#
# 임계 룰: BAD rate ≥ 11% 인 feature 1개라도 hit → 경고
#
# 효과: 짧음/모호/지시대명사/구체성0 발화 시 사용자에게 "이 패턴 정정 N% 유발" 경고

: "${HOME:?}"

INPUT=$(cat)
PROMPT=$(echo "$INPUT" | python3 -c "import json,sys; d=json.load(sys.stdin); print(d.get('prompt',''))" 2>/dev/null)
[ -z "$PROMPT" ] && exit 0

PROMPT_LEN=${#PROMPT}
RULES=$HOME/.claude/cache/question-quality-rules.json
[ ! -f "$RULES" ] && exit 0

# 슬래시 명령어 / 코드 / URL 시작 → 스킵
echo "$PROMPT" | grep -qE '^(/|`|http|cd |ls |```)' && exit 0

# Python 한 방으로 features 추출 + rules 매칭 (zsh regex보다 정확)
python3 - "$PROMPT" "$RULES" <<'PY' 2>/dev/null
import json, re, sys

prompt = sys.argv[1]
rules_path = sys.argv[2]
with open(rules_path) as f:
    rules = json.load(f)

n_chars = len(prompt)
ambiguous = re.compile(r"\b(좀|그냥|아무거나|알아서|적당히|뭐|뭐든|어떻게든|대충|maybe|kinda|whatever)\b")
deixis = re.compile(r"(그것|이것|저것|거기|저기|아까|저번에|그거|이거|that|this|it)")
concrete = re.compile(r"[/\\]|\.[a-z]+\b|[A-Z][a-zA-Z]{2,}|`[^`]+`|[0-9]+")

hits = []
if n_chars < 5 and rules.get("very_short_bad_rate", 0) >= 0.05:
    hits.append(("매우 짧음 (<5자)", rules["very_short_bad_rate"]))
if ambiguous.search(prompt) and rules.get("ambiguous_bad_rate", 0) >= 0.10:
    hits.append(("모호 키워드 (좀/그냥/알아서)", rules["ambiguous_bad_rate"]))
if deixis.search(prompt) and rules.get("deixis_bad_rate", 0) >= 0.10:
    hits.append(("지시대명사 (그거/거기/아까)", rules["deixis_bad_rate"]))
if not concrete.search(prompt) and rules.get("no_concrete_bad_rate", 0) >= 0.10:
    hits.append(("구체성 0 (파일경로/숫자 없음)", rules["no_concrete_bad_rate"]))

if not hits:
    sys.exit(0)

# 발화 자체가 너무 길면 (>120자) 모호도 신호 약함 — 스킵
if n_chars > 120:
    sys.exit(0)

# 가장 높은 BAD rate 1개만 노출 (소음 방지)
hits.sort(key=lambda kv: kv[1], reverse=True)
top_label, top_rate = hits[0]
combined_pct = int(top_rate * 100)

# 발화 직전 경고 — UserPromptSubmit hook은 stderr 출력하면 사용자에게 안 보임,
# stdout으로 nudge 주입
print(f"[💬 발화 패턴 알림] {top_label} → 과거 정정률 {combined_pct}% (qq 1699 메시지 기준)")
if len(hits) > 1:
    print(f"   추가 hit: {', '.join(h[0] for h in hits[1:])}")
print(f"   → 한 줄 더 명확히 쓰면 다음 5턴 안전. 또는 그대로 진행하면 검증 강화 모드.")
PY

exit 0
