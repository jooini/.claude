#!/usr/bin/env python3
"""
Decision Wave Tracker — claude-mem 7912 observations에서 결정 추출 → 시간축 모순/번복 그래프.

자료원:
- ~/.claude-mem/claude-mem.db (observations.narrative + facts)
- ~/Workspace/weaversbrain/weaversbrain/decisions/ (있으면)

Codex MVP 권고:
- LLM 단독 모순 판정 X
- evidence edge: 채택→기각, 권장→번복, 동일 topic 상반 결론

진행:
1. 결정 시그널 키워드로 observations 추출
2. 토픽 추출 (concepts 컬럼 + 명사 키워드)
3. 같은 토픽에 시간차 두고 등장한 결정 → wave (번복/강화)
4. 충돌 신호 단어쌍 매칭 (instead of / switched / reverted / adopted X over Y)
"""

import re
import sys
import json
import sqlite3
import argparse
from pathlib import Path
from collections import defaultdict, Counter
from datetime import datetime

DB = Path.home() / ".claude-mem/claude-mem.db"
OUT_MD = Path.home() / ".claude/cache/decision-wave.md"
OUT_JSON = Path.home() / ".claude/cache/decision-wave.json"

DECISION_KW = [
    "decision", "selected", "chose ", "rejected", "instead of", "switched",
    "reverted", "adopted", "replaced", "deprecated", "migrated",
    "채택", "기각", "번복", "결정", "선택", "전환", "롤백",
]

REVERSAL_PATTERNS = [
    re.compile(r"\b(switched to|moved to|migrated to|replaced)\s+(.{3,80}?)(?:\s+(?:from|instead of)\s+(.{3,80}?))?[.\n]", re.IGNORECASE),
    re.compile(r"\binstead of\s+(.{3,80}?)(?:,|\.|$)", re.IGNORECASE),
    re.compile(r"\breverted\s+(.{3,80}?)(?:,|\.|$)", re.IGNORECASE),
    re.compile(r"\b(deprecated|removed)\s+(.{3,80}?)(?:,|\.|$)", re.IGNORECASE),
]


def extract_topics(text):
    """대문자 명사 + 따옴표/백틱 안 단어 → 토픽."""
    if not text:
        return []
    candidates = set()
    for m in re.findall(r'`([^`]{2,40})`', text):
        candidates.add(m.lower())
    for m in re.findall(r'"([^"]{3,40})"', text):
        candidates.add(m.lower())
    for m in re.findall(r'\b([A-Z][A-Za-z]{3,})\s*(?:Service|Provider|Manager|Hub|Engine|Model|Config|Loader|Handler|Filter|Repository)\b', text):
        candidates.add(m.lower())
    for m in re.findall(r'\b(Identity Hub|Keycloak|FastAPI|alembic|JWT|SSO|LanceDB|ClickHouse|Codex|Gemini|graphify|claude-mem|local-rag|witness|forecast|vitality|self-model|hook|skill|MCP)\b', text, re.IGNORECASE):
        candidates.add(m.lower())
    return list(candidates)[:8]


def extract_decisions(rows):
    decisions = []
    for r in rows:
        narrative = r["narrative"] or ""
        facts = r["facts"] or ""
        text = narrative + "\n" + facts
        topics = extract_topics(text)
        reversals = []
        for pat in REVERSAL_PATTERNS:
            for m in pat.finditer(text):
                reversals.append({
                    "kind": pat.pattern[:30],
                    "match": m.group(0)[:200],
                })
        decisions.append({
            "id": r["id"],
            "ts": r["created_at"][:16] if r["created_at"] else "",
            "epoch": r["created_at_epoch"] or 0,
            "project": r["project"],
            "type": r["type"],
            "topics": topics,
            "reversals": reversals,
            "narrative_excerpt": narrative[:300],
        })
    return decisions


def find_topic_waves(decisions, min_count=2):
    """같은 토픽에 시간차 두고 등장한 결정들."""
    by_topic = defaultdict(list)
    for d in decisions:
        for t in d["topics"]:
            by_topic[t].append(d)
    waves = []
    for topic, ds in by_topic.items():
        if len(ds) < min_count:
            continue
        ds_sorted = sorted(ds, key=lambda x: x["epoch"])
        spread_days = (ds_sorted[-1]["epoch"] - ds_sorted[0]["epoch"]) / 86400 if ds_sorted[0]["epoch"] else 0
        waves.append({
            "topic": topic,
            "count": len(ds_sorted),
            "spread_days": round(spread_days, 1),
            "first_ts": ds_sorted[0]["ts"],
            "last_ts": ds_sorted[-1]["ts"],
            "projects": list(set(d["project"] for d in ds_sorted)),
            "decision_ids": [d["id"] for d in ds_sorted],
            "samples": [
                {"ts": d["ts"], "project": d["project"], "excerpt": d["narrative_excerpt"][:200]}
                for d in ds_sorted[:5]
            ],
        })
    waves.sort(key=lambda w: (-w["count"], -w["spread_days"]))
    return waves


