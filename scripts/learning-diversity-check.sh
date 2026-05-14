#!/bin/zsh
# 학습 도메인 편식 진단 스크립트
# 사용: ~/.claude/scripts/learning-diversity-check.sh [json|table|both]
#       기본값: both (JSON + 사람 읽는 표)
# 동작: Learning/ 하위 모든 .md 스캔 → frontmatter tags 분석 → 9개 도메인별 노트 수
#       0개 도메인 또는 30일 이상 미학습 도메인 식별

set -e

LEARNING_DIR="$HOME/Workspace/weaversbrain/weaversbrain/Learning"
OUTPUT_MODE="${1:-both}"

if [ ! -d "$LEARNING_DIR" ]; then
    echo "학습 노트 폴더 없음: $LEARNING_DIR" >&2
    exit 1
fi

python3 - "$LEARNING_DIR" "$OUTPUT_MODE" <<'PYEOF'
import os
import re
import sys
import json
from datetime import datetime, date, timedelta
from pathlib import Path

learning_dir = Path(sys.argv[1])
mode = sys.argv[2] if len(sys.argv) > 2 else "both"

# 도메인 분류 룰 — Learning/dashboard.md 의 taxonomy 와 동일
TAXONOMY = {
    "백엔드/API": ["fastapi", "spring", "kotlin", "django", "rest", "grpc", "dependency-injection"],
    "프론트엔드": ["react", "vue", "typescript", "javascript", "css", "tailwind"],
    "AI/LLM": ["llm", "ollama", "gemini", "codex", "rag", "embedding", "llm-routing", "prompt-engineering"],
    "인프라/Ops": ["docker", "kubernetes", "terraform", "aws", "ops", "dotfiles", "migration", "fastcgi", "php-fpm", "nginx"],
    "데이터/SQL": ["database", "sql", "postgresql", "clickhouse", "mysql", "materialized-view", "performance"],
    "오디오/STT": ["audio", "codec", "stt", "ffmpeg", "whisper", "torchaudio"],
    "CS 기본": ["cs", "design-pattern", "cpu", "scheduler", "null-object", "callback"],
    "Claude Code": ["claude-code", "automation", "hook", "prescan", "skill"],
    "보안/인증": ["sso", "oauth", "jwt", "keycloak", "auth"],
}

# auto_generated 일자별 노트 + 메타 태그 제외
META_TAGS = {"learning", "learning-note"}

def parse_frontmatter(text):
    """간이 YAML frontmatter 파서. tags(list/inline) 와 date/created 만 추출."""
    if not text.startswith("---"):
        return {}
    parts = text.split("---", 2)
    if len(parts) < 3:
        return {}
    fm_raw = parts[1]
    result = {"tags": [], "date": None, "auto_generated": False}

    lines = fm_raw.split("\n")
    i = 0
    while i < len(lines):
        line = lines[i]
        # tags: [a, b, c] 인라인
        m_inline = re.match(r"^tags:\s*\[(.*)\]\s*$", line)
        if m_inline:
            inner = m_inline.group(1)
            tags = [t.strip().strip('"').strip("'").lower() for t in inner.split(",") if t.strip()]
            result["tags"] = tags
            i += 1
            continue
        # tags: (블록 리스트)
        if re.match(r"^tags:\s*$", line):
            j = i + 1
            tags = []
            while j < len(lines):
                m = re.match(r"^\s+-\s+(.+?)\s*$", lines[j])
                if m:
                    tags.append(m.group(1).strip().strip('"').strip("'").lower())
                    j += 1
                else:
                    break
            result["tags"] = tags
            i = j
            continue
        # date: 2026-05-09  또는 date: "2026-05-09"
        m_date = re.match(r"^date:\s*\"?(\d{4}-\d{2}-\d{2})\"?\s*$", line)
        if m_date:
            result["date"] = m_date.group(1)
            i += 1
            continue
        # created: 2026-05-09  또는 created: 2026-05-09 19:38
        m_created = re.match(r"^created:\s*\"?(\d{4}-\d{2}-\d{2})", line)
        if m_created and not result["date"]:
            result["date"] = m_created.group(1)
            i += 1
            continue
        m_auto = re.match(r"^auto_generated:\s*(true|false)\s*$", line)
        if m_auto:
            result["auto_generated"] = m_auto.group(1) == "true"
            i += 1
            continue
        i += 1

    return result


def classify(tags):
    """태그 리스트를 도메인으로 분류. 매칭된 도메인 모두 반환 (중복 가능)."""
    matched = set()
    tagset = {t.lower() for t in tags}
    for domain, keywords in TAXONOMY.items():
        if tagset & set(keywords):
            matched.add(domain)
    return matched


