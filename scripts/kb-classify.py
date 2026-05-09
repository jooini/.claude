#!/usr/bin/env python3
"""knowledge 파일을 사내 고유도로 분류.

휴리스틱 점수 (0~10):
- 회사/제품명 (weaversbrain, speakingmax, maxai 등): +3
- 사내 시스템 이름 (Identity Hub, B2C, identity-nginx 등): +2
- 사내 코드 식별자 (T_, IdentityHub_lib, getServiceToken 등): +2
- ADR/RFC 형식 (ADR-NNN): +2
- 회사 사람 이름 (현준/영찬/주인식): +1 each
- 절대 날짜 (2026-MM-DD): +1
- Incident/RCA 키워드: +2
- URL 회사 도메인: +1

분류:
- 점수 7+ : 사내 고유 (⭐⭐⭐)
- 점수 3-6: 부분 (⭐⭐)
- 점수 0-2: 일반 베스트프랙티스 (⭐)
"""
import re
import sys
import json
from pathlib import Path

KB_ROOT = Path.home() / ".claude" / "agents" / "knowledge"

PATTERNS = {
    "company_product": {
        "regex": re.compile(r"\b(weaversbrain|speakingmax|maxai|speakingmaxapp|terracore|stt-insight|speech-hub|speech-quality|identity-hub|identity-nginx)\b", re.I),
        "score": 3,
    },
    # role의 도메인 키워드 — Claude가 알더라도 팀 SOP로 가치 있음
    "role_domain": {
        "regex": re.compile(r"(?i)\b(RAG|embedding|vector\s*store|chunking|fine[- ]tun|prompt\s*engineering|"
                            r"code\s*review|review\s*process|bug\s*detection|"
                            r"test\s*strategy|test\s*plan|unit\s*test|e2e\s*test|"
                            r"design\s*system|design\s*principle|wireframe|"
                            r"state\s*management|component\s*pattern|"
                            r"window\s*function|query\s*optim|ETL|data\s*model|"
                            r"PRD|product\s*strategy|product\s*vision|"
                            r"system\s*prompt|chain[- ]of[- ]thought|"
                            r"client\s*onboard|escalation|SLA)\b"),
        "score": 1,
    },
    # 번호 매겨진 시리즈 = 큐레이션된 SOP 가이드
    "numbered_sop": {
        "regex": re.compile(r"^\d{2}-[a-z]"),  # 파일명 패턴은 별도 처리
        "score": 0,  # 아래 classify에서 별도 처리
    },
    "internal_system": {
        "regex": re.compile(r"\b(Identity Hub|B2C\b|B2B\b|identity-nginx|Keycloak.*?(?:exact=True|getUserByUsername)|셀바스|Selvas|클로바노트)\b"),
        "score": 2,
    },
    "internal_code": {
        "regex": re.compile(r"\b(T_[A-Z][a-zA-Z]+|IdentityHub_lib|getServiceToken|setAdminCurlOptions|Auth_middleware|webapp/JUMP)\b"),
        "score": 2,
    },
    "adr": {
        "regex": re.compile(r"\bADR-\d{2,3}\b"),
        "score": 2,
    },
    "person_names": {
        "regex": re.compile(r"\b(현준|영찬|주인식)\b"),
        "score": 1,
    },
    "absolute_date": {
        "regex": re.compile(r"\b(202[5-7])-(0[1-9]|1[0-2])-(0[1-9]|[12]\d|3[01])\b"),
        "score": 1,
    },
    "incident": {
        "regex": re.compile(r"(?:\b(?:incident|RCA|postmortem|root\s+cause)\b|장애\s*(?:대응|보고|분석)|회고록|incident\s*report)"),
        "score": 2,
    },
    "company_url": {
        "regex": re.compile(r"\b(weaversbrain\.com|maxaiapp\.com|speakingmax\.com|speakingmaxapp\.com)\b"),
        "score": 1,
    },
}


