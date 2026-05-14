#!/usr/bin/env bash
# decision-learning-link.sh
#
# 결정 노트(decisions/)와 학습 노트(Learning/)를 매칭해 연결 표를 출력한다.
# 매칭 휴리스틱: (1) 공통 태그, (2) 제목 키워드, (3) 결정일 +/- 7일 학습 노트.
#
# 출력:
#   - CLI 표 (결정 ↔ 학습 노트 페어)
#   - --json 옵션: JSON 출력 (Dataview/외부 도구용)
#   - --markdown 옵션: 마크다운 표 출력 (decision-link.md 임베드용)
#
# 사용:
#   decision-learning-link.sh
#   decision-learning-link.sh --markdown > out.md
#   decision-learning-link.sh --json > out.json

set -euo pipefail

VAULT="${HOME}/Workspace/weaversbrain/weaversbrain"
DECISIONS_DIR="${VAULT}/decisions"
LEARNING_DIR="${VAULT}/Learning"

MODE="cli"
case "${1:-}" in
    --json) MODE="json" ;;
    --markdown|--md) MODE="markdown" ;;
    --help|-h)
        sed -n '2,16p' "$0"
        exit 0
        ;;
esac

# Vault 내에서 frontmatter에 type:decision 또는 meta-decision, 또는 tags에 decision이 있는 파일 수집
# decisions/ 디렉토리도 포함 (자동 캡처분).
collect_decision_files() {
    {
        if [ -d "$DECISIONS_DIR" ]; then
            find "$DECISIONS_DIR" -type f -name "*.md" ! -name "INDEX.md" 2>/dev/null
        fi
        # frontmatter 기반 추가 결정 노트 (vault 어디든)
        grep -l -E "^type:[[:space:]]*(decision|meta-decision)" -r "$VAULT" --include="*.md" 2>/dev/null || true
        grep -l -E "^tags:.*\bdecision\b" -r "$VAULT" --include="*.md" 2>/dev/null || true
    } | sort -u | grep -v -E "(decision-link\.md|/dashboard\.md|/learning-queue.*\.md|/INDEX\.md)$" || true
}

collect_learning_files() {
    if [ -d "$LEARNING_DIR" ]; then
        find "$LEARNING_DIR" -type f -name "*.md" \
            ! -name "dashboard.md" \
            ! -name "learning-queue*.md" \
            ! -name "decision-link.md" \
            2>/dev/null
    fi
}

# 한 파일에서 (date, title, tags, basename) 추출
# 출력: TAB 구분: filepath \t date \t title_keywords \t tags
extract_meta() {
    local f="$1"
    /usr/bin/python3 - "$f" <<'PY'
import sys, re, os
fp = sys.argv[1]
try:
    with open(fp, 'r', encoding='utf-8', errors='ignore') as fh:
        head = fh.read(4096)
except Exception:
    sys.exit(0)

# YAML frontmatter 추출
fm = {}
m = re.match(r'^---\n(.*?)\n---', head, re.DOTALL)
if m:
    body = m.group(1)
    for line in body.split('\n'):
        mm = re.match(r'^([\w_-]+):\s*(.*)$', line)
        if mm:
            fm[mm.group(1).strip()] = mm.group(2).strip()

# 날짜 추출: frontmatter > 파일명 > mtime
date = fm.get('date', '') or fm.get('created', '')
date = date.strip('"').strip("'")
if not re.match(r'^\d{4}-\d{2}-\d{2}', date):
    base = os.path.basename(fp)
    mb = re.match(r'(\d{4}-\d{2}-\d{2})', base)
    date = mb.group(1) if mb else ''

# 제목 키워드: title 필드 또는 파일명에서 토큰화
title = fm.get('title', '') or fm.get('topic', '')
title = title.strip('"').strip("'")
if not title:
    base = os.path.basename(fp).replace('.md', '')
    # YYYY-MM-DD-HHMM- 또는 YYYY-MM-DD- 접두사 제거
    title = re.sub(r'^\d{4}-\d{2}-\d{2}(-\d{4})?-?', '', base)

# 키워드: 영숫자/한글 토큰 (3자 이상)
tokens = re.findall(r'[\w가-힣]+', title.lower())
tokens = [t for t in tokens if len(t) >= 3]
keywords = ','.join(tokens)

# 태그
tags_raw = fm.get('tags', '')
tags = re.findall(r'[\w가-힣-]+', tags_raw.lower())
tags = ','.join([t for t in tags if t not in ('tags',)])

print(f"{fp}\t{date}\t{keywords}\t{tags}")
PY
}