# 노트 스캔
notes = []
for path in learning_dir.rglob("*.md"):
    name = path.name
    # dashboard / queue / queue.bak 제외
    if name.startswith("dashboard") or name.startswith("learning-queue"):
        continue
    try:
        text = path.read_text(encoding="utf-8")
    except Exception:
        continue
    fm = parse_frontmatter(text)
    # auto_generated 일자별 노트는 제외 (실제 학습 내용 없음)
    if fm.get("auto_generated"):
        continue
    # 파일명에서 시분 timestamp 패턴 (YYYY-MM-DD-HHMM-...) 또는 tags 가 있는 것만 학습 노트로 간주
    has_real_tags = bool([t for t in fm.get("tags", []) if t.lower() not in META_TAGS])
    has_timestamp_name = bool(re.match(r"^\d{4}-\d{2}-\d{2}-\d{4}-", name))
    if not has_real_tags and not has_timestamp_name:
        continue
    notes.append({
        "path": str(path),
        "name": name,
        "tags": fm.get("tags", []),
        "date": fm.get("date"),
    })

# 도메인별 카운트 + 마지막 학습일
today = date.today()
domain_stats = {}
for domain in TAXONOMY.keys():
    domain_stats[domain] = {"count": 0, "last_date": None, "days_since": None, "notes": []}

unclassified = []
for n in notes:
    matched = classify(n["tags"])
    if not matched:
        unclassified.append(n["name"])
        continue
    for domain in matched:
        domain_stats[domain]["count"] += 1
        domain_stats[domain]["notes"].append(n["name"])
        if n["date"]:
            try:
                d = datetime.strptime(n["date"], "%Y-%m-%d").date()
                cur = domain_stats[domain]["last_date"]
                if cur is None or d > datetime.strptime(cur, "%Y-%m-%d").date():
                    domain_stats[domain]["last_date"] = n["date"]
            except ValueError:
                pass

# days_since 계산
for domain, st in domain_stats.items():
    if st["last_date"]:
        d = datetime.strptime(st["last_date"], "%Y-%m-%d").date()
        st["days_since"] = (today - d).days
    else:
        st["days_since"] = None

# 0개 도메인 / 30일+ 미학습
zero_domains = [d for d, st in domain_stats.items() if st["count"] == 0]
stale_domains = [
    {"domain": d, "last_date": st["last_date"], "days_since": st["days_since"]}
    for d, st in domain_stats.items()
    if st["days_since"] is not None and st["days_since"] >= 30
]

# 최종 결과
result = {
    "scanned_at": datetime.now().strftime("%Y-%m-%dT%H:%M:%S"),
    "total_notes": len(notes),
    "domains": {
        d: {
            "count": st["count"],
            "last_date": st["last_date"],
            "days_since": st["days_since"],
        }
        for d, st in domain_stats.items()
    },
    "zero_domains": zero_domains,
    "stale_domains": stale_domains,
    "unclassified_count": len(unclassified),
}


def render_table():
    out = []
    out.append("=== 학습 도메인 편식 진단 ===")
    out.append(f"스캔 시각: {result['scanned_at']}")
    out.append(f"총 학습 노트: {result['total_notes']}개  (분류 불가: {result['unclassified_count']}개)")
    out.append("")
    out.append("도메인          개수  마지막 학습   경과일   분포")
    out.append("─" * 64)
    rows = sorted(domain_stats.items(), key=lambda kv: -kv[1]["count"])
    for domain, st in rows:
        cnt = st["count"]
        last = st["last_date"] or "-"
        days = st["days_since"]
        days_str = f"{days:>4}일" if days is not None else "    -"
        bar = "█" * min(cnt, 30)
        if cnt == 0:
            flag = " ⚠️0"
        elif days is not None and days >= 30:
            flag = f" ⚠️{days}d"
        else:
            flag = ""
        out.append(f"{domain:<14} {cnt:>4}  {last:<12}  {days_str}   {bar}{flag}")
    out.append("")
    if zero_domains:
        out.append(f"⚠️  노트 0개 도메인 ({len(zero_domains)}개): {', '.join(zero_domains)}")
    if stale_domains:
        out.append(f"⚠️  30일 이상 미학습 ({len(stale_domains)}개):")
        for s in stale_domains:
            out.append(f"     - {s['domain']}  (마지막: {s['last_date']}, {s['days_since']}일 경과)")
    if not zero_domains and not stale_domains:
        out.append("✅  편식 없음. 모든 도메인 30일 이내 학습.")
    return "\n".join(out)


if mode == "json":
    print(json.dumps(result, ensure_ascii=False, indent=2))
elif mode == "table":
    print(render_table())
else:  # both
    print(render_table())
    print("")
    print("--- JSON ---")
    print(json.dumps(result, ensure_ascii=False, indent=2))
PYEOF