def classify(path: Path) -> dict:
    text = path.read_text(errors="ignore")
    hits = {}
    score = 0
    for name, p in PATTERNS.items():
        if name == "numbered_sop":
            continue  # 파일명 기반, 아래 별도 처리
        matches = p["regex"].findall(text)
        if matches:
            count = len(matches)
            sc = min(p["score"] * (1 if count == 1 else 2), p["score"] * 2)
            hits[name] = {"count": count, "score": sc, "samples": list(set(str(m) for m in matches[:3]))}
            score += sc

    # 파일명 기반 보너스
    # 1) 번호 매겨진 SOP (NN-name.md)
    if re.match(r"^\d{2}-[a-z]", path.name):
        sc = 2
        hits["numbered_sop"] = {"count": 1, "score": sc, "samples": [path.name]}
        score += sc
    # 2) role 디렉토리 안에 있으면 = 그 role의 도메인 가이드
    try:
        rel = path.relative_to(KB_ROOT)
    except ValueError:
        rel = path
    parts = rel.parts
    role_dirs = {
        "ai-engineer", "backend-developer", "code-reviewer", "code-tester",
        "data-analyst", "designer", "frontend-developer", "ops-lead",
        "po", "prompt-engineer", "qa", "debug-master", "dev-lead",
    }
    if parts and parts[0] in role_dirs:
        sc = 1
        hits["role_dir"] = {"count": 1, "score": sc, "samples": [parts[0]]}
        score += sc

    if score >= 7:
        tier = "⭐⭐⭐ 사내 고유"
    elif score >= 4:
        tier = "⭐⭐ 부분/도메인 가이드"
    elif score >= 2:
        tier = "⭐ 일반 가이드 (보존 가치 있음)"
    else:
        tier = "⚪ 노이즈"

    return {
        "path": str(path.relative_to(KB_ROOT)),
        "score": score,
        "tier": tier,
        "hits": hits,
        "size_bytes": path.stat().st_size,
    }


def main():
    files = []
    for p in KB_ROOT.rglob("*.md"):
        if p.name.startswith("knowledge-catalog") or p.name == "MAINTENANCE.md":
            continue
        # templates만 제외 (archive는 재분류 대상에 포함)
        rel = str(p.relative_to(KB_ROOT))
        if rel.startswith("_templates/"):
            continue
        # archive 파일은 archive/ 접두어 제거하고 원래 경로로 분류
        if rel.startswith("_archive/"):
            # 점수만 계산 (실제 위치는 archive)
            pass
        files.append(p)
    files.sort()

    if len(sys.argv) > 1 and sys.argv[1] == "--sample":
        n = int(sys.argv[2]) if len(sys.argv) > 2 else 20
        import random
        random.seed(42)
        files = random.sample(files, min(n, len(files)))

    results = [classify(p) for p in files]

    by_tier = {"⭐⭐⭐ 사내 고유": [], "⭐⭐ 부분": [], "⭐ 일반": []}
    for r in results:
        by_tier[r["tier"]].append(r)

    print(f"분류 대상: {len(results)}개")
    print()
    for tier, items in by_tier.items():
        print(f"=== {tier}: {len(items)}개 ({len(items)*100//len(results)}%) ===")
        for r in sorted(items, key=lambda x: -x["score"])[:15]:
            samples = []
            for h in r["hits"].values():
                samples.extend(h["samples"][:2])
            sample_str = ", ".join(samples[:4])[:80]
            print(f"  [{r['score']:2}] {r['path']}  ← {sample_str}")
        if len(items) > 15:
            print(f"  ... 외 {len(items)-15}개")
        print()

    out = Path.home() / ".claude" / "cache" / "kb-classify.json"
    out.parent.mkdir(exist_ok=True)
    out.write_text(json.dumps(results, ensure_ascii=False, indent=2))
    print(f"전체 결과 저장: {out}")


if __name__ == "__main__":
    main()