# decision -> learning 매칭
# - 공통 키워드 1개 이상 OR 공통 태그 1개 이상 (decision/auto-capture/learning 같은 메타 태그 제외)
# - 또는 날짜가 +/- 7일 이내 (약한 매칭, 보조)
match_score() {
    /usr/bin/python3 - "$1" "$2" "$3" "$4" "$5" "$6" <<'PY'
import sys
from datetime import date

d_date, d_kw, d_tags, l_date, l_kw, l_tags = sys.argv[1:7]

META_TAGS = {'decision', 'auto-capture', 'learning', 'learning-note', 'meta-decision'}

d_keywords = set(d_kw.split(',')) - {''}
l_keywords = set(l_kw.split(',')) - {''}
d_tagset   = set(d_tags.split(',')) - META_TAGS - {''}
l_tagset   = set(l_tags.split(',')) - META_TAGS - {''}

kw_overlap  = d_keywords & l_keywords
tag_overlap = d_tagset & l_tagset

score = 0
reasons = []
if kw_overlap:
    score += 2 * len(kw_overlap)
    reasons.append(f"keywords:{','.join(sorted(kw_overlap))[:60]}")
if tag_overlap:
    score += 3 * len(tag_overlap)
    reasons.append(f"tags:{','.join(sorted(tag_overlap))[:60]}")

# 날짜 보조 매칭
if d_date and l_date:
    try:
        dd = date.fromisoformat(d_date[:10])
        ll = date.fromisoformat(l_date[:10])
        delta = abs((ll - dd).days)
        if delta <= 7 and score > 0:
            score += 1
            reasons.append(f"within{delta}d")
        elif delta <= 7 and score == 0:
            # 단독으로는 약함 — 매칭 안 함
            pass
    except Exception:
        pass

if score == 0:
    sys.exit(1)

print(f"{score}\t{'; '.join(reasons)}")
PY
}

# 메인
DECISIONS=$(collect_decision_files)
LEARNINGS=$(collect_learning_files)

DEC_COUNT=$(echo "$DECISIONS" | grep -c . || true)
LEARN_COUNT=$(echo "$LEARNINGS" | grep -c . || true)

# 메타 추출
TMP_DEC=$(mktemp)
TMP_LEARN=$(mktemp)
trap 'rm -f "$TMP_DEC" "$TMP_LEARN"' EXIT

if [ "$DEC_COUNT" -gt 0 ]; then
    while IFS= read -r f; do
        [ -z "$f" ] && continue
        extract_meta "$f"
    done <<< "$DECISIONS" > "$TMP_DEC"
fi

if [ "$LEARN_COUNT" -gt 0 ]; then
    while IFS= read -r f; do
        [ -z "$f" ] && continue
        extract_meta "$f"
    done <<< "$LEARNINGS" > "$TMP_LEARN"
fi

# 매칭 수행
MATCHES_TSV=$(mktemp)
ORPHAN_DECISIONS=$(mktemp)
trap 'rm -f "$TMP_DEC" "$TMP_LEARN" "$MATCHES_TSV" "$ORPHAN_DECISIONS"' EXIT

while IFS=$'\t' read -r d_path d_date d_kw d_tags; do
    [ -z "$d_path" ] && continue
    matched=0
    while IFS=$'\t' read -r l_path l_date l_kw l_tags; do
        [ -z "$l_path" ] && continue
        if result=$(match_score "$d_date" "$d_kw" "$d_tags" "$l_date" "$l_kw" "$l_tags" 2>/dev/null); then
            score=$(echo "$result" | cut -f1)
            reason=$(echo "$result" | cut -f2)
            printf "%s\t%s\t%s\t%s\t%s\n" "$score" "$d_path" "$l_path" "$d_date" "$reason" >> "$MATCHES_TSV"
            matched=1
        fi
    done < "$TMP_LEARN"
    if [ "$matched" -eq 0 ]; then
        printf "%s\t%s\n" "$d_path" "$d_date" >> "$ORPHAN_DECISIONS"
    fi
done < "$TMP_DEC"

# 점수 내림차순 정렬
SORTED_MATCHES=$(sort -t$'\t' -k1,1 -nr "$MATCHES_TSV" 2>/dev/null || true)
PAIR_COUNT=$(echo "$SORTED_MATCHES" | grep -c . || true)
ORPHAN_COUNT=$(grep -c . "$ORPHAN_DECISIONS" 2>/dev/null || echo 0)

