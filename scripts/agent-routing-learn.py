#!/usr/bin/env python3
"""
agent-quality.jsonl 의 user_trigger 패턴 → 어느 agent 가 가장 잘 매칭됐는지 학습.

출력: ~/.claude/cache/md-live/agent-routing-rules.json
{
  "rules": [
    {
      "keywords": ["db", "쿼리", "데이터베이스"],
      "suggested": "backend-developer",
      "confidence": 0.85,
      "evidence": 12  # 매칭된 호출 수
    }
  ],
  "agent_stats": { "backend-developer": {"avg_score": 70.0, "best_keywords": [...]} }
}
"""
import json
import re
from collections import Counter, defaultdict
from pathlib import Path

LIVE_DIR = Path.home() / ".claude" / "cache" / "md-live"
QUALITY = LIVE_DIR / "agent-quality.jsonl"
OUTCOMES = LIVE_DIR / "suggestion-outcomes.jsonl"
OUT = LIVE_DIR / "agent-routing-rules.json"


def load_outcome_stats():
    """suggestion-outcomes.jsonl 분석 → suggested_agent 별 acceptance rate.
    keyword level 까지는 데이터 부족할 수 있으므로 agent level 로 보정."""
    if not OUTCOMES.exists():
        return {}
    by_agent = {}  # agent → [accepted, ignored, other, expired]
    for ln in OUTCOMES.read_text().splitlines():
        if not ln.strip():
            continue
        try:
            d = json.loads(ln)
        except Exception:
            continue
        agent = d.get("suggested_agent", "")
        outcome = d.get("outcome", "")
        if not agent:
            continue
        rec = by_agent.setdefault(agent, {"accepted": 0, "ignored": 0, "other": 0, "expired": 0, "total": 0})
        if outcome in rec:
            rec[outcome] += 1
        rec["total"] += 1
    # acceptance rate 계산 — expired 제외 (사용자가 마무리 못 한 경우)
    for agent, rec in by_agent.items():
        decisive = rec["accepted"] + rec["ignored"] + rec["other"]
        rec["acceptance_rate"] = round(rec["accepted"] / max(1, decisive), 3) if decisive else None
        rec["decisive_count"] = decisive
    return by_agent

# 사용자 발화에서 키워드 추출 (한국어 + 영어, 2~30자)
KEYWORD_RE = re.compile(r"[가-힣a-zA-Z][가-힣a-zA-Z0-9]{1,29}")
STOPWORDS = {
    "있어", "없어", "해줘", "하자", "이거", "저거", "지금", "그냥", "다시",
    "진행", "작업", "다", "좀", "잘", "그런데", "왜", "뭐", "지", "이", "그",
    "the", "and", "for", "with", "this", "that", "you", "are", "is",
    "프로젝트", "사용자", "에이전트",
}


