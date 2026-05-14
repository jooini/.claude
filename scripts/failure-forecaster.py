#!/usr/bin/env python3
"""
30분 후 장애 예보관 (MVP).

코드 변경 직후 운영 흐름에서 깨질 가능성을 시뮬레이션.

분석 대상:
- 현재 git diff (또는 마지막 커밋)
- 변경된 함수/필드 시그니처
- 호출자(callers) 검색 (grep 기반)
- 환경 의존성 (env vars, config 파일)
- 멀티 프로젝트 chain 영향 (SSO 같은 경우)

출력 형식: 위험 시나리오 3-5개, 각각 (확률, 영향, 30분 시뮬레이션, 검증 방법)

이 MVP는 휴리스틱 + Gemini 호출 (선택)로 동작. 실제 Playwright/CI 연동은 미구현.
"""

import os
import re
import sys
import json
import argparse
import subprocess
from pathlib import Path
from datetime import datetime


def get_diff(cwd, mode="unstaged"):
    cmds = {
        "unstaged": ["git", "-C", cwd, "diff"],
        "staged": ["git", "-C", cwd, "diff", "--staged"],
        "head": ["git", "-C", cwd, "diff", "HEAD~1..HEAD"],
    }
    cmd = cmds.get(mode, cmds["unstaged"])
    try:
        out = subprocess.run(cmd, capture_output=True, text=True, timeout=10)
        return out.stdout if out.returncode == 0 else ""
    except Exception:
        return ""


def get_changed_files(cwd, mode="unstaged"):
    cmds = {
        "unstaged": ["git", "-C", cwd, "diff", "--name-only"],
        "staged": ["git", "-C", cwd, "diff", "--name-only", "--staged"],
        "head": ["git", "-C", cwd, "diff", "--name-only", "HEAD~1..HEAD"],
    }
    cmd = cmds.get(mode, cmds["unstaged"])
    try:
        out = subprocess.run(cmd, capture_output=True, text=True, timeout=10)
        return [l.strip() for l in out.stdout.splitlines() if l.strip()]
    except Exception:
        return []


def extract_signatures(diff_text):
    """변경된 함수/메서드 시그니처 + 필드 추출."""
    sigs = {
        "removed_functions": re.findall(r"^-\s*def\s+(\w+)\(", diff_text, re.MULTILINE),
        "added_functions": re.findall(r"^\+\s*def\s+(\w+)\(", diff_text, re.MULTILINE),
        "removed_methods": re.findall(r"^-\s*(?:public|private|async)?\s*function\s+(\w+)|^-\s*(\w+)\s*=\s*(?:async\s+)?\(", diff_text, re.MULTILINE),
        "removed_fields": re.findall(r'^-\s*["\']?(\w+)["\']?\s*[:=]', diff_text, re.MULTILINE),
        "added_fields": re.findall(r'^\+\s*["\']?(\w+)["\']?\s*[:=]', diff_text, re.MULTILINE),
        "removed_keys": re.findall(r'^-\s*["\'](\w+)["\']\s*:', diff_text, re.MULTILINE),
        "added_keys": re.findall(r'^\+\s*["\'](\w+)["\']\s*:', diff_text, re.MULTILINE),
    }
    return {k: list(set(v)) if isinstance(v, list) else v for k, v in sigs.items()}


def find_callers(symbol, search_root, max_results=10):
    if not symbol or len(symbol) < 3:
        return []
    try:
        out = subprocess.run(
            ["rg", "-n", "--max-count", "3", "--type", "py", "--type", "ts",
             "--type", "js", "--type", "tsx", "--type", "kt", "--type", "php",
             rf"\b{re.escape(symbol)}\b", str(search_root)],
            capture_output=True, text=True, timeout=10,
        )
        lines = out.stdout.splitlines()[:max_results]
        return lines
    except Exception:
        return []


