#!/usr/bin/env bash
# learning-to-anki.sh
# 학습 노트(마크다운)를 Anki Q/A 카드(마크다운 + CSV)로 변환한다.
# 단일 파일 또는 디렉토리 모드 지원.
#
# 사용법:
#   learning-to-anki.sh <노트파일.md>             # 단일 파일 (기본)
#   learning-to-anki.sh <디렉토리>                # 일괄 처리 (사용자 명시 시에만)
#   OUT_DIR=/path/to/out learning-to-anki.sh ...  # 출력 디렉토리 오버라이드
#
# 의존성: codex CLI, jq, python3
set -euo pipefail

# ---------- 인자 검증 ----------
if [[ $# -lt 1 ]]; then
    echo "사용법: $0 <노트파일.md | 디렉토리>" >&2
    exit 1
fi

INPUT="$1"
NUM_CARDS="${NUM_CARDS:-8}"

if [[ ! -e "$INPUT" ]]; then
    echo "[ERR] 입력 경로 없음: $INPUT" >&2
    exit 1
fi

# 출력 디렉토리: 입력 노트가 있는 Learning/.../{file} 기준으로 형제 anki/ 디렉토리에 저장
default_out_dir() {
    local note_path="$1"
    local note_dir
    note_dir="$(cd "$(dirname "$note_path")" && pwd)"
    # Learning/2026-05/ -> Learning/anki/
    if [[ "$note_dir" == */Learning/* ]]; then
        local base="${note_dir%/Learning/*}"
        echo "$base/Learning/anki"
    else
        echo "$note_dir/anki"
    fi
}

# ---------- 의존성 체크 ----------
for cmd in codex jq python3; do
    if ! command -v "$cmd" >/dev/null 2>&1; then
        echo "[ERR] 의존성 누락: $cmd" >&2
        exit 1
    fi
done

# ---------- 코어: 노트 1개 처리 ----------
process_one() {
    local note_path="$1"
    local idx="${2:-1}"
    local total="${3:-1}"

    local note_abs
    note_abs="$(cd "$(dirname "$note_path")" && pwd)/$(basename "$note_path")"

    local out_dir="${OUT_DIR:-$(default_out_dir "$note_abs")}"
    mkdir -p "$out_dir"

    local base_name
    base_name="$(basename "$note_path" .md)"
    local md_out="$out_dir/${base_name}-cards.md"
    local csv_out="$out_dir/${base_name}-cards.csv"
    local raw_out="$out_dir/.${base_name}-cards.raw"
    local json_out="$out_dir/.${base_name}-cards.json"

    echo "[$idx/$total] $base_name 처리 중 ..."

    # ---------- Codex 호출 ----------
    # 노트 내용을 stdin이 아닌 인자에 직접 임베드 (codex exec 특성상 prompt 단일 인자)
    # 너무 큰 노트는 잘릴 수 있으니 16KB 제한
    local note_body
    note_body="$(head -c 16000 "$note_path")"

    local prompt
    prompt=$(cat <<PROMPT
다음 학습 노트를 기반으로 Anki 복습용 Q/A 카드 ${NUM_CARDS}장을 생성해라.

요구사항:
1. 출력은 **반드시 JSON 배열만** 출력. 다른 텍스트, 코드펜스, 주석, 마크다운 금지.
2. 형식: [{"q": "질문", "a": "답변"}, ...]
3. 카드 ${NUM_CARDS}장 정확히 생성.
4. 질문은 구체적이고 단답형/짧은 서술형이 가능한 형태. 답변은 1-3문장.
5. 노트의 핵심 개념·예시·함정·차이점을 골고루 커버.
6. 한국어로 작성 (코드/영문 용어는 그대로).

학습 노트:
---
${note_body}
---

JSON 배열만 출력해라.
PROMPT
)

    # codex exec 실행 (timeout 방어)
    if ! (cd "$HOME/.claude" && codex exec --skip-git-repo-check "$prompt") > "$raw_out" 2>/dev/null; then
        echo "  [WARN] codex exec 실패 — raw 출력 보관: $raw_out" >&2
    fi

    # ---------- JSON 추출 (견고한 파싱) ----------
    # python3로 첫 번째 JSON 배열 [ ... ] 블록을 추출 (대괄호 균형 매칭)
    if ! python3 - "$raw_out" "$json_out" <<'PYEOF'
import json
import re
import sys

raw_path, json_path = sys.argv[1], sys.argv[2]
with open(raw_path, "r", encoding="utf-8", errors="replace") as f:
    text = f.read()

# 1) 코드펜스 제거 시도
text2 = re.sub(r"```(?:json)?\s*", "", text)
text2 = re.sub(r"```", "", text2)

# 2) 첫 '['부터 균형 잡힌 ']'까지 추출
def extract_first_array(s: str):
    start = s.find("[")
    while start != -1:
        depth = 0
        in_str = False
        esc = False
        for i in range(start, len(s)):
            ch = s[i]
            if in_str:
                if esc:
                    esc = False
                elif ch == "\\":
                    esc = True
                elif ch == '"':
                    in_str = False
                continue
            if ch == '"':
                in_str = True
            elif ch == "[":
                depth += 1
            elif ch == "]":
                depth -= 1
                if depth == 0:
                    return s[start:i+1]
        start = s.find("[", start + 1)
    return None

candidate = extract_first_array(text2) or extract_first_array(text)

cards = None
if candidate:
    try:
        cards = json.loads(candidate)
    except Exception:
        # 후행 콤마 등 흔한 문제 보정
        fixed = re.sub(r",\s*([\]}])", r"\1", candidate)
        try:
            cards = json.loads(fixed)
        except Exception:
            cards = None

if not isinstance(cards, list) or not cards:
    print("[ERR] JSON 배열 추출 실패", file=sys.stderr)
    sys.exit(2)

# 정규화: q/a 키 강제, 누락 시 빈 문자열
norm = []
for c in cards:
    if isinstance(c, dict):
        q = str(c.get("q") or c.get("question") or c.get("Q") or "").strip()
        a = str(c.get("a") or c.get("answer") or c.get("A") or "").strip()
        if q and a:
            norm.append({"q": q, "a": a})

if not norm:
    print("[ERR] 유효한 q/a 카드 없음", file=sys.stderr)
    sys.exit(3)

with open(json_path, "w", encoding="utf-8") as f:
    json.dump(norm, f, ensure_ascii=False, indent=2)

print(f"[OK] {len(norm)} 카드 추출")
PYEOF
    then
        echo "  [ERR] $base_name JSON 파싱 실패. raw 보관: $raw_out" >&2
        return 1
    fi

    # ---------- 마크다운 출력 ----------
    python3 - "$json_out" "$md_out" "$base_name" <<'PYEOF'
import json
import sys

json_path, md_path, base_name = sys.argv[1], sys.argv[2], sys.argv[3]
with open(json_path, encoding="utf-8") as f:
    cards = json.load(f)

lines = []
lines.append("---")
lines.append("type: anki-cards")
lines.append(f"source: {base_name}.md")
lines.append(f"count: {len(cards)}")
lines.append("tags: [anki, learning, qa]")
lines.append("---")
lines.append("")
lines.append(f"# Anki Cards — {base_name}")
lines.append("")
for i, c in enumerate(cards, 1):
    lines.append(f"## Q{i}. {c['q']}")
    lines.append("")
    lines.append(c["a"])
    lines.append("")
    lines.append("---")
    lines.append("")

with open(md_path, "w", encoding="utf-8") as f:
    f.write("\n".join(lines))
PYEOF

    # ---------- CSV 출력 (Anki 임포트용) ----------
    # Anki "텍스트 파일에서 가져오기": 탭 또는 콤마 구분, 필드 순서 = Front,Back
    # 안전을 위해 RFC 4180 CSV 사용 (콤마/줄바꿈/따옴표 이스케이프)
    python3 - "$json_out" "$csv_out" <<'PYEOF'
import csv
import json
import sys

json_path, csv_path = sys.argv[1], sys.argv[2]
with open(json_path, encoding="utf-8") as f:
    cards = json.load(f)

with open(csv_path, "w", encoding="utf-8", newline="") as f:
    # Anki는 헤더 없이 임포트 가능. #separator:Comma 메타 헤더로 명시.
    f.write("#separator:Comma\n")
    f.write("#html:false\n")
    f.write("#columns:Front,Back\n")
    writer = csv.writer(f, quoting=csv.QUOTE_MINIMAL)
    for c in cards:
        writer.writerow([c["q"], c["a"]])
PYEOF

    # 정리: 임시 raw/json 보관 (디버깅용으로 그대로 둠)
    echo "  [OK] $md_out"
    echo "  [OK] $csv_out"
}

# ---------- 메인 분기 ----------
if [[ -d "$INPUT" ]]; then
    # 디렉토리 모드 — 사용자 명시 트리거
    echo "[INFO] 디렉토리 모드: $INPUT"
    mapfile -t notes < <(find "$INPUT" -maxdepth 1 -type f -name "*.md" | sort)
    total=${#notes[@]}
    if [[ $total -eq 0 ]]; then
        echo "[ERR] .md 파일 없음" >&2
        exit 1
    fi
    echo "[INFO] $total 개 노트 처리"
    i=0
    fail=0
    for note in "${notes[@]}"; do
        i=$((i+1))
        if ! process_one "$note" "$i" "$total"; then
            fail=$((fail+1))
        fi
    done
    echo "[DONE] 성공 $((total-fail))/$total, 실패 $fail"
    [[ $fail -eq 0 ]] || exit 1
elif [[ -f "$INPUT" ]]; then
    process_one "$INPUT" 1 1
else
    echo "[ERR] 파일도 디렉토리도 아님: $INPUT" >&2
    exit 1
fi