def main():
    if not QUALITY.exists():
        print("agent-quality.jsonl 없음")
        return
    rows = [json.loads(ln) for ln in QUALITY.read_text().splitlines() if ln.strip()]
    print(f"분석 대상: {len(rows)} 호출")

    # 1) 좋은 호출만 필터링 (점수 50+ + unique_hits 3+)
    good = [r for r in rows if r.get("score", 0) >= 50 and r.get("domain", {}).get("unique_hits", 0) >= 3]
    print(f"좋은 호출 (score≥50 & unique≥3): {len(good)}")

    # 2) 키워드 → agent 매핑 + agent 전체 호출 빈도 (배경)
    keyword_to_agents = defaultdict(Counter)
    agent_total = Counter()  # 좋은 호출 전체 중 agent 비율 (배경)
    for r in good:
        agent_total[r["agent_type"]] += 1
        trig = (r.get("user_trigger") or "").lower()
        if not trig: continue
        kws = set(KEYWORD_RE.findall(trig))
        kws = {k for k in kws if k.lower() not in STOPWORDS and len(k) >= 2}
        for k in kws:
            keyword_to_agents[k][r["agent_type"]] += 1
    total_good = sum(agent_total.values())
    # agent 별 prior (전체 중 비율)
    agent_prior = {a: c/max(1,total_good) for a, c in agent_total.items()}

    # 3) lift 기반 룰 — keyword 와 agent 매칭이 random 보다 얼마나 강한가
    # lift = P(agent | keyword) / P(agent)
    # outcome 기반 weight 보정 — 수용률 < 30% 이면 weight 감소
    outcome_stats = load_outcome_stats()
    if outcome_stats:
        print(f"\n📈 추천 outcome 데이터: {len(outcome_stats)} agents")
        for agent, rec in sorted(outcome_stats.items(), key=lambda x: -x[1]["total"]):
            ar = rec.get("acceptance_rate")
            ar_str = f"{ar:.0%}" if ar is not None else "N/A"
            print(f"  {agent:25} accepted={rec['accepted']:3} ignored={rec['ignored']:3} accept_rate={ar_str} (total={rec['total']})")

    rules = []
    for kw, agents in keyword_to_agents.items():
        total = sum(agents.values())
        if total < 3:
            continue
        top_agent, top_count = agents.most_common(1)[0]
        observed = top_count / total
        prior = agent_prior.get(top_agent, 0)
        if prior == 0: continue
        lift = observed / prior
        # lift ≥ 1.5 (이 agent 가 평균보다 1.5배 이상 자주 매칭) + observed ≥ 0.5
        if lift < 1.5 or observed < 0.5:
            continue

        # outcome weight: acceptance rate 20% 미만 + decisive ≥ 5 면 lift 0.7배 차감
        # 50% 이상 + decisive ≥ 5 면 boost (1.2배)
        weight_mult = 1.0
        outcome_note = ""
        rec = outcome_stats.get(top_agent)
        if rec and rec.get("decisive_count", 0) >= 5 and rec.get("acceptance_rate") is not None:
            ar = rec["acceptance_rate"]
            if ar < 0.2:
                weight_mult = 0.7
                outcome_note = f"low_accept({ar:.0%})"
            elif ar >= 0.5:
                weight_mult = 1.2
                outcome_note = f"high_accept({ar:.0%})"

        rules.append({
            "keyword": kw,
            "suggested": top_agent,
            "confidence": round(observed, 3),
            "lift": round(lift * weight_mult, 2),
            "raw_lift": round(lift, 2),
            "evidence": top_count,
            "total": total,
            "weight_mult": weight_mult,
            "outcome_note": outcome_note,
        })
    rules.sort(key=lambda x: (-x["lift"], -x["evidence"]))
    print(f"채택된 룰 (lift≥1.5, outcome 보정 후): {len(rules)}")

    # 4) agent_stats — 각 agent type 평균 점수 + best 키워드
    agent_scores = defaultdict(list)
    for r in rows:
        agent_scores[r["agent_type"]].append(r.get("score", 0))
    agent_stats = {}
    for at, scores in agent_scores.items():
        avg = sum(scores) / max(1, len(scores))
        # 이 agent 와 매칭이 강한 키워드들
        my_kws = [r["keyword"] for r in rules if r["suggested"] == at][:10]
        agent_stats[at] = {
            "count": len(scores),
            "avg_score": round(avg, 1),
            "best_keywords": my_kws,
        }

    out = {
        "generated_at": __import__("datetime").datetime.utcnow().isoformat() + "Z",
        "source_calls": len(rows),
        "good_calls": len(good),
        "rules": rules,  # 전체 저장 — 컷오프 시 다수 도메인(prior 높음)이 lift 상한에 걸려 누락되는 문제 회피
        "agent_stats": dict(sorted(agent_stats.items(), key=lambda x: -x[1]["avg_score"])),
        "outcome_stats": outcome_stats,
    }
    OUT.write_text(json.dumps(out, ensure_ascii=False, indent=2))
    print(f"\n✅ {OUT}")
    print(f"\n=== 상위 키워드 룰 20개 (lift 순) ===")
    for r in rules[:20]:
        print(f"  '{r['keyword']:18}' → {r['suggested']:22} lift={r['lift']:.1f}x conf={r['confidence']:.0%} ({r['evidence']}/{r['total']})")


if __name__ == "__main__":
    main()