def detect_risk_scenarios(diff_text, sigs, changed_files, cwd):
    scenarios = []

    removed_keys = sigs.get("removed_keys", [])
    added_keys = sigs.get("added_keys", [])
    schema_changed = removed_keys or added_keys

    if schema_changed and any("api" in f.lower() or "schema" in f.lower() or "response" in f.lower() or "endpoint" in f.lower() for f in changed_files):
        scenarios.append({
            "category": "API shape 변경",
            "probability": "높음",
            "scenario": f"제거된 키 {removed_keys[:3]} / 추가된 키 {added_keys[:3]}. 프론트 캐시는 이전 shape를 들고 있음. 30분 내 토큰 refresh 또는 SWR 재요청 시 shape 불일치로 깨질 수 있음.",
            "mitigation": "프론트에서 새 shape를 핸들링하는지 확인. 캐시 무효화 또는 backward-compatible 필드 유지.",
        })

    if any("test" in f.lower() and ("removed" in diff_text or "skip" in diff_text.lower()) for f in changed_files):
        scenarios.append({
            "category": "테스트 약화",
            "probability": "중간",
            "scenario": "테스트가 삭제되거나 skip 처리됨. CI는 통과하지만 보호 범위가 줄어듦.",
            "mitigation": "삭제 사유 명시. 대체 테스트 추가 검토.",
        })

    sso_keywords = ["AUTH_MODE", "JWT", "SSO_", "Identity", "keycloak", "사용자", "kc.User"]
    if any(kw in diff_text for kw in sso_keywords):
        scenarios.append({
            "category": "SSO/인증 영향",
            "probability": "높음",
            "scenario": "인증 분기 코드 변경됨. AUTH_MODE 분기, Identity Hub 폴백, KC ↔ B2C 동기화 chain에 영향 가능. 30분 내 첫 사용자 로그인 시도에서 비대칭 발견.",
            "mitigation": "SSO 멀티 프로젝트 cross-check 실행 (/cross-check). 폴백 경로 수동 검증.",
        })

    env_changed = re.findall(r"^[+-].*?(?:os\.environ|process\.env|getenv)\.[\w'\[]+", diff_text, re.MULTILINE)
    if env_changed:
        scenarios.append({
            "category": "환경변수 의존성",
            "probability": "중간",
            "scenario": f"환경변수 참조 변경 {len(env_changed)}곳. 운영 환경에서 변수 미설정 시 30분 내 첫 부팅/배포에서 빈 값 또는 None 에러.",
            "mitigation": ".env.example 동기화. 배포 전 helm/k8s/ECS 환경변수 확인.",
        })

    if any(f.endswith(("/migrations/", ".sql")) for f in changed_files) or "migration" in diff_text.lower():
        scenarios.append({
            "category": "DB 스키마 변경",
            "probability": "높음",
            "scenario": "DB 마이그레이션 변경 감지. 백필 누락 시 NOT NULL 컬럼 추가, 인덱스 빌드 락, 운영 트랜잭션 차단 가능.",
            "mitigation": "스테이징에서 운영 데이터 사이즈로 dry-run. 락 모니터링 준비.",
        })

    if not scenarios:
        scenarios.append({
            "category": "낮은 위험",
            "probability": "낮음",
            "scenario": "API shape, 인증, 환경변수, DB 마이그레이션 변경 신호 미감지. 단순 내부 리팩터 가능성.",
            "mitigation": "테스트 통과 + 린트만 확인하면 충분할 가능성.",
        })

    callers_summary = {}
    for sym in (sigs.get("removed_functions", [])[:5] + sigs.get("removed_methods", [])[:5]):
        if isinstance(sym, tuple):
            sym = sym[0] or sym[1]
        if sym:
            callers = find_callers(sym, cwd)
            if callers:
                callers_summary[sym] = callers[:3]

    return scenarios, callers_summary


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--cwd", default=".", help="git repo")
    ap.add_argument("--mode", default="unstaged", choices=["unstaged", "staged", "head"])
    ap.add_argument("--json", action="store_true")
    args = ap.parse_args()

    cwd = os.path.abspath(args.cwd)
    diff = get_diff(cwd, args.mode)
    files = get_changed_files(cwd, args.mode)

    if not diff:
        print(f"diff 없음 (mode={args.mode}, cwd={cwd}). --mode head 또는 --mode staged 시도", file=sys.stderr)
        sys.exit(0)

    sigs = extract_signatures(diff)
    scenarios, callers = detect_risk_scenarios(diff, sigs, files, cwd)

    if args.json:
        print(json.dumps({
            "cwd": cwd,
            "mode": args.mode,
            "changed_files": files,
            "signatures": sigs,
            "scenarios": scenarios,
            "removed_symbol_callers": callers,
        }, indent=2, ensure_ascii=False))
        return

    print()
    print(f"# 30분 후 장애 예보 — `{Path(cwd).name}`")
    print()
    print(f"모드: `{args.mode}`, 변경 파일: {len(files)}개")
    print()
    if files:
        print("## 변경 파일")
        for f in files[:20]:
            print(f"- `{f}`")
        if len(files) > 20:
            print(f"- ... 외 {len(files)-20}개")
        print()

    print("## 위험 시나리오")
    print()
    for i, s in enumerate(scenarios, 1):
        print(f"### {i}. {s['category']} (확률: {s['probability']})")
        print(f"- **시나리오**: {s['scenario']}")
        print(f"- **완화**: {s['mitigation']}")
        print()

    if callers:
        print("## 제거된 심볼의 호출자")
        print()
        for sym, lines in callers.items():
            print(f"### `{sym}`")
            for l in lines:
                print(f"- {l}")
            print()

    print("---")
    print("⚠️ 이 예보는 휴리스틱 기반 MVP. Playwright/CI smoke 자동 실행은 별도 통합 필요.")


if __name__ == "__main__":
    main()
