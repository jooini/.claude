#!/usr/bin/env python3
"""v2 backlog.md → v3 (카테고리 컬럼 추가) 마이그레이션.

사용:
    python3 backlog-migrate-v3.py                # 전체 프로젝트 dry-run 미리보기
    python3 backlog-migrate-v3.py --apply        # 실제 적용
    python3 backlog-migrate-v3.py --apply --project identity-hub
    python3 backlog-migrate-v3.py --reclassify   # 이미 v3여도 카테고리 재추론

키워드 룰 기반 분류 → 모호한 항목은 빈 카테고리로 두고 리스트업.
"""
from __future__ import annotations

import argparse
import re
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent))
from backlog_lib import (  # type: ignore
    CATEGORY_NAMES,
    PROJECTS,
    Task,
    iter_project_backlogs,
    read_backlog,
    render_v3,
)


# (카테고리, [(가중치, 정규식)])
RULES: list[tuple[str, list[tuple[int, str]]]] = [
    ("보안", [
        (10, r"\b(인증|권한|JWT|토큰|OAuth|SSO|RBAC|CSRF|XSS|SQL[\s-]?injection|취약|보안)\b"),
        (8,  r"(rate[\s-]?limit|레이트|블록|차단|만료|퍼지|PII|개인정보|민감)"),
        (6,  r"(API[\s-]?key|secret|시크릿|크레덴셜|패스워드|비밀번호|쿠키|세션)"),
    ]),
    ("버그", [
        (10, r"\b(bug|버그|fix|수정|에러|error|예외|crash|장애|깨짐|이상|틀림)\b"),
        (6,  r"(미구현|동작\s?안|작동\s?안|반영\s?안|누락|race\s?condition|deadlock)"),
    ]),
    ("성능", [
        (10, r"\b(성능|perf|최적화|optimize|latency|응답시간|throughput|throughput)\b"),
        (8,  r"(N\+1|캐시|cache|인덱스|index|느림|느려|병목|memory|메모리\s?누수)"),
    ]),
    ("테스트", [
        (10, r"\b(테스트|test|coverage|커버리지|TDD|pytest|jest|회귀)\b"),
        (6,  r"(mock|모킹|fixture|픽스처|e2e|단위\s?테스트|통합\s?테스트)"),
    ]),
    ("문서", [
        (10, r"\b(문서|docs?|README|가이드|guide|매뉴얼|튜토리얼)\b"),
        (8,  r"(TODO\s?작성|체크리스트|Known\s?Issues|주석|comment|예제)"),
    ]),
    ("리팩터", [
        (10, r"\b(리팩터|refactor|정리|cleanup|구조\s?개선|분리|통합)\b"),
        (6,  r"(헬퍼|helper|mixin|strategy|extract|상수화|매직\s?넘버|중복\s?제거|네이밍)"),
        (4,  r"(미사용|deprecated|제거|삭제)"),
    ]),
    ("설정", [
        (10, r"\b(환경변수|env|설정|config|Docker|Terraform|infra|인프라)\b"),
        (8,  r"(하드코딩|배포|CI|CD|workflow|파이프라인|secret\s?manager)"),
        (6,  r"(KEYCLOAK_|DEFAULT_|ALLOWED_|URL|PORT|HOST)"),
    ]),
    ("기능", [
        (8,  r"\b(추가|신규|구현|implement|feature|기능|enable|지원|연동)\b"),
        (4,  r"(API|엔드포인트|endpoint|화면|페이지|UI|컴포넌트)"),
    ]),
]


def classify(title: str, detail: list[str]) -> tuple[str, dict[str, int]]:
    """카테고리와 점수표 반환. 점수 0이면 빈 문자열."""
    text = title + " " + " ".join(detail)
    scores: dict[str, int] = {}
    for cat, patterns in RULES:
        s = 0
        for w, pat in patterns:
            if re.search(pat, text, re.IGNORECASE):
                s += w
        if s > 0:
            scores[cat] = s
    if not scores:
        return "", scores
    best = max(scores.items(), key=lambda x: x[1])
    return best[0], scores


def migrate_project(path: Path, project: str, apply: bool, reclassify: bool) -> dict:
    tasks, schema = read_backlog(path)
    if schema == "none":
        return {"project": project, "schema": "none", "skipped": True}
    if schema == "v3" and not reclassify:
        return {"project": project, "schema": "v3", "skipped": True}

    classified = 0
    ambiguous: list[tuple[str, str]] = []
    for t in tasks:
        if t.category and not reclassify:
            classified += 1
            continue
        cat, scores = classify(t.title, t.detail)
        if cat:
            t.category = cat
            classified += 1
        else:
            ambiguous.append((t.id, t.title))

    if apply:
        rendered = render_v3(tasks, project)
        path.write_text(rendered, encoding="utf-8")

    return {
        "project": project,
        "schema": schema,
        "total": len(tasks),
        "classified": classified,
        "ambiguous": ambiguous,
        "applied": apply,
    }


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--apply", action="store_true", help="실제 파일 저장")
    ap.add_argument("--project", help="단일 프로젝트만")
    ap.add_argument("--reclassify", action="store_true", help="v3여도 카테고리 재추론")
    args = ap.parse_args()

    target_projects = (
        [(args.project, dict(PROJECTS).get(args.project, ""))]
        if args.project
        else PROJECTS
    )

    print(f"{'프로젝트':35s} | schema | total | 분류 | 모호 | 적용")
    print("-" * 88)

    total_amb: list[tuple[str, str, str]] = []
    for project, _ in target_projects:
        path = Path.home() / "Workspace" / project / "docs" / "backlog.md"
        if not path.exists():
            continue
        r = migrate_project(path, project, args.apply, args.reclassify)
        if r.get("skipped"):
            print(f"{project:35s} | {r['schema']:6s} | (skip)")
            continue
        amb_n = len(r["ambiguous"])
        print(
            f"{project:35s} | {r['schema']:6s} | {r['total']:5d} | "
            f"{r['classified']:4d} | {amb_n:4d} | {'YES' if r['applied'] else 'dry'}"
        )
        for tid, title in r["ambiguous"]:
            total_amb.append((project, tid, title))

    if total_amb:
        print(f"\n⚠ 모호한 태스크 ({len(total_amb)}건) — 수동 카테고리 부여 권장:")
        for project, tid, title in total_amb:
            print(f"  · [{project}] {tid}: {title[:70]}")

    if not args.apply:
        print("\n(dry-run) --apply 추가하면 실제 저장")

    return 0


if __name__ == "__main__":
    sys.exit(main())