def find_explicit_reversals(decisions):
    """명시적 번복 신호가 있는 결정만."""
    out = []
    for d in decisions:
        if d["reversals"]:
            out.append({
                "id": d["id"],
                "ts": d["ts"],
                "project": d["project"],
                "topics": d["topics"],
                "reversals": d["reversals"][:3],
                "excerpt": d["narrative_excerpt"][:250],
            })
    return out


def load_decisions(db_path, limit_days=180):
    """claude-mem DB에서 결정 시그널 있는 observations 추출."""
    conn = sqlite3.connect(str(db_path))
    conn.row_factory = sqlite3.Row
    cur = conn.cursor()

    where_clauses = []
    for kw in DECISION_KW:
        where_clauses.append(f"narrative LIKE '%{kw}%' OR facts LIKE '%{kw}%'")
    where_sql = " OR ".join(where_clauses)

    sql = f"""
        SELECT id, memory_session_id, project, type, narrative, facts,
               concepts, created_at, created_at_epoch
        FROM observations
        WHERE ({where_sql})
        ORDER BY created_at_epoch ASC
    """
    rows = list(cur.execute(sql))
    conn.close()
    return rows


def write_md(decisions, waves, reversals):
    OUT_MD.parent.mkdir(parents=True, exist_ok=True)
    lines = []
    lines.append("# Decision Wave Tracker")
    lines.append("")
    lines.append(f"- 결정 시그널 observations: {len(decisions)}개")
    lines.append(f"- 토픽 wave (같은 토픽 2+회): {len(waves)}")
    lines.append(f"- 명시적 번복 신호: {len(reversals)}")
    lines.append("")

    proj_count = Counter(d["project"] for d in decisions)
    lines.append("## 프로젝트별 결정 분포")
    lines.append("")
    lines.append("| 프로젝트 | 결정 수 |")
    lines.append("|---|---|")
    for p, c in proj_count.most_common(10):
        lines.append(f"| {p} | {c} |")
    lines.append("")

    lines.append("## 토픽 Wave TOP 30 (같은 토픽이 시간차 두고 반복 등장)")
    lines.append("")
    lines.append("> 같은 토픽이 여러 시점에 나타남 = 결정 강화 또는 번복 가능성")
    lines.append("")
    for w in waves[:30]:
        lines.append(f"### `{w['topic']}` — {w['count']}회 / {w['spread_days']}일 ({w['first_ts'][:10]} → {w['last_ts'][:10]})")
        lines.append(f"- 관여 프로젝트: {', '.join(w['projects'])}")
        for s in w["samples"][:3]:
            lines.append(f"- **{s['ts']}** [{s['project']}]: {s['excerpt'][:180]}")
        lines.append("")

    lines.append("## 명시적 번복 신호 (instead of / switched / reverted / replaced)")
    lines.append("")
    for r in reversals[:30]:
        lines.append(f"### {r['ts']} [{r['project']}]")
        for rv in r["reversals"]:
            lines.append(f"- 패턴: `{rv['match'][:200]}`")
        lines.append(f"- 컨텍스트: {r['excerpt'][:200]}")
        lines.append("")
    if len(reversals) > 30:
        lines.append(f"... 외 {len(reversals) - 30}건")
        lines.append("")

    lines.append("## 권고")
    lines.append("")
    lines.append("- 토픽 wave 빈도 5+ 는 중요 결정 — 일관성 점검 필요")
    lines.append("- 번복 신호가 같은 프로젝트에서 반복되면 설계 미정착")
    lines.append("- /witness '토픽명' 으로 과거 정정 패턴까지 통합 조회 가능")

    OUT_MD.write_text("\n".join(lines), encoding="utf-8")


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--show", action="store_true")
    args = ap.parse_args()

    if not DB.exists():
        print(f"claude-mem DB 없음: {DB}", file=sys.stderr)
        sys.exit(1)

    print(f"분석: {DB}", file=sys.stderr)
    rows = load_decisions(DB)
    print(f"  결정 시그널 행: {len(rows)}", file=sys.stderr)

    decisions = extract_decisions(rows)
    waves = find_topic_waves(decisions, min_count=2)
    reversals = find_explicit_reversals(decisions)

    print(f"  토픽 wave: {len(waves)}", file=sys.stderr)
    print(f"  명시적 번복: {len(reversals)}", file=sys.stderr)

    write_md(decisions, waves, reversals)
    OUT_JSON.write_text(json.dumps({
        "total_decisions": len(decisions),
        "wave_count": len(waves),
        "reversal_count": len(reversals),
        "waves_top": waves[:50],
        "reversals_top": reversals[:50],
    }, indent=2, ensure_ascii=False), encoding="utf-8")

    print(f"\n리포트: {OUT_MD}", file=sys.stderr)
    if args.show:
        print(OUT_MD.read_text())


if __name__ == "__main__":
    main()