case "$MODE" in
    json)
        /usr/bin/python3 - "$VAULT" "$MATCHES_TSV" "$ORPHAN_DECISIONS" "$DEC_COUNT" "$LEARN_COUNT" <<'PY'
import sys, json, os
vault, mfile, ofile, dc, lc = sys.argv[1:6]
out = {
    "vault": vault,
    "decision_count": int(dc),
    "learning_count": int(lc),
    "pairs": [],
    "orphan_decisions": [],
}
def rel(p): return p.replace(vault + '/', '')
try:
    with open(mfile) as f:
        rows = []
        for line in f:
            parts = line.rstrip('\n').split('\t')
            if len(parts) < 5: continue
            rows.append({
                "score": int(parts[0]),
                "decision": rel(parts[1]),
                "learning": rel(parts[2]),
                "decision_date": parts[3],
                "reasons": parts[4],
            })
        rows.sort(key=lambda r: -r["score"])
        out["pairs"] = rows
except FileNotFoundError:
    pass
try:
    with open(ofile) as f:
        for line in f:
            parts = line.rstrip('\n').split('\t')
            if len(parts) >= 1 and parts[0]:
                out["orphan_decisions"].append({"decision": rel(parts[0]), "date": parts[1] if len(parts) > 1 else ""})
except FileNotFoundError:
    pass
print(json.dumps(out, ensure_ascii=False, indent=2))
PY
        ;;
    markdown)
        echo "## 결정 ↔ 학습 매칭"
        echo
        echo "- 결정 노트: ${DEC_COUNT}개"
        echo "- 학습 노트: ${LEARN_COUNT}개"
        echo "- 매칭된 페어: ${PAIR_COUNT}개"
        echo "- 학습 없는 결정: ${ORPHAN_COUNT}개"
        echo
        if [ -n "$SORTED_MATCHES" ]; then
            echo "| 점수 | 결정 | 학습 | 매칭 근거 |"
            echo "|---:|---|---|---|"
            while IFS=$'\t' read -r score d_path l_path d_date reason; do
                [ -z "$d_path" ] && continue
                d_rel="${d_path#${VAULT}/}"
                l_rel="${l_path#${VAULT}/}"
                d_name=$(basename "$d_path" .md)
                l_name=$(basename "$l_path" .md)
                echo "| ${score} | [[${d_rel%.md}\\|${d_name}]] | [[${l_rel%.md}\\|${l_name}]] | ${reason} |"
            done <<< "$SORTED_MATCHES"
            echo
        fi
        if [ "$ORPHAN_COUNT" -gt 0 ]; then
            echo "## 학습 없는 결정 (위험)"
            echo
            while IFS=$'\t' read -r d_path d_date; do
                [ -z "$d_path" ] && continue
                d_rel="${d_path#${VAULT}/}"
                d_name=$(basename "$d_path" .md)
                echo "- [[${d_rel%.md}\\|${d_name}]] (${d_date})"
            done < "$ORPHAN_DECISIONS"
            echo
        fi
        ;;
    cli|*)
        printf '\n=== Decision <-> Learning Link Report ===\n'
        printf 'Vault          : %s\n' "$VAULT"
        printf 'Decision notes : %s\n' "$DEC_COUNT"
        printf 'Learning notes : %s\n' "$LEARN_COUNT"
        printf 'Matched pairs  : %s\n' "$PAIR_COUNT"
        printf 'Orphan decisions (no learning) : %s\n\n' "$ORPHAN_COUNT"
        if [ -n "$SORTED_MATCHES" ]; then
            printf '%-5s | %-50s | %-50s | %s\n' "Score" "Decision" "Learning" "Reason"
            printf '%s\n' "------+----------------------------------------------------+----------------------------------------------------+-----------------"
            while IFS=$'\t' read -r score d_path l_path d_date reason; do
                [ -z "$d_path" ] && continue
                d_short=$(basename "$d_path")
                l_short=$(basename "$l_path")
                # 길이 제한
                d_short=${d_short:0:50}
                l_short=${l_short:0:50}
                printf '%-5s | %-50s | %-50s | %s\n' "$score" "$d_short" "$l_short" "$reason"
            done <<< "$SORTED_MATCHES"
            printf '\n'
        fi
        if [ "$ORPHAN_COUNT" -gt 0 ]; then
            printf '\n--- Orphan decisions (no matched learning note) ---\n'
            while IFS=$'\t' read -r d_path d_date; do
                [ -z "$d_path" ] && continue
                printf '  [%s] %s\n' "$d_date" "$(basename "$d_path")"
            done < "$ORPHAN_DECISIONS"
        fi
        ;;
esac
