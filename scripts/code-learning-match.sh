#!/usr/bin/env bash
# code-learning-match.sh
# 그래파이 그래프의 핵심 모듈/God Nodes와 학습 노트(Obsidian Vault) 매칭 분석.
# Usage: code-learning-match.sh <project_path>
# Example: code-learning-match.sh ~/Workspace/identity-hub

set -euo pipefail

# -----------------------------------------------------------------------------
# 0. 인자 검증
# -----------------------------------------------------------------------------
if [[ $# -lt 1 ]]; then
    echo "Usage: $0 <project_path>" >&2
    echo "Example: $0 ~/Workspace/identity-hub" >&2
    exit 2
fi

PROJECT_PATH="${1/#\~/$HOME}"
PROJECT_PATH="$(cd "$PROJECT_PATH" 2>/dev/null && pwd)" || {
    echo "ERROR: 프로젝트 경로를 찾을 수 없습니다: $1" >&2
    exit 2
}
PROJECT_NAME="$(basename "$PROJECT_PATH")"

GRAPH_JSON="$PROJECT_PATH/graphify-out/graph.json"
GRAPH_REPORT="$PROJECT_PATH/graphify-out/GRAPH_REPORT.md"
LEARNING_ROOT="$HOME/Workspace/weaversbrain/weaversbrain/Learning"

# -----------------------------------------------------------------------------
# 1. graph.json 존재 확인
# -----------------------------------------------------------------------------
if [[ ! -f "$GRAPH_JSON" ]]; then
    echo "ERROR: graphify-out/graph.json 이 없습니다: $GRAPH_JSON" >&2
    echo "먼저 'graphify ingest' 를 실행하세요." >&2
    exit 3
fi

if ! command -v jq >/dev/null 2>&1; then
    echo "ERROR: jq 가 필요합니다. 'brew install jq'" >&2
    exit 3
fi

# -----------------------------------------------------------------------------
# 2. 핵심 모듈 추출
#    - GRAPH_REPORT.md 의 'God Nodes' 섹션이 있으면 그것을 우선
#    - 없으면 graph.json 에서 link 차수 상위 노드 산출
# -----------------------------------------------------------------------------
TMPDIR_X="$(mktemp -d)"
trap 'rm -rf "$TMPDIR_X"' EXIT

GOD_NODES_FILE="$TMPDIR_X/god_nodes.txt"

if [[ -f "$GRAPH_REPORT" ]] && grep -q "^## God Nodes" "$GRAPH_REPORT"; then
    awk '
        /^## God Nodes/        {flag=1; next}
        /^## /                 {if (flag) flag=0}
        flag && /^[0-9]+\./    {
            # "1. `AuthService` - 156 edges" 형태에서 backtick 사이 추출
            match($0, /`[^`]+`/)
            if (RSTART > 0) {
                name = substr($0, RSTART+1, RLENGTH-2)
                # edges 숫자 추출
                edges = ""
                if (match($0, /- *[0-9]+/)) {
                    edges = substr($0, RSTART, RLENGTH)
                    gsub(/[^0-9]/, "", edges)
                }
                print name "\t" edges
            }
        }
    ' "$GRAPH_REPORT" > "$GOD_NODES_FILE"
    SOURCE_OF_TRUTH="GRAPH_REPORT.md (God Nodes 섹션)"
else
    # 폴백: link 차수 상위 노드를 jq로 산출
    jq -r '
        (.links | group_by(.source) | map({id: .[0].source, out: length})) as $out |
        (.links | group_by(.target) | map({id: .[0].target, in:  length})) as $in  |
        (.nodes | map({id, label})) as $nodes |
        ($out + $in)
        | group_by(.id)
        | map({id: .[0].id, deg: (map((.out // 0) + (.in // 0)) | add)})
        | sort_by(-.deg)
        | .[0:15]
        | map(. as $x | $nodes[] | select(.id == $x.id) | "\(.label)\t\($x.deg)")
        | .[]
    ' "$GRAPH_JSON" > "$GOD_NODES_FILE"
    SOURCE_OF_TRUTH="graph.json (link 차수 상위)"
fi

# 핵심 communities (전체 community 개수)
COMMUNITY_COUNT="$(jq -r '[.nodes[].community] | unique | length' "$GRAPH_JSON")"
NODE_COUNT="$(jq -r '.nodes | length' "$GRAPH_JSON")"
EDGE_COUNT="$(jq -r '.links | length' "$GRAPH_JSON")"

# -----------------------------------------------------------------------------
# 3. 학습 노트 색인
#    - $LEARNING_ROOT/**/*.md 에서 frontmatter tags + 본문 키워드 추출
#    - python으로 frontmatter 파싱 (yaml-like). 실패 시 grep 폴백
# -----------------------------------------------------------------------------
NOTES_INDEX="$TMPDIR_X/notes_index.tsv"   # 형식: <relative_path>\t<keywords joined by ,>

python3 - "$LEARNING_ROOT" "$NOTES_INDEX" <<'PY'
import os, re, sys, pathlib

root = pathlib.Path(sys.argv[1])
out_path = sys.argv[2]

# frontmatter 분리: 첫 줄이 ---로 시작하면 다음 ---까지를 frontmatter로 간주
def parse_note(p):
    try:
        text = p.read_text(encoding="utf-8", errors="ignore")
    except Exception:
        return set(), ""

    fm = ""
    body = text
    if text.startswith("---"):
        # 두 번째 ---까지 잘라냄
        m = re.search(r"^---\s*\n(.*?)\n---\s*\n", text, re.DOTALL)
        if m:
            fm = m.group(1)
            body = text[m.end():]

    # 메타/도구 문서 (type: learning-tool-doc 등) 는 매칭 대상에서 제외
    type_match = re.search(r"^type\s*:\s*(.+)$", fm, re.MULTILINE)
    if type_match:
        ntype = type_match.group(1).strip().strip('"').strip("'").lower()
        if ntype not in {"learning-note", "learning", "study"}:
            # 학습 노트가 아닌 메타 문서는 색인 제외
            return set(), ""

    keywords = set()

    # tags 추출: list 형식 ([a, b]) 또는 indent block (- a)
    # 1) flow style: tags: [a, b, c]
    for m in re.finditer(r"^tags\s*:\s*\[([^\]]+)\]", fm, re.MULTILINE):
        for raw in m.group(1).split(","):
            t = raw.strip().strip('"').strip("'")
            if t:
                keywords.add(t.lower())
    # 2) block style: tags:\n  - a\n  - b
    block = re.search(r"^tags\s*:\s*\n((?:\s+-\s+\S+.*\n?)+)", fm, re.MULTILINE)
    if block:
        for line in block.group(1).splitlines():
            mm = re.match(r"\s*-\s*(.+)$", line)
            if mm:
                t = mm.group(1).strip().strip('"').strip("'")
                if t:
                    keywords.add(t.lower())

    # topic / title / category / domain / project / related도 보조 키워드로
    for key in ("topic", "title", "category", "domain", "project"):
        for m in re.finditer(rf"^{key}\s*:\s*(.+)$", fm, re.MULTILINE):
            v = m.group(1).strip().strip('"').strip("'")
            if v:
                keywords.add(v.lower())
                # 단어 분해 (camelCase / 하이픈 / 공백)
                for token in re.split(r"[\s\-_/]+", v):
                    token = re.sub(r"[^a-zA-Z0-9가-힣]", "", token)
                    if len(token) >= 3:
                        keywords.add(token.lower())

    # related: list 형식
    for m in re.finditer(r"^related\s*:\s*\n((?:\s+-\s+\S+.*\n?)+)", fm, re.MULTILINE):
        for line in m.group(1).splitlines():
            mm = re.match(r"\s*-\s*(.+)$", line)
            if mm:
                v = mm.group(1).strip().strip('"').strip("'")
                if v:
                    keywords.add(v.lower())

    # 본문 백틱 코드명도 보조 키워드 (상위 30개)
    code_tokens = re.findall(r"`([A-Za-z_][A-Za-z0-9_\.]{2,})`", body)
    for t in code_tokens[:30]:
        keywords.add(t.lower())

    # 파일명 자체에서 단어 분해
    for token in re.split(r"[\s\-_/]+", p.stem):
        token = re.sub(r"[^a-zA-Z0-9가-힣]", "", token)
        if len(token) >= 3 and not token.isdigit():
            keywords.add(token.lower())

    return keywords, body[:200]

with open(out_path, "w", encoding="utf-8") as out:
    if not root.exists():
        sys.exit(0)
    for p in sorted(root.rglob("*.md")):
        try:
            rel = p.relative_to(root)
        except ValueError:
            rel = p
        kw, _ = parse_note(p)
        if kw:
            out.write(f"{rel}\t{','.join(sorted(kw))}\n")
PY

NOTE_TOTAL="$(wc -l < "$NOTES_INDEX" | tr -d ' ')"

# -----------------------------------------------------------------------------
# 4. God Node ↔ 학습 노트 매칭
#    매칭 룰: God node 이름을 소문자/카멜→하이픈/공백 으로 정규화 → 노트 키워드와 부분 일치
# -----------------------------------------------------------------------------
MATCH_TSV="$TMPDIR_X/match.tsv"

python3 - "$GOD_NODES_FILE" "$NOTES_INDEX" "$MATCH_TSV" <<'PY'
import re, sys, pathlib

god_path  = sys.argv[1]
note_path = sys.argv[2]
out_path  = sys.argv[3]

# 너무 일반적이라 매칭 노이즈가 되는 토큰
STOPWORDS = {
    "service", "services", "client", "clients", "manager", "handler",
    "controller", "config", "configs", "context", "request", "response",
    "error", "exception", "factory", "helper", "util", "utils",
    "model", "models", "schema", "schemas", "data", "info", "value",
    "test", "tests", "code", "type", "name", "id", "main", "app",
    "module", "package", "function", "method", "class", "object",
    "base", "common", "core", "default", "abstract", "impl",
}

def normalize(name):
    # AuthService -> 의미있는 토큰만 (auth, oauth, jwt 등) — service/error 같은 stopword 제외
    name = name.strip()
    tokens = set()
    full = name.lower()

    # camelCase / PascalCase 분리
    parts = re.findall(r"[A-Z]?[a-z0-9]+|[A-Z]+(?=[A-Z]|$)", name)
    parts = [p.lower() for p in parts if p]

    # 의미있는 토큰만 (길이 >= 4 + stopword 제외)
    meaningful = [p for p in parts if len(p) >= 4 and p not in STOPWORDS]

    # 의미있는 토큰이 없으면 매칭 후보 자체에서 제외 (빈 set 반환)
    if not meaningful:
        return set()

    for p in meaningful:
        tokens.add(p)

    # 풀 네임도 보조 토큰 (정확 매칭용)
    if len(full) >= 5:
        tokens.add(full)

    # 도메인성 약어 보강
    synonyms_map = {
        "oauth":   {"oauth", "oauth2", "oidc"},
        "oidc":    {"oauth", "oauth2", "oidc"},
        "jwt":     {"jwt", "jwks"},
        "auth":    {"auth", "authn", "authentication"},
        "session": {"session"},
        "cache":   {"cache", "caching"},
        "keycloak":{"keycloak", "kc"},
        "pkce":    {"pkce"},
        "redis":   {"redis", "cache"},
    }
    extra = set()
    for tok in list(tokens):
        if tok in synonyms_map:
            extra |= synonyms_map[tok]
    tokens |= extra
    return tokens

# 노트 색인 로드
notes = []  # [(relpath, set(keywords))]
with open(note_path, encoding="utf-8") as f:
    for line in f:
        rel, _, kw = line.rstrip("\n").partition("\t")
        notes.append((rel, set(k for k in kw.split(",") if k)))

# 매칭
with open(out_path, "w", encoding="utf-8") as out:
    with open(god_path, encoding="utf-8") as f:
        for line in f:
            line = line.rstrip("\n")
            if not line:
                continue
            name, _, deg = line.partition("\t")
            tokens = normalize(name)
            hits = []
            if not tokens:
                # 의미있는 토큰이 없는 모듈은 매칭 시도 자체를 스킵 (예: ServiceUnavailableError)
                out.write(f"{name}\t{deg}\t\n")
                continue
            for rel, kws in notes:
                # 정확 일치만 인정 (부분 substring 매칭 제거 → 노이즈 차단)
                if tokens & kws:
                    hits.append(rel)
            out.write(f"{name}\t{deg}\t{'|'.join(hits)}\n")
PY

# -----------------------------------------------------------------------------
# 5. 출력 (마크다운 표 + 추천)
# -----------------------------------------------------------------------------
echo
echo "# Code ↔ Learning Match Report"
echo
echo "- 프로젝트: \`$PROJECT_NAME\` (\`$PROJECT_PATH\`)"
echo "- Graph: $NODE_COUNT nodes, $EDGE_COUNT edges, $COMMUNITY_COUNT communities"
echo "- 학습 노트 색인: $NOTE_TOTAL 건 (\`$LEARNING_ROOT\`)"
echo "- 핵심 모듈 출처: $SOURCE_OF_TRUTH"
echo
echo "## 핵심 모듈 ↔ 학습 노트 매칭"
echo
echo "| # | 모듈 (God Node) | 차수 | 학습 노트 매칭 |"
echo "|---|----------------|------|--------------|"

idx=0
gap_count=0
hit_count=0
GAP_LIST="$TMPDIR_X/gap_list.txt"
: > "$GAP_LIST"

while IFS=$'\t' read -r name deg hits; do
    [[ -z "$name" ]] && continue
    idx=$((idx+1))
    if [[ -z "$hits" ]]; then
        cell="X 학습 안 함"
        echo "$name" >> "$GAP_LIST"
        gap_count=$((gap_count+1))
    else
        IFS='|' read -ra arr <<< "$hits"
        links=()
        for h in "${arr[@]}"; do
            base="$(basename "$h" .md)"
            uri_path="Learning/${h}"
            uri_path_no_ext="${uri_path%.md}"
            # URL 인코딩 (공백/한글 등) — python으로 처리
            encoded="$(python3 -c 'import urllib.parse,sys; print(urllib.parse.quote(sys.argv[1]))' "$uri_path_no_ext")"
            links+=("[$base](obsidian://open?vault=weaversbrain&file=$encoded)")
        done
        # 표 셀 안에서 파이프 회피
        joined="$(IFS=' / '; echo "${links[*]}")"
        cell="$joined"
        hit_count=$((hit_count+1))
    fi
    echo "| $idx | \`$name\` | ${deg:-?} | $cell |"
done < "$MATCH_TSV"

echo
echo "## 학습 갭 (이 모듈을 만지면 학습할 거리)"
echo
if [[ "$gap_count" -eq 0 ]]; then
    echo "_핵심 모듈 모두 학습 노트 보유. 좋습니다._"
else
    echo "다음 ${gap_count}개 모듈은 아직 학습 노트가 없습니다. 코드 만지기 전에 \`/deep-learn\` 큐에 등록 권장:"
    echo
    while read -r name; do
        [[ -z "$name" ]] && continue
        # 학습 주제 제안 (단순 휴리스틱)
        suggestion="$name 의 책임/의존성/오용 패턴 정리"
        case "$name" in
            *Service)        suggestion="$name 의 책임 경계, DI 그래프, 호출 시퀀스" ;;
            *Error|*Exception) suggestion="$name 가 발생하는 분기와 상위 핸들러 매핑" ;;
            *Cache*|*Redis*) suggestion="$name 키 네이밍/TTL/무효화 전략" ;;
            *OAuth*|*OIDC*)  suggestion="$name 의 PKCE/state/nonce/JWKS 검증 흐름" ;;
            *Session*)       suggestion="$name 라이프사이클/스토리지/만료 정책" ;;
            *JWT*|*Token*)   suggestion="$name 발급·검증 경로, 키 회전, 캐시 폴백" ;;
        esac
        echo "- [ ] \`$name\` → $suggestion"
    done < "$GAP_LIST"
fi

echo
echo "## 요약"
echo
total=$((hit_count + gap_count))
if [[ "$total" -gt 0 ]]; then
    pct=$(( hit_count * 100 / total ))
else
    pct=0
fi
echo "- 매칭: ${hit_count}/${total} (${pct}%)"
echo "- 갭: ${gap_count}건"
echo "- 권장: 코드 수정 전 갭 항목 학습 → 수정 → \`/deep-learn\` 으로 학습 노트화"
