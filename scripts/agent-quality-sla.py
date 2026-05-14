#!/usr/bin/env python3
"""
Agent Quality SLA 체크 — 매일 1회 실행 권장.

규칙:
- 평균 점수 < 30 + 호출 ≥ 3 인 agent → SLA 위반
- unique=0 비율 ≥ 50% + 호출 ≥ 3 → knowledge 미활용
- wrong_agent 추천이 같은 agent 에 ≥ 5 건 → 라우팅 룰 갱신 후보

출력:
1. 콘솔 (수동 실행 시)
2. ~/.claude/cache/md-live/agent-sla-report.md (어제 → 오늘 비교)
3. Obsidian Vault 에 회고 노트 자동 생성 (선택)
"""
import json
import sys
from collections import Counter, defaultdict
from datetime import datetime
from pathlib import Path

LIVE_DIR = Path.home() / ".claude" / "cache" / "md-live"
QUALITY = LIVE_DIR / "agent-quality.jsonl"
REPORT = LIVE_DIR / "agent-sla-report.md"

# Obsidian Vault (선택)
OBSIDIAN_INBOX = Path.home() / "Workspace" / "weaversbrain" / "weaversbrain" / "Inbox"


def main():
    if not QUALITY.exists():
        print("agent-quality.jsonl 없음. /agent-quality-analyze 먼저 실행.")
        sys.exit(1)

    rows = [json.loads(ln) for ln in QUALITY.read_text().splitlines() if ln.strip()]
    print(f"분석 대상: {len(rows)}")

    # agent 별 집계
    by_agent = defaultdict(lambda: {
        "scores": [], "unique_hits": [], "term_count": 0,
        "wrong_agent_target": Counter(),
    })
    for r in rows:
        at = r["agent_type"]
        by_agent[at]["scores"].append(r.get("score", 0))
        by_agent[at]["unique_hits"].append(r.get("domain", {}).get("unique_hits", 0))
        by_agent[at]["term_count"] = r.get("domain", {}).get("term_count", 0)
        if r.get("suggested_agent"):
            by_agent[at]["wrong_agent_target"][r["suggested_agent"]] += 1

    # SLA 위반
    sla_violations = []
    knowledge_underuse = []
    routing_candidates = []

    for at, info in by_agent.items():
        n = len(info["scores"])
        if n < 3:
            continue
        avg = sum(info["scores"]) / n
        zero_rate = sum(1 for h in info["unique_hits"] if h == 0) / n
        if avg < 30:
            sla_violations.append((at, avg, n))
        if info["term_count"] > 0 and zero_rate >= 0.5:
            knowledge_underuse.append((at, zero_rate, n, info["term_count"]))
        # 같은 agent 에서 다른 agent 추천이 5+
        for target, cnt in info["wrong_agent_target"].most_common(3):
            if cnt >= 5:
                routing_candidates.append((at, target, cnt, n))

    # 리포트
    today = datetime.now().strftime("%Y-%m-%d")
    lines = [
        f"# Agent Quality SLA Report — {today}",
        "",
        f"전체 호출 분석: {len(rows)}",
        "",
    ]

    if sla_violations:
        lines.append("## 🔴 SLA 위반 (평균 점수 < 30)")
        lines.append("")
        for at, avg, n in sorted(sla_violations, key=lambda x: x[1]):
            lines.append(f"- **{at}** (호출 {n}건) — 평균 {avg:.1f}")
            lines.append(f"  - 액션: agent definition 점검, 또는 호출 패턴 재검토")
        lines.append("")

    if knowledge_underuse:
        lines.append("## 🟡 Knowledge 미활용 (unique=0 ≥ 50%)")
        lines.append("")
        for at, zr, n, tc in sorted(knowledge_underuse, key=lambda x: -x[1]):
            lines.append(f"- **{at}** ({n}건 중 {int(zr*n)}건이 0매칭) — 용어 풀 {tc}개")
            lines.append(f"  - 액션: `~/.claude/agents/build-agents.sh {at}` 재빌드")
            lines.append(f"  - 또는 knowledge 도메인 점검: `ls ~/.claude/agents/knowledge/{at}/`")
        lines.append("")

    if routing_candidates:
        lines.append("## ⚠️ 라우팅 미스매치 패턴 (같은 잘못 5건+)")
        lines.append("")
        for at, target, cnt, n in sorted(routing_candidates, key=lambda x: -x[2]):
            pct = cnt/n*100
            lines.append(f"- **{at}** {cnt}건이 사실상 **{target}** 영역 ({pct:.0f}% 미스매치)")
            lines.append(f"  - 액션: 향후 비슷한 발화는 직접 {target} 호출")
            lines.append(f"  - 또는 ~/.claude/cache/md-live/agent-routing-rules.json 룰 강화")
        lines.append("")

    if not (sla_violations or knowledge_underuse or routing_candidates):
        lines.append("## ✅ SLA 위반 없음")
        lines.append("")

    REPORT.write_text("\n".join(lines))
    print(f"\n📄 리포트: {REPORT}")
    print()
    print("\n".join(lines))

    # Obsidian Vault 자동 등록 (위반 1건 이상이고 vault 존재할 때)
    if (sla_violations or knowledge_underuse or routing_candidates) and OBSIDIAN_INBOX.exists():
        slug = f"{today}-agent-quality-sla.md"
        target = OBSIDIAN_INBOX / slug
        if not target.exists():
            target.write_text(
                f"---\ntitle: Agent Quality SLA — {today}\ntype: action-needed\ntags: [agent-quality, sla]\n---\n\n"
                + "\n".join(lines)
            )
            print(f"📥 Obsidian: {target}")


if __name__ == "__main__":
    main()
