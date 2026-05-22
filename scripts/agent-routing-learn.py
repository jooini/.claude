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

# 한국어 조사 분리 — "에이전트가" → "에이전트", "코드는" → "코드"
# 의미 있는 단어와 결합된 조사를 떼어내 stopword 매칭 정확도 향상
KOREAN_PARTICLE_RE = re.compile(
    r'^(.+?)(는|은|이|가|을|를|의|와|랑|도|만|들|로|으로|에서|에게|에서는|에게도|에서도|보다|마저|조차|에|와는)$'
)

STOPWORDS = {
    # 기존 (2026-05-09)
    "있어", "없어", "해줘", "하자", "이거", "저거", "지금", "그냥", "다시",
    "진행", "작업", "다", "좀", "잘", "그런데", "왜", "뭐", "지", "이", "그",
    "the", "and", "for", "with", "this", "that", "you", "are", "is",
    "프로젝트", "사용자", "에이전트",
    # 추가 (2026-05-21 — 실측 17건 노이즈 룰 정리)
    # 한국어 인칭/지시
    "니가", "내가", "네가", "저는", "제가", "우리", "나는", "너도",
    "이건", "저건", "이게", "저게", "그거", "그건", "그게",
    # 한국어 시간/빈도 부사
    "아까", "나중", "진작", "벌써", "아직", "이미", "바로", "곧", "한번", "두번",
    # 한국어 일상 명사/동사
    "사용", "성공", "실패", "확인", "문제", "결과", "상태", "관리",
    "가능", "불가", "해결", "처리", "시작", "종료", "완료", "시도",
    "환경", "기능", "데이터", "파일", "폴더", "코드", "서비스", "시스템",
    # 한국어 형용사/부사
    "좋은", "나쁜", "같은", "다른", "새로운", "오래된", "많은", "적은",
    "잘못", "제대로", "겨우", "거의", "약간", "먼저", "특히",
    # 한국어 응답/감탄
    "아니", "맞아", "오케이", "ㅇㅋ",
    # 한국어 접속/조사 변형
    "그리고", "그래서", "하지만", "그러나", "그러면", "아니면",
    # 영어 stopwords 확장
    "of", "in", "on", "at", "to", "a", "an", "be", "by", "or", "but",
    "not", "if", "so", "do", "how", "why", "what", "when", "where",
    "all", "any", "some", "will", "can", "could", "would", "should",
    "just", "now", "then", "here", "there", "as", "we", "i", "me",
    "my", "your", "his", "her", "it", "its", "their", "them",
}


def normalize_keyword(kw: str) -> str:
    """한국어 조사 분리 — 본체만 추출.
    예: '에이전트가' → '에이전트', '코드는' → '코드'
    """
    kw = kw.lower()
    m = KOREAN_PARTICLE_RE.match(kw)
    if m:
        stem = m.group(1)
        # 본체가 2자 미만이면 분리 안 함 (예: "가가" → "가")
        if len(stem) >= 2:
            return stem
    return kw


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
        raw_kws = set(KEYWORD_RE.findall(trig))
        # 조사 분리 후 stopword 필터 (정확도 향상)
        kws = {normalize_keyword(k) for k in raw_kws}
        kws = {k for k in kws if k not in STOPWORDS and len(k) >= 2}
        # hex 류 토큰 차단 — 4자 이상 순수 hex는 모두 노이즈 (해시 단편/컬러코드 모두 제거).
        # 컬러코드는 frontend 명백 도메인이지만 a780/cb7fe 같은 hash 단편이 같이 학습돼
        # 실측 16건 frontend 편향 노이즈를 만들었음. 차라리 통째 차단이 안전.
        kws = {k for k in kws if not (len(k) >= 4 and all(c in '0123456789abcdef' for c in k))}
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

    # 소수 agent 의 prior 인위 부풀림 방지 — floor 0.15.
    # 예: frontend prior 0.128 이면 5번 매칭만으로 lift 7.8x → floor 적용 시 lift 6.7x.
    # 더 중요한 건 evidence 임계값 (아래 10) 으로 5건짜리 룰을 차단.
    PRIOR_FLOOR = 0.15
    # 최소 evidence — 3건은 우연 매칭 가능.
    # 시뮬레이션 (2026-05-22): min_ev=3 → 495룰 (frontend 편향), min_ev=5 → 57룰,
    # min_ev=7 → 12룰 (backend 7/frontend 5 균형), min_ev=10 → 1룰 (너무 엄격).
    # 7건이 통계적 신뢰와 정보량의 균형점.
    MIN_EVIDENCE = 7

    rules = []
    for kw, agents in keyword_to_agents.items():
        total = sum(agents.values())
        if total < MIN_EVIDENCE:
            continue
        top_agent, top_count = agents.most_common(1)[0]
        if top_count < MIN_EVIDENCE:
            continue
        observed = top_count / total
        prior = max(agent_prior.get(top_agent, 0), PRIOR_FLOOR)
        if prior == 0: continue
        lift = observed / prior
        # lift ≥ 1.5 (이 agent 가 평균보다 1.5배 이상 자주 매칭) + observed ≥ 0.5
        if lift < 1.5 or observed < 0.5:
            continue

        # outcome weight: acceptance rate 30% 미만 + decisive ≥ 5 면 lift 0.5배 강하게 차감.
        # 50% 이상 + decisive ≥ 5 면 boost (1.2배).
        # 2026-05-22: frontend 채택률 7% 인데 기존 0.7배 감쇠로는 부족했음 — 0.5배로 강화.
        weight_mult = 1.0
        outcome_note = ""
        rec = outcome_stats.get(top_agent)
        if rec and rec.get("decisive_count", 0) >= 5 and rec.get("acceptance_rate") is not None:
            ar = rec["acceptance_rate"]
            if ar < 0.3:
                weight_mult = 0.5
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
